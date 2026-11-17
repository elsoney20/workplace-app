import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/widgets/motion.dart';
import '../../auth/domain/my_profile.dart';
import '../../moderation/presentation/report_dialog.dart';
import '../application/feed_controller.dart';
import '../data/feed_repository.dart';
import '../domain/feed_post.dart';
import '../domain/feed_scope.dart';
import 'animated_emoji.dart';
import 'attachments_view.dart';
import 'comments_dialog.dart';
import 'feed_format.dart';
import 'people_dialogs.dart';
import 'person_avatar.dart';
import 'post_composer_dialog.dart';
import 'reaction_picker.dart';
import 'rich_body.dart';

/// Announcements this app session already reported as seen.
final Set<String> _reportedSeen = {};

class PostCard extends ConsumerStatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.me,
    required this.scope,
    this.onHashtag,
  });

  final FeedPost post;
  final MyProfile me;
  final FeedScope scope;
  final void Function(String tag)? onHashtag;

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

enum _MenuAction { edit, delete, pin, unpin, lock, unlock, seenBy, report }

class _PostCardState extends ConsumerState<PostCard> {
  bool _showComments = false;

  FeedPost get post => widget.post;
  bool get _mine => post.author.id == widget.me.id;

  bool get _canModerate => widget.scope.canModerate;

  @override
  void initState() {
    super.initState();
    _reportSeen();
  }

  @override
  void didUpdateWidget(PostCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reportSeen();
  }

  void _reportSeen() {
    if (!post.isAnnouncement ||
        post.seenByMe ||
        _reportedSeen.contains(post.id)) {
      return;
    }
    _reportedSeen.add(post.id);
    ref
        .read(feedRepositoryProvider)
        .markSeen(post.id)
        .catchError((_) => _reportedSeen.remove(post.id));
  }

