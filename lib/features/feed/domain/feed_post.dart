import 'person.dart';
import 'poll.dart';
import 'post_attachment.dart';

/// One post as returned by `public.get_feed()`.
class FeedPost {
  const FeedPost({
    required this.id,
    required this.author,
    required this.body,
    required this.createdAt,
    this.groupId,
    this.isAnnouncement = false,
    this.isPinned = false,
    this.commentsLocked = false,
    this.editedAt,
    this.attachments = const [],
    this.commentCount = 0,
    this.reactions = const {},
    this.myReaction,
    this.seenCount = 0,
    this.seenByMe = false,
    this.audienceCount,
    this.poll,
  });

  factory FeedPost.fromJson(Map<String, dynamic> json) => FeedPost(
    id: json['id'] as String,
    groupId: json['group_id'] as String?,
    author: Person.fromJson(_map(json['author'])),
    body: json['body'] as String? ?? '',
    isAnnouncement: json['is_announcement'] as bool? ?? false,
    isPinned: json['is_pinned'] as bool? ?? false,
    commentsLocked: json['comments_locked'] as bool? ?? false,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    editedAt: json['edited_at'] == null
        ? null
        : DateTime.parse(json['edited_at'] as String).toLocal(),
    attachments: [
      for (final a in (json['attachments'] as List? ?? const []))
        PostAttachment.fromJson(Map<String, dynamic>.from(a as Map)),
    ],
    commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
    reactions: reactionCountsFromJson(json['reactions']),
    myReaction: json['my_reaction'] as String?,
    seenCount: (json['seen_count'] as num?)?.toInt() ?? 0,
    seenByMe: json['seen_by_me'] as bool? ?? false,
    audienceCount: (json['audience_count'] as num?)?.toInt(),
  );

  final String id;
  final String? groupId;
  final Person author;

  /// Raw text including mention markup `@[Name](id)`.
  final String body;
  final bool isAnnouncement;
  final bool isPinned;
  final bool commentsLocked;
  final DateTime createdAt;
  final DateTime? editedAt;
  final List<PostAttachment> attachments;
  final int commentCount;

  /// emoji -> how many people reacted with it.
  final Map<String, int> reactions;
  final String? myReaction;
  final int seenCount;
  final bool seenByMe;
  final int? audienceCount;

  /// A quick poll inside the post (loaded separately, see get_polls).
  final Poll? poll;

  int get reactionTotal => reactions.values.fold(0, (a, b) => a + b);

  /// Local, optimistic change of my reaction (null = remove).
  FeedPost withMyReaction(String? emoji) {
    final counts = Map<String, int>.from(reactions);
    if (myReaction != null) {
      final left = (counts[myReaction!] ?? 1) - 1;
      if (left <= 0) {
        counts.remove(myReaction);
      } else {
        counts[myReaction!] = left;
      }
    }
    if (emoji != null) counts[emoji] = (counts[emoji] ?? 0) + 1;
    return FeedPost(
      id: id,
      groupId: groupId,
      author: author,
      body: body,
      isAnnouncement: isAnnouncement,
      isPinned: isPinned,
      commentsLocked: commentsLocked,
      createdAt: createdAt,
      editedAt: editedAt,
      attachments: attachments,
      commentCount: commentCount,
      reactions: counts,
      myReaction: emoji,
      seenCount: seenCount,
      seenByMe: seenByMe,
      audienceCount: audienceCount,
      poll: poll,
    );
  }

  FeedPost withPoll(Poll? poll) => FeedPost(
    id: id,
    groupId: groupId,
    author: author,
    body: body,
    isAnnouncement: isAnnouncement,
    isPinned: isPinned,
    commentsLocked: commentsLocked,
    createdAt: createdAt,
    editedAt: editedAt,
    attachments: attachments,
    commentCount: commentCount,
    reactions: reactions,
    myReaction: myReaction,
    seenCount: seenCount,
    seenByMe: seenByMe,
    audienceCount: audienceCount,
    poll: poll,
  );
}

Map<String, int> reactionCountsFromJson(Object? value) {
  final map = _map(value);
  if (map == null) return const {};
  final entries =
      map.entries.map((e) => MapEntry(e.key, (e.value as num).toInt())).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
  return Map.fromEntries(entries);
}

Map<String, dynamic>? _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;
