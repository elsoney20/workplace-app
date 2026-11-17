import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_bootstrap.dart';
import '../domain/feed_post.dart';
import '../domain/person.dart';
import '../domain/post_attachment.dart';
import '../domain/post_comment.dart';
import 'media_compressor.dart';

/// Max size of one file (same limit as the database and storage bucket).
const int maxUploadBytes = 50 * 1024 * 1024;

/// A file chosen in the composer, not uploaded yet.
class PendingUpload {
  PendingUpload({required this.name, required this.bytes, String? mimeType})
    : mimeType =
          mimeType ??
          lookupMimeType(name, headerBytes: bytes) ??
          'application/octet-stream';

  final String name;
  final Uint8List bytes;
  final String mimeType;

  AttachmentKind get kind => mimeType.startsWith('image/')
      ? AttachmentKind.image
      : mimeType.startsWith('video/')
      ? AttachmentKind.video
      : AttachmentKind.file;

  bool get tooBig => bytes.length > maxUploadBytes;
}

class FeedPage {
  const FeedPage(this.posts, {required this.hasMore});
  final List<FeedPost> posts;
  final bool hasMore;
}

/// All feed reads and writes. The database (RLS + triggers) re-checks every
/// permission; hiding buttons in the app is only for convenience.
class FeedRepository {
  FeedRepository(SupabaseClient client) : _clientOrNull = client;

  /// For tests that replace every method (no network client needed).
  FeedRepository.withoutClient() : _clientOrNull = null;

  final SupabaseClient? _clientOrNull;
  SupabaseClient get _client => _clientOrNull!;
  static const String bucket = 'post-media';
  static const int pageSize = 20;

  StorageFileApi get _storage => _client.storage.from(bucket);

  // ------------------------------------------------------------------ reads
  Future<FeedPage> fetchFeed({
    String? hashtag,
    DateTime? before,
    String? groupId,
  }) async {
    final rows = await _client.rpc<List<dynamic>>(
      'get_feed',
      params: {
        'p_group_id': groupId,
        'p_hashtag': hashtag,
        // With a hashtag filter pinned posts are shown in the list itself.
        'p_pinned': hashtag == null ? false : null,
        'p_before': before?.toUtc().toIso8601String(),
        'p_limit': pageSize,
      },
    );
    final posts = rows
        .map((r) => FeedPost.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
    return FeedPage(posts, hasMore: posts.length == pageSize);
  }

  Future<List<FeedPost>> fetchPinned({String? groupId}) async {
    final rows = await _client.rpc<List<dynamic>>(
      'get_feed',
      params: {'p_group_id': groupId, 'p_pinned': true, 'p_limit': 10},
    );
    return rows
        .map((r) => FeedPost.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<FeedPost?> fetchPost(String postId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'get_feed',
      params: {'p_post_id': postId},
    );
    if (rows.isEmpty) return null;
    return FeedPost.fromJson(Map<String, dynamic>.from(rows.first as Map));
  }

  Future<List<PostComment>> fetchComments(String postId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'get_post_comments',
      params: {'p_post_id': postId},
    );
    return rows
        .map((r) => PostComment.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<List<(Person, String)>> fetchReactors({
    String? postId,
    String? commentId,
  }) async {
    final rows = await _client.rpc<List<dynamic>>(
      'get_reactors',
      params: {'p_post_id': postId, 'p_comment_id': commentId},
    );
    return [
      for (final r in rows.cast<Map>())
        (
          Person.fromJson(Map<String, dynamic>.from(r['person'] as Map)),
          r['emoji'] as String,
        ),
    ];
  }

  Future<List<(Person, DateTime)>> fetchViewers(String postId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'get_announcement_viewers',
      params: {'p_post_id': postId},
    );
    return [
      for (final r in rows.cast<Map>())
        (
          Person.fromJson(Map<String, dynamic>.from(r['person'] as Map)),
          DateTime.parse(r['seen_at'] as String).toLocal(),
        ),
    ];
  }

  Future<List<(String, int)>> fetchTrendingHashtags() async {
    final rows = await _client.rpc<List<dynamic>>(
      'get_trending_hashtags',
      params: {'p_limit': 10},
    );
    return [
      for (final r in rows.cast<Map>())
        (r['tag'] as String, (r['post_count'] as num).toInt()),
    ];
  }

  Future<List<Person>> searchPeople(String query) async {
    final rows = await _client.rpc<List<dynamic>>(
      'search_people',
      params: {'p_query': query, 'p_limit': 8},
    );
    return [
      for (final r in rows.cast<Map>())
        Person.fromJson(Map<String, dynamic>.from(r['person'] as Map)),
    ];
  }

  /// Short-lived links (1 hour) to open private files.
  Future<Map<String, String>> signedUrls(List<String> paths) async {
    if (paths.isEmpty) return const {};
    final results = await _storage.createSignedUrlsResult(paths, 3600);
    return {
      for (final r in results)
        if (r is SignedUrlSuccess) r.path: r.signedUrl,
    };
  }

  // ----------------------------------------------------------------- writes

  /// Creates the post, then uploads its files into `post-media/<post_id>/`.
  /// If an upload fails, the half-made post is removed again.
  Future<String> createPost({
    required String authorId,
    required String body,
    required List<PendingUpload> uploads,
    bool announcement = false,
    String? groupId,
    void Function(int done, int total)? onProgress,
  }) async {
    final row = await _client
        .from('posts')
        .insert({
          'author_id': authorId,
          'body': body,
          'group_id': groupId,
          'is_announcement': announcement,
          'is_pinned': announcement,
        })
        .select('id')
        .single();
    final postId = row['id'] as String;

    final uploaded = <String>[];
    try {
      for (var i = 0; i < uploads.length; i++) {
        onProgress?.call(i, uploads.length);
        uploaded.add(await _uploadAttachment(postId, uploads[i], i));
      }
      onProgress?.call(uploads.length, uploads.length);
    } catch (_) {
      if (uploaded.isNotEmpty) {
        await _storage.remove(uploaded).catchError((_) => <FileObject>[]);
      }
      await _client
          .from('posts')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', postId);
      rethrow;
    }
    return postId;
  }

  Future<String> _uploadAttachment(
    String postId,
    PendingUpload upload,
    int order,
  ) async {
    var bytes = upload.bytes;
    var mimeType = upload.mimeType;
    int? width;
    int? height;
    if (upload.kind == AttachmentKind.image) {
      final compressed = await MediaCompressor.compressImage(bytes, mimeType);
      if (compressed != null) {
        bytes = compressed.bytes;
        mimeType = compressed.mimeType;
        width = compressed.width;
        height = compressed.height;
      }
    }
    if (bytes.length > maxUploadBytes) {
      throw const FileTooBigException();
    }
    final path =
        '$postId/${DateTime.now().microsecondsSinceEpoch}_${_safeFileName(upload.name, mimeType)}';
    await _storage.uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: mimeType),
    );
    await _client.from('post_attachments').insert({
      'post_id': postId,
      'storage_path': path,
      'kind': upload.kind.name,
      'mime_type': mimeType,
      'file_name': upload.name,
      'size_bytes': bytes.length,
      'width': width,
      'height': height,
      'sort_order': order,
    });
    return path;
  }