  Future<void> _react(BuildContext anchor) async {
    final choice = await showReactionPicker(anchor, current: post.myReaction);
    if (choice == null) return;
    final emoji = choice is ReactionPicked ? choice.emoji : null;
    try {
      await ref
          .read(feedControllerProvider(widget.scope.groupId).notifier)
          .react(post.id, widget.me.id, emoji);
    } catch (_) {
      if (mounted) _snack(AppLocalizations.of(context).errorUnknown);
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _onMenu(_MenuAction action) async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(feedRepositoryProvider);
    final feed = ref.read(
      feedControllerProvider(widget.scope.groupId).notifier,
    );
    try {
      switch (action) {
        case _MenuAction.edit:
          if (await showPostComposer(
            context,
            me: widget.me,
            scope: widget.scope,
            editing: post,
          )) {
            await feed.refresh();
          }
        case _MenuAction.delete:
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              content: Text(l10n.deletePostConfirm),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(l10n.delete),
                ),
              ],
            ),
          );
          if (ok != true) return;
          await repo.deletePost(post.id);
          feed.removeLocally(post.id);
        case _MenuAction.pin:
          await repo.setPinned(post.id, pinned: true);
          await feed.refresh();
        case _MenuAction.unpin:
          await repo.setPinned(post.id, pinned: false);
          await feed.refresh();
        case _MenuAction.lock:
          await repo.setCommentsLocked(post.id, locked: true);
          await feed.refresh();
        case _MenuAction.unlock:
          await repo.setCommentsLocked(post.id, locked: false);
          await feed.refresh();
        case _MenuAction.report:
          await showReportDialog(context, ref, postId: post.id);
        case _MenuAction.seenBy:
          if (mounted) {
            await showSeenByDialog(
              context,
              postId: post.id,
              total: post.audienceCount,
            );
          }
      }
    } catch (_) {
      if (mounted) _snack(l10n.errorUnknown);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canSeeViewers = post.isAnnouncement && (_mine || _canModerate);

    final menu = <PopupMenuEntry<_MenuAction>>[
      if (_mine) PopupMenuItem(value: _MenuAction.edit, child: Text(l10n.edit)),
      if (_mine || _canModerate)
        PopupMenuItem(value: _MenuAction.delete, child: Text(l10n.delete)),
      if (_canModerate && !post.isPinned)
        PopupMenuItem(value: _MenuAction.pin, child: Text(l10n.pinPost)),
      if (_canModerate && post.isPinned)
        PopupMenuItem(value: _MenuAction.unpin, child: Text(l10n.unpinPost)),
      if (_canModerate && !post.commentsLocked)
        PopupMenuItem(value: _MenuAction.lock, child: Text(l10n.lockComments)),
      if (_canModerate && post.commentsLocked)
        PopupMenuItem(
          value: _MenuAction.unlock,
          child: Text(l10n.unlockComments),
        ),
      if (canSeeViewers)
        PopupMenuItem(value: _MenuAction.seenBy, child: Text(l10n.seenByTitle)),
      if (!_mine)
        PopupMenuItem(
          key: Key('reportPost-${post.id}'),
          value: _MenuAction.report,
          child: Text(l10n.reportAction),
        ),
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: post.isAnnouncement
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.primary, width: 1.5),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (post.isAnnouncement || post.isPinned)
            Container(
              color: scheme.primaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    post.isAnnouncement ? Icons.campaign : Icons.push_pin,
                    size: 18,
                    color: scheme.onPrimaryContainer,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    [
                      if (post.isAnnouncement) l10n.announcementBadge,
                      if (post.isPinned) l10n.pinnedBadge,
                    ].join(' · '),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ListTile(
            leading: PersonAvatar(post.author),
            title: Text(
              post.author.fullName,
              style: theme.textTheme.titleMedium,
            ),
            subtitle: Tooltip(
              message: fullTime(context, post.createdAt),
              child: Text(
                [
                  ?post.author.jobTitle,
                  timeAgo(context, post.createdAt),
                  if (post.editedAt != null) l10n.edited,
                ].join(' · '),
              ),
            ),
            trailing: menu.isEmpty
                ? null
                : PopupMenuButton<_MenuAction>(
                    key: Key('postMenu-${post.id}'),
                    onSelected: _onMenu,
                    itemBuilder: (_) => menu,
                  ),
          ),
          if (post.body.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: RichBody(post.body, onHashtag: widget.onHashtag),
            ),
          if (post.attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AttachmentsView(attachments: post.attachments),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                ReactionSummary(
                  reactions: post.reactions,
                  onTap: () => showReactorsDialog(context, postId: post.id),
                ),
                const Spacer(),
                if (post.commentCount > 0)
                  TextButton(
                    onPressed: () => _openComments(),
                    child: Text(l10n.commentCount(post.commentCount)),
                  ),
                if (canSeeViewers)
                  TextButton.icon(
                    key: Key('seenBy-${post.id}'),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                    onPressed: () => showSeenByDialog(
                      context,
                      postId: post.id,
                      total: post.audienceCount,
                    ),
                    label: Text(
                      post.audienceCount == null
                          ? l10n.seenBy(post.seenCount)
                          : l10n.seenByOf(post.seenCount, post.audienceCount!),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Row(
            children: [
              Expanded(
                child: Builder(
                  builder: (anchor) => TextButton.icon(
                    key: Key('reactButton-${post.id}'),
                    onPressed: () => _react(anchor),
                    icon: PopOnChange(
                      trigger: post.myReaction,
                      child: post.myReaction == null
                          ? const Icon(Icons.thumb_up_outlined)
                          : AnimatedEmoji(
                              post.myReaction!,
                              size: 22,
                              onHover: true,
                            ),
                    ),
                    label: Text(l10n.react),
                  ),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  key: Key('commentButton-${post.id}'),
                  onPressed: _openComments,
                  icon: Icon(
                    post.commentsLocked
                        ? Icons.lock_outline
                        : Icons.mode_comment_outlined,
                  ),
                  label: Text(l10n.comment),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: kSmooth,
            alignment: Alignment.topCenter,
            child: _showComments
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Divider(height: 1),
                      CommentsSection(
                        key: Key('comments-${post.id}'),
                        post: post,
                        me: widget.me,
                        canModerate: widget.scope.canModerate,
                        onHashtag: widget.onHashtag,
                        inline: true,
                        onChanged: _commentsChanged,
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  /// Comments open right under the post (like Facebook).
  void _openComments() => setState(() => _showComments = !_showComments);

  void _commentsChanged() => unawaited(
    ref.read(feedControllerProvider(widget.scope.groupId).notifier).refresh(),
  );
}
