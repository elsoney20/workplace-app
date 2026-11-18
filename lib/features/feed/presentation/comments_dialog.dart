import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../auth/domain/my_profile.dart';
import '../../moderation/presentation/report_dialog.dart';
import '../data/feed_repository.dart';
import '../domain/feed_post.dart';
import '../domain/post_comment.dart';
import 'feed_format.dart';
import 'mention_text_field.dart';
import 'people_dialogs.dart';
import 'person_avatar.dart';
import 'reaction_picker.dart';
import 'rich_body.dart';

final _commentsProvider = FutureProvider.autoDispose
    .family<List<PostComment>, String>(
      (ref, postId) => ref.watch(feedRepositoryProvider).fetchComments(postId),
    );

/// Comments of one post, with replies (one level), reactions and @mentions.
Future<void> showCommentsDialog(
  BuildContext context, {
  required FeedPost post,
  required MyProfile me,
  bool canModerate = false,
  void Function(String tag)? onHashtag,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => CommentsSection(
      post: post,
      me: me,
      canModerate: canModerate,
      onHashtag: onHashtag,
    ),
  );
}

/// How top-level comments are ordered.
enum CommentOrder { newest, oldest }

/// Comments of a post. [inline] shows them right under the post (like
/// Facebook); otherwise they are shown in a dialog.
class CommentsSection extends ConsumerStatefulWidget {
  const CommentsSection({
    super.key,
    required this.post,
    required this.me,
    this.canModerate = false,
    this.onHashtag,
    this.inline = false,
    this.onChanged,
  });

  final FeedPost post;
  final MyProfile me;
  final bool canModerate;
  final void Function(String tag)? onHashtag;
  final bool inline;

  /// Called after a comment is added, edited or deleted.
  final VoidCallback? onChanged;

  @override
  ConsumerState<CommentsSection> createState() => _CommentsDialogState();
}

class _CommentsDialogState extends ConsumerState<CommentsSection> {
  CommentOrder _order = CommentOrder.newest;
  final MentionController _text = MentionController();
  PostComment? _replyTo;
  PostComment? _editing;
  bool _sending = false;
  String? _error;

  bool get _canModerate => widget.canModerate;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _reload() {
    ref.invalidate(_commentsProvider(widget.post.id));
    widget.onChanged?.call();
  }

  Future<void> _send() async {
    if (_text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final repo = ref.read(feedRepositoryProvider);
    try {
      if (_editing != null) {
        await repo.updateComment(_editing!.id, _text.storedText);
      } else {
        await repo.addComment(
          postId: widget.post.id,
          authorId: widget.me.id,
          body: _text.storedText,
          // Replies to a reply attach to the top comment (one level).
          parentId: _replyTo == null
              ? null
              : (_replyTo!.parentId ?? _replyTo!.id),
        );
      }
      _text.clear();
      setState(() {
        _replyTo = null;
        _editing = null;
      });
      _reload();
    } catch (_) {
      if (mounted) {
        setState(() => _error = AppLocalizations.of(context).errorUnknown);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startReply(PostComment c) => setState(() {
    _editing = null;
    _replyTo = c;
  });

  void _startEdit(PostComment c) {
    _text.load(c.body); // keeps the existing @mentions
    setState(() {
      _replyTo = null;
      _editing = c;
    });
  }

  Future<void> _react(BuildContext anchor, PostComment c) async {
    final choice = await showReactionPicker(anchor, current: c.myReaction);
    if (choice == null) return;
    await ref
        .read(feedRepositoryProvider)
        .setReaction(
          profileId: widget.me.id,
          commentId: c.id,
          emoji: choice is ReactionPicked ? choice.emoji : null,
        );
    _reload();
  }

  Future<void> _delete(PostComment c) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.deleteCommentConfirm),
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
    await ref.read(feedRepositoryProvider).deleteComment(c.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final comments = ref.watch(_commentsProvider(widget.post.id));
    final locked = widget.post.commentsLocked && !_canModerate;

    final theme = Theme.of(context);
    final header = Row(
      children: [
        Expanded(
          child: Text(
            l10n.commentsTitle,
            style: widget.inline
                ? theme.textTheme.titleSmall
                : theme.textTheme.titleLarge,
          ),
        ),
        PopupMenuButton<CommentOrder>(
          key: const Key('commentOrder'),
          initialValue: _order,
          onSelected: (o) => setState(() => _order = o),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: CommentOrder.newest,
              child: Text(l10n.commentsNewest),
            ),
            PopupMenuItem(
              value: CommentOrder.oldest,
              child: Text(l10n.commentsOldest),
            ),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sort_rounded, size: 18),
                const SizedBox(width: 4),
                Text(
                  _order == CommentOrder.newest
                      ? l10n.commentsNewest
                      : l10n.commentsOldest,
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
          ),
        ),
        if (!widget.inline)
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
      ],
    );

    List<Widget> tiles(List<PostComment> value) {
      final top = value.where((c) => c.parentId == null).toList()
        ..sort(
          (a, b) => _order == CommentOrder.newest
              ? b.createdAt.compareTo(a.createdAt)
              : a.createdAt.compareTo(b.createdAt),
        );
      return [
        for (final c in top) ...[
          _CommentTile(comment: c, state: this),
          for (final r in value.where((r) => r.parentId == c.id))
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 48),
              child: _CommentTile(comment: r, state: this),
            ),
        ],
      ];
    }

