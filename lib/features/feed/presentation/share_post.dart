import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/storage/signed_urls.dart';
import '../../auth/application/auth_providers.dart';
import '../../chat/application/chat_providers.dart';
import '../../chat/data/chat_repository.dart';
import '../../chat/presentation/chat_drawer.dart';
import '../data/feed_repository.dart';
import '../domain/feed_post.dart';
import '../domain/post_attachment.dart';
import '../domain/rich_text.dart';
import 'person_avatar.dart';
import 'post_screen.dart';

/// A post shared into a chat travels inside the message text as
/// `[[post:<id>]]`; the chat shows it as a small card.
class SharedPostLink {
  static final RegExp _re = RegExp(r'\[\[post:([0-9a-fA-F-]{36})\]\]');

  static String make(String postId, String note) {
    final n = note.trim();
    return n.isEmpty ? '[[post:$postId]]' : '$n\n[[post:$postId]]';
  }

  /// The message text without the link, and the shared post id (if any).
  static (String, String?) split(String body) {
    final m = _re.firstMatch(body);
    if (m == null) return (body, null);
    return (body.replaceAll(_re, '').trim(), m.group(1));
  }

  /// One-line preview for the chats list.
  static String preview(String body, AppLocalizations l10n) {
    final (text, id) = split(body);
    if (id == null) return body;
    return text.isEmpty ? '📰 ${l10n.sharedPost}' : '📰 $text';
  }
}

Future<void> showSharePostDialog(BuildContext context, FeedPost post) =>
    showDialog<void>(
      context: context,
      builder: (_) => _SharePostDialog(post: post),
    );

class _SharePostDialog extends ConsumerStatefulWidget {
  const _SharePostDialog({required this.post});

  final FeedPost post;

  @override
  ConsumerState<_SharePostDialog> createState() => _SharePostDialogState();
}

class _SharePostDialogState extends ConsumerState<_SharePostDialog> {
  final _note = TextEditingController();
  final Set<String> _sent = {};
  final Set<String> _sending = {};

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: plainText(widget.post.body)));
    if (mounted) Navigator.pop(context);
    messenger.showSnackBar(SnackBar(content: Text(l10n.postCopied)));
  }

  Future<void> _send(String conversationId) async {
    final me = ref.read(myProfileProvider).value;
    if (me == null) return;
    setState(() => _sending.add(conversationId));
    try {
      await ref
          .read(chatRepositoryProvider)
          .send(
            conversationId: conversationId,
            senderId: me.id,
            body: SharedPostLink.make(widget.post.id, _note.text),
          );
      ref.invalidate(conversationsProvider);
      if (mounted) setState(() => _sent.add(conversationId));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).errorUnknown)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending.remove(conversationId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final chats = ref.watch(conversationsProvider).value ?? const [];

    return AlertDialog(
      title: Text(l10n.sharePostTitle),
      content: SizedBox(
        width: 440,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              key: const Key('copyPostText'),
              onPressed: _copy,
              icon: const Icon(Icons.copy_rounded),
              label: Text(l10n.copyPostText),
            ),
            const SizedBox(height: 16),
            Text(l10n.sendToChat, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            TextField(
              key: const Key('shareNote'),
              controller: _note,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: l10n.shareNoteHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: chats.isEmpty
                  ? Center(child: Text(l10n.chatsEmpty))
                  : ListView.builder(
                      itemCount: chats.length,
                      itemBuilder: (context, i) {
                        final c = chats[i];
                        final sent = _sent.contains(c.id);
                        final sending = _sending.contains(c.id);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: c.isGroup
                              ? const CircleAvatar(child: Icon(Icons.group))
                              : PersonAvatar(c.avatarPerson, radius: 20),
                          title: Text(
                            c.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: sent
                              ? TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    ref
                                        .read(chatDrawerProvider.notifier)
                                        .openChat(c.id);
                                  },
                                  child: Text('✓ ${l10n.openChat}'),
                                )
                              : FilledButton.tonal(
                                  key: Key('shareTo-${c.id}'),
                                  onPressed: sending ? null : () => _send(c.id),
                                  child: sending
                                      ? const SizedBox.square(
                                          dimension: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(l10n.send),
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}

/// The card a shared post shows inside a chat message.
class SharedPostPreview extends ConsumerWidget {
  const SharedPostPreview({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final post = ref.watch(singlePostProvider(postId));

    final Widget inside = switch (post) {
      AsyncData(value: final p?) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (p.attachments
                  .where((a) => a.kind == AttachmentKind.image)
                  .firstOrNull
              case final img?)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _Thumb(path: img.storagePath),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    PersonAvatar(p.author, radius: 11),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        p.author.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
                if (p.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    plainText(p.body),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      AsyncData() || AsyncError() => Padding(
        padding: const EdgeInsets.all(12),
        child: Text(l10n.postNotFound, style: theme.textTheme.bodySmall),
      ),
      _ => const SizedBox(
        height: 64,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    };

    return SizedBox(
      width: 300,
      child: Material(
        color: theme.colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        child: InkWell(
          key: Key('sharedPost-$postId'),
          onTap: () => context.push(PostScreen.pathFor(postId)),
          child: inside,
        ),
      ),
    );
  }
}

class _Thumb extends ConsumerWidget {
  const _Thumb({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref.watch(
      signedUrlProvider((bucket: FeedRepository.bucket, path: path)),
    );
    return switch (url) {
      // Paused: a GIF stays still here (no endless redraws).
      AsyncData(value: final link?) => TickerMode(
        enabled: false,
        child: Image.network(link, fit: BoxFit.cover),
      ),
      _ => ColoredBox(color: Theme.of(context).colorScheme.surfaceContainer),
    };
  }
}
