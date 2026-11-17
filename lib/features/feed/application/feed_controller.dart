import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/feed_repository.dart';
import '../domain/feed_post.dart';

/// What the feed screen shows.
class FeedState {
  const FeedState({
    this.pinned = const [],
    this.posts = const [],
    this.hasMore = true,
    this.loadingMore = false,
    this.hashtag,
  });

  final List<FeedPost> pinned;
  final List<FeedPost> posts;
  final bool hasMore;
  final bool loadingMore;

  /// Active #hashtag filter (lower-case, without '#'), or null.
  final String? hashtag;

  FeedState copyWith({
    List<FeedPost>? pinned,
    List<FeedPost>? posts,
    bool? hasMore,
    bool? loadingMore,
  }) => FeedState(
    pinned: pinned ?? this.pinned,
    posts: posts ?? this.posts,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    hashtag: hashtag,
  );

  FeedState mapPosts(FeedPost Function(FeedPost) change) => copyWith(
    pinned: pinned.map(change).toList(),
    posts: posts.map(change).toList(),
  );
}

/// The active #hashtag filter of the company feed.
class HashtagFilter extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? tag) => state = tag?.replaceFirst('#', '').toLowerCase();
}

/// One filter per feed: `null` = company feed, otherwise a group id.
final hashtagFilterProvider =
    NotifierProvider.family<HashtagFilter, String?, String?>(
      (groupId) => HashtagFilter(),
    );

/// Company feed: pinned announcements + newest posts, with paging and live
/// updates.
class FeedController extends AsyncNotifier<FeedState> {
  FeedController(this.groupId);

  /// `null` = company feed, otherwise this group's feed.
  final String? groupId;
  Timer? _debounce;

  FeedRepository get _repo => ref.read(feedRepositoryProvider);

  @override
  Future<FeedState> build() async {
    final hashtag = ref.watch(hashtagFilterProvider(groupId));
    final repo = ref.watch(feedRepositoryProvider);

    final channel = repo.watchFeed(_scheduleRefresh, groupId: groupId);
    ref.onDispose(() {
      _debounce?.cancel();
      unawaited(repo.stopWatching(channel).catchError((_) => 'error'));
    });

    final results = await Future.wait([
      hashtag == null
          ? repo.fetchPinned(groupId: groupId)
          : Future.value(const <FeedPost>[]),
      repo.fetchFeed(hashtag: hashtag, groupId: groupId),
    ]);
    final page = results[1] as FeedPage;
    return FeedState(
      pinned: results[0] as List<FeedPost>,
      posts: page.posts,
      hasMore: page.hasMore,
      hashtag: hashtag,
    );
  }

  /// Several changes in a row (e.g. a post with 5 photos) = one refresh.
  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 1200),
      () => unawaited(refresh()),
    );
  }

  /// Reloads the newest page and keeps older pages that were already loaded.
  Future<void> refresh() async {
    final current = state.value;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }
    try {
      final results = await Future.wait([
        current.hashtag == null
            ? _repo.fetchPinned(groupId: groupId)
            : Future.value(const <FeedPost>[]),
        _repo.fetchFeed(hashtag: current.hashtag, groupId: groupId),
      ]);
      final page = results[1] as FeedPage;
      final oldest = page.posts.isEmpty ? null : page.posts.last.createdAt;
      final older = oldest == null
          ? const <FeedPost>[]
          : current.posts.where((p) => p.createdAt.isBefore(oldest)).toList();
      state = AsyncData(
        current.copyWith(
          pinned: results[0] as List<FeedPost>,
          posts: [...page.posts, ...older],
          hasMore: older.isNotEmpty ? current.hasMore : page.hasMore,
        ),
      );
    } catch (_) {
      // Keep showing what we have; the next change or pull will retry.
    }
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null ||
        !current.hasMore ||
        current.loadingMore ||
        current.posts.isEmpty) {
      return;
    }
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await _repo.fetchFeed(
        hashtag: current.hashtag,
        before: current.posts.last.createdAt,
        groupId: groupId,
      );
      final latest = state.value ?? current;
      final known = latest.posts.map((p) => p.id).toSet();
      state = AsyncData(
        latest.copyWith(
          posts: [
            ...latest.posts,
            ...page.posts.where((p) => !known.contains(p.id)),
          ],
          hasMore: page.hasMore,
          loadingMore: false,
        ),
      );
    } catch (_) {
      state = AsyncData((state.value ?? current).copyWith(loadingMore: false));
    }
  }

  /// Shows my reaction immediately, then saves it.
  Future<void> react(String postId, String profileId, String? emoji) async {
    final before = state.value;
    if (before != null) {
      state = AsyncData(
        before.mapPosts((p) => p.id == postId ? p.withMyReaction(emoji) : p),
      );
    }
    try {
      await _repo.setReaction(
        profileId: profileId,
        postId: postId,
        emoji: emoji,
      );
    } catch (_) {
      if (before != null) state = AsyncData(before);
      rethrow;
    }
  }

  /// Removes a post from the screen right away (after delete).
  void removeLocally(String postId) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        pinned: current.pinned.where((p) => p.id != postId).toList(),
        posts: current.posts.where((p) => p.id != postId).toList(),
      ),
    );
  }
}

/// One controller per feed: `null` = company feed, otherwise a group id.
final feedControllerProvider =
    AsyncNotifierProvider.family<FeedController, FeedState, String?>(
      FeedController.new,
    );

final trendingHashtagsProvider =
    FutureProvider.autoDispose<List<(String, int)>>(
      (ref) => ref.watch(feedRepositoryProvider).fetchTrendingHashtags(),
    );
