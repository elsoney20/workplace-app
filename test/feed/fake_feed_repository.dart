import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workplace_app/features/feed/data/feed_repository.dart';
import 'package:workplace_app/features/feed/domain/feed_post.dart';
import 'package:workplace_app/features/feed/domain/person.dart';
import 'package:workplace_app/features/feed/domain/post_comment.dart';

/// In-memory feed for widget tests (no network).
class FakeFeedRepository extends FeedRepository {
  FakeFeedRepository({List<FeedPost>? posts, List<FeedPost>? pinned})
    : posts = posts ?? [],
      pinned = pinned ?? [],
      super.withoutClient();

  final List<FeedPost> posts;
  final List<FeedPost> pinned;
  final List<String> created = [];
  final List<(String, String?)> reactions = [];
  final List<String> seen = [];

  /// How many times the company feed was loaded from the start.
  int feedLoads = 0;

  @override
  Future<FeedPage> fetchFeed({
    String? hashtag,
    DateTime? before,
    String? groupId,
  }) async {
    if (groupId == null && hashtag == null && before == null) feedLoads++;
    final list = hashtag == null
        ? posts
        : [
            ...pinned,
            ...posts,
          ].where((p) => p.body.toLowerCase().contains('#$hashtag')).toList();
    return FeedPage(before == null ? list : const [], hasMore: false);
  }

  @override
  Future<FeedPost?> fetchPost(String postId) async =>
      [...pinned, ...posts].where((p) => p.id == postId).firstOrNull;

  @override
  Future<List<FeedPost>> fetchPinned({String? groupId}) async => pinned;

  @override
  Future<List<(String, int)>> fetchTrendingHashtags() async => const [
    ('sales', 3),
  ];

  @override
  Future<List<PostComment>> fetchComments(String postId) async =>
      comments[postId] ?? const [];

  /// Comments per post id.
  final Map<String, List<PostComment>> comments = {};

  @override
  Future<List<Person>> searchPeople(String query) async => const [
    Person(
      id: '00000000-0000-0000-0000-0000000000a1',
      fullName: 'Sara Ali',
      jobTitle: 'Sales',
    ),
  ];

  final List<({String question, List<String> options})> createdPolls = [];
  final List<(String, String?)> votes = [];

  @override
  Future<void> votePoll(String postId, String? optionId) async =>
      votes.add((postId, optionId));

  @override
  Future<String> createPost({
    required String authorId,
    required String body,
    required List<PendingUpload> uploads,
    bool announcement = false,
    String? groupId,
    ({String question, List<String> options})? poll,
    void Function(int done, int total)? onProgress,
  }) async {
    created.add(body);
    if (poll != null) createdPolls.add(poll);
    posts.insert(
      0,
      FeedPost(
        id: 'new-${created.length}',
        author: Person(id: authorId, fullName: 'Owner'),
        body: body,
        createdAt: DateTime.now(),
        isAnnouncement: announcement,
      ),
    );
    return 'new-${created.length}';
  }

  @override
  Future<void> setReaction({
    required String profileId,
    String? postId,
    String? commentId,
    String? emoji,
  }) async {
    reactions.add((postId ?? commentId!, emoji));
  }

  @override
  Future<void> markSeen(String postId) async => seen.add(postId);

  @override
  RealtimeChannel watchFeed(void Function() onChange, {String? groupId}) =>
      _NoopChannel();

  @override
  Future<void> stopWatching(RealtimeChannel channel) async {}
}

class _NoopChannel implements RealtimeChannel {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
