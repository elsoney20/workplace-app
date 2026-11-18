import 'feed_post.dart';
import 'person.dart';

/// One comment as returned by `public.get_post_comments()`.
class PostComment {
  const PostComment({
    required this.id,
    required this.postId,
    required this.author,
    required this.body,
    required this.createdAt,
    this.parentId,
    this.editedAt,
    this.reactions = const {},
    this.myReaction,
  });

  factory PostComment.fromJson(Map<String, dynamic> json) => PostComment(
    id: json['id'] as String,
    postId: json['post_id'] as String,
    parentId: json['parent_id'] as String?,
    author: Person.fromJson(
      json['author'] is Map
          ? Map<String, dynamic>.from(json['author'] as Map)
          : null,
    ),
    body: json['body'] as String? ?? '',
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    editedAt: json['edited_at'] == null
        ? null
        : DateTime.parse(json['edited_at'] as String).toLocal(),
    reactions: reactionCountsFromJson(json['reactions']),
    myReaction: json['my_reaction'] as String?,
  );

  final String id;
  final String postId;
  final String? parentId;
  final Person author;
  final String body;
  final DateTime createdAt;
  final DateTime? editedAt;
  final Map<String, int> reactions;
  final String? myReaction;
}
