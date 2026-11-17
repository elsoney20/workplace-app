import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_bootstrap.dart';
import '../../feed/data/feed_repository.dart'
    show PendingUpload, FileTooBigException, maxUploadBytes;
import '../../feed/data/media_compressor.dart';
import '../../feed/domain/person.dart';
import '../../feed/domain/post_attachment.dart';
import '../domain/chat_message.dart';
import '../domain/conversation.dart';

/// Chat reads and writes. PRIVACY is enforced by the database: only members
/// of a conversation can read it (no admin exception).
class ChatRepository {
  ChatRepository(SupabaseClient client) : _clientOrNull = client;

  /// For tests that replace every method.
  ChatRepository.withoutClient() : _clientOrNull = null;

  final SupabaseClient? _clientOrNull;
  SupabaseClient get _client => _clientOrNull!;

  static const String bucket = 'chat-media';
  static const int pageSize = 40;

  Future<List<Conversation>> listConversations() async {
    final rows = await _client.rpc<List<dynamic>>('list_conversations');
    return rows
        .map((r) => Conversation.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<String> openDirect(String otherProfileId) => _client.rpc<String>(
    'get_or_create_direct_conversation',
    params: {'p_other_profile_id': otherProfileId},
  );

  Future<String> createGroup(String title, List<String> memberIds) =>
      _client.rpc<String>(
        'create_group_conversation',
        params: {'p_title': title, 'p_member_ids': memberIds},
      );

  Future<List<ChatMessage>> fetchMessages(
    String conversationId, {
    DateTime? before,
  }) async {
    final rows = await _client.rpc<List<dynamic>>(
      'get_messages',
      params: {
        'p_conversation_id': conversationId,
        'p_before': before?.toUtc().toIso8601String(),
        'p_limit': pageSize,
      },
    );
    return rows
        .map((r) => ChatMessage.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<List<MessageReceipt>> fetchReceipts(String messageId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'get_message_receipts',
      params: {'p_message_id': messageId},
    );
    return [
      for (final r in rows.cast<Map>())
        MessageReceipt(
          Person.fromJson(Map<String, dynamic>.from(r['person'] as Map)),
          r['delivered_at'] == null
              ? null
              : DateTime.parse(r['delivered_at'] as String).toLocal(),
          r['seen_at'] == null
              ? null
              : DateTime.parse(r['seen_at'] as String).toLocal(),
        ),
    ];
  }

  Future<List<(Person, bool)>> fetchMembers(String conversationId) async {
    final rows = await _client.rpc<List<dynamic>>(
      'get_conversation_members',
      params: {'p_conversation_id': conversationId},
    );
    return [
      for (final r in rows.cast<Map>())
        (
          Person.fromJson(Map<String, dynamic>.from(r['person'] as Map)),
          r['role'] == 'owner',
        ),
    ];
  }

  /// Sends a message, then uploads its files to `chat-media/<conversation>/`.
  Future<String> send({
    required String conversationId,
    required String senderId,
    required String body,
    String? replyToId,
    List<PendingUpload> uploads = const [],
  }) async {
    final row = await _client
        .from('messages')
        .insert({
          'conversation_id': conversationId,
          'sender_id': senderId,
          'body': body,
          'reply_to_id': replyToId,
        })
        .select('id')
        .single();
    final messageId = row['id'] as String;
    for (final upload in uploads) {
      await _uploadAttachment(conversationId, messageId, upload);
    }
    return messageId;
  }

  Future<void> _uploadAttachment(
    String conversationId,
    String messageId,
    PendingUpload upload,
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
    if (bytes.length > maxUploadBytes) throw const FileTooBigException();
    final safe = upload.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path =
        '$conversationId/${DateTime.now().microsecondsSinceEpoch}_${safe.isEmpty ? 'file' : safe}';
    await _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType),
        );
    await _client.from('message_attachments').insert({
      'message_id': messageId,
      'storage_path': path,
      'kind': upload.kind.name,
      'mime_type': mimeType,
      'file_name': upload.name,
      'size_bytes': bytes.length,
      'width': width,
      'height': height,
    });
  }

  Future<void> edit(String messageId, String body) =>
      _client.from('messages').update({'body': body}).eq('id', messageId);

  /// "Delete for everyone": the server wipes the text and attachments.
  Future<void> deleteForEveryone(String messageId) => _client
      .from('messages')
      .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
      .eq('id', messageId);

  Future<void> addReaction(String messageId, String profileId, String emoji) =>
      _client.from('message_reactions').upsert({
        'message_id': messageId,
        'profile_id': profileId,
        'emoji': emoji,
      }, ignoreDuplicates: true);

  Future<void> removeReaction(
    String messageId,
    String profileId,
    String emoji,
  ) => _client
      .from('message_reactions')
      .delete()
      .eq('message_id', messageId)
      .eq('profile_id', profileId)
      .eq('emoji', emoji);

  Future<void> markDelivered(String conversationId) => _client.rpc<void>(
    'mark_conversation_delivered',
    params: {'p_conversation_id': conversationId},
  );

  Future<void> markSeen(String conversationId) => _client.rpc<void>(
    'mark_conversation_seen',
    params: {'p_conversation_id': conversationId},
  );

  Future<void> rename(String conversationId, String title) => _client
      .from('conversations')
      .update({'title': title})
      .eq('id', conversationId);

  Future<void> addMember(String conversationId, String profileId) => _client
      .from('conversation_members')
      .insert({'conversation_id': conversationId, 'profile_id': profileId});

  Future<void> removeMember(String conversationId, String profileId) => _client
      .from('conversation_members')
      .delete()
      .eq('conversation_id', conversationId)
      .eq('profile_id', profileId);

  Future<void> leave(String conversationId) => _client.rpc<void>(
    'leave_group_conversation',
    params: {'p_conversation_id': conversationId},
  );

  Future<void> setMuted(
    String conversationId,
    String profileId, {
    required bool muted,
  }) => _client
      .from('conversation_members')
      .update({'muted': muted})
      .eq('conversation_id', conversationId)
      .eq('profile_id', profileId);

  // ------------------------------------------------------------- realtime

  /// New/changed messages, receipts and reactions in any of my chats.
  /// RLS makes sure only my own chats' rows ever arrive.
  RealtimeChannel watchInbox(void Function() onChange) {
    final channel = _client.channel('chat-inbox');
    for (final table in [
      'messages',
      'message_receipts',
      'message_reactions',
      'conversation_members',
      'conversations',
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

  /// Private live channel of one chat, used for "typing…" signals.
  /// Only members may join (Realtime Authorization, see Phase 5 migration).
  RealtimeChannel typingChannel(
    String conversationId,
    void Function(String profileId, String name) onTyping,
  ) {
    final channel = _client.channel(
      'chat:$conversationId',
      opts: const RealtimeChannelConfig(private: true),
    );
    channel.onBroadcast(
      event: 'typing',
      callback: (payload) {
        final id = payload['profile_id'];
        final name = payload['name'];
        if (id is String && name is String) onTyping(id, name);
      },
    );
    return channel..subscribe();
  }

  Future<void> sendTyping(
    RealtimeChannel channel,
    String profileId,
    String name,
  ) => channel.sendBroadcastMessage(
    event: 'typing',
    payload: {'profile_id': profileId, 'name': name},
  );

  /// Shared "who is online" channel.
  RealtimeChannel presenceChannel(
    String profileId,
    void Function(Set<String> online) onChange,
  ) {
    final channel = _client.channel(
      'presence:online',
      opts: RealtimeChannelConfig(private: true, key: profileId),
    );
    void emit() {
      final ids = <String>{};
      for (final state in channel.presenceState()) {
        for (final p in state.presences) {
          final id = p.payload['profile_id'];
          if (id is String) ids.add(id);
        }
      }
      onChange(ids);
    }

    channel
      ..onPresenceSync((_) => emit())
      ..onPresenceJoin((_) => emit())
      ..onPresenceLeave((_) => emit())
      ..subscribe((status, error) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          await channel.track({'profile_id': profileId});
        }
      });
    return channel;
  }

  Future<void> stop(RealtimeChannel channel) => _client.removeChannel(channel);
}

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.watch(supabaseClientProvider)),
);