    final Widget list = switch (comments) {
      AsyncData(:final value) when value.isEmpty => Padding(
        padding: const EdgeInsets.all(16),
        child: Center(child: Text(l10n.noCommentsYet)),
      ),
      AsyncData(:final value) =>
        widget.inline
            ? Column(children: tiles(value))
            : ListView(shrinkWrap: true, children: tiles(value)),
      AsyncError() => Center(
        child: TextButton.icon(
          onPressed: _reload,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.retry),
        ),
      ),
      _ => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
    };

    final composer = <Widget>[
      if (locked)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              const Icon(Icons.lock_outline),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.commentsLocked)),
            ],
          ),
        )
      else ...[
        if (_replyTo != null || _editing != null)
          Row(
            children: [
              Expanded(
                child: Text(
                  _editing != null
                      ? l10n.edit
                      : l10n.writeReply(_replyTo!.author.fullName),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              IconButton(
                iconSize: 18,
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _replyTo = null;
                  if (_editing != null) _text.clear();
                  _editing = null;
                }),
              ),
            ],
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: MentionTextField(
                fieldKey: const Key('commentTextField'),
                controller: _text,
                hintText: _replyTo == null
                    ? l10n.writeComment
                    : l10n.writeReply(_replyTo!.author.fullName),
                maxLines: 5,
                autofocus: true,
                onSubmit: _send,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const Key('sendCommentButton'),
              tooltip: l10n.send,
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
        if (_error != null)
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
      ],
    ];

    if (widget.inline) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [header, ...composer, const SizedBox(height: 4), list],
        ),
      );
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const Divider(),
              Flexible(child: list),
              const Divider(),
              ...composer,
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, required this.state});

  final PostComment comment;
  final _CommentsDialogState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mine = comment.author.id == state.widget.me.id;
    final canDelete = mine || state._canModerate;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PersonAvatar(comment.author, radius: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comment.author.fullName,
                        style: theme.textTheme.titleSmall,
                      ),
                      RichBody(
                        comment.body,
                        style: theme.textTheme.bodyMedium,
                        onHashtag: state.widget.onHashtag == null
                            ? null
                            : (tag) {
                                Navigator.pop(context);
                                state.widget.onHashtag!(tag);
                              },
                      ),
                    ],
                  ),
                ),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: [
                    Text(
                      timeAgo(context, comment.createdAt) +
                          (comment.editedAt != null ? ' · ${l10n.edited}' : ''),
                      style: theme.textTheme.bodySmall,
                    ),
                    Builder(
                      builder: (anchor) => TextButton(
                        onPressed: () => state._react(anchor, comment),
                        child: Text(comment.myReaction ?? l10n.like),
                      ),
                    ),
                    if (!(state.widget.post.commentsLocked &&
                        !state._canModerate))
                      TextButton(
                        onPressed: () => state._startReply(comment),
                        child: Text(l10n.reply),
                      ),
                    if (mine)
                      TextButton(
                        onPressed: () => state._startEdit(comment),
                        child: Text(l10n.edit),
                      ),
                    if (canDelete)
                      TextButton(
                        onPressed: () => state._delete(comment),
                        child: Text(l10n.delete),
                      ),
                    if (!mine)
                      TextButton(
                        onPressed: () => showReportDialog(
                          context,
                          state.ref,
                          commentId: comment.id,
                        ),
                        child: Text(l10n.reportAction),
                      ),
                    ReactionSummary(
                      reactions: comment.reactions,
                      size: 16,
                      onTap: () =>
                          showReactorsDialog(context, commentId: comment.id),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
