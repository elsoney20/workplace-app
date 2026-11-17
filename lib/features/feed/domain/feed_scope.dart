/// Which feed a screen shows and what the current person may do in it.
/// The database re-checks all of this; it only decides which buttons show.
class FeedScope {
  const FeedScope({
    this.groupId,
    required this.canModerate,
    this.canPost = true,
  });

  /// Company feed (admins moderate it).
  const FeedScope.company({required bool isAdmin}) : this(canModerate: isAdmin);

  /// `null` = company feed.
  final String? groupId;

  /// Pin/announce, lock comments, delete anyone's post.
  final bool canModerate;

  /// Members (or moderators) can post; others only read.
  final bool canPost;
}