  Future<void> updatePostBody(String postId, String body) =>
      _client.from('posts').update({'body': body}).eq('id', postId);

  Future<void> deletePost(String postId) => _client
      .from('posts')
      .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
      .eq('id', postId);

  /// Moderators only: pin to the top / make an announcement.
  Future<void> setPinned(String postId, {required bool pinned}) => _client
      .from('posts')
      .update({'is_pinned': pinned, if (pinned) 'is_announcement': true})
      .eq('id', postId);

  Future<void> setCommentsLocked(String postId, {required bool locked}) =>
      _client
          .from('posts')
          .update({'comments_locked': locked})
          .eq('id', postId);

  Future<void> markSeen(String postId) => _client.rpc<void>(
    'mark_announcement_seen',
    params: {'p_post_id': postId},
  );

  /// Sets (or replaces) my reaction. `emoji == null` removes it.
  Future<void> setReaction({
    required String profileId,
    String? postId,
    String? commentId,
    String? emoji,
  }) async {
    final column = postId != null ? 'post_id' : 'comment_id';
    final target = postId ?? commentId!;
    await _client
        .from('reactions')
        .delete()
        .eq('profile_id', profileId)
        .eq(column, target);
    if (emoji != null) {
      await _client.from('reactions').insert({
        'profile_id': profileId,
        column: target,
        'emoji': emoji,
      });
    }
  }

  Future<void> addComment({
    required String postId,
    required String authorId,
    required String body,
    String? parentId,
  }) => _client.from('comments').insert({
    'post_id': postId,
    'author_id': authorId,
    'body': body,
    'parent_id': parentId,
  });

  Future<void> updateComment(String commentId, String body) =>
      _client.from('comments').update({'body': body}).eq('id', commentId);

  Future<void> deleteComment(String commentId) => _client
      .from('comments')
      .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
      .eq('id', commentId);

  /// Live updates: calls [onChange] when posts, comments or reactions change.
  RealtimeChannel watchFeed(void Function() onChange, {String? groupId}) {
    final channel = _client.channel('feed-changes-${groupId ?? 'company'}');
    for (final table in [
      'posts',
      'comments',
      'reactions',
      'post_attachments',
    ]) {
      channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => onChange(),
      );
    }
    return channel..subscribe();
  }

  Future<void> stopWatching(RealtimeChannel channel) =>
      _client.removeChannel(channel);
}

class FileTooBigException implements Exception {
  const FileTooBigException();
}

/// Storage keys must be simple: keep letters, digits, dot, dash, underscore.
String _safeFileName(String name, String mimeType) {
  var base = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  if (base.replaceAll(RegExp(r'[_.]'), '').isEmpty) base = 'file';
  if (base.length > 80) base = base.substring(base.length - 80);
  if (mimeType == 'image/jpeg' &&
      !RegExp(r'\.jpe?g$', caseSensitive: false).hasMatch(base)) {
    base = '${base.replaceAll(RegExp(r'\.[A-Za-z0-9]+$'), '')}.jpg';
  }
  return base;
}

final feedRepositoryProvider = Provider<FeedRepository>(
  (ref) => FeedRepository(ref.watch(supabaseClientProvider)),
);
