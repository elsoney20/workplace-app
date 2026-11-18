import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/my_profile.dart';
import '../../feed/data/feed_repository.dart'
    show PendingUpload, maxUploadBytes;
import '../../feed/domain/person.dart';
import '../../feed/domain/post_attachment.dart';
import '../../feed/presentation/animated_emoji.dart';
import '../../feed/presentation/attachments_view.dart';
import '../../feed/presentation/emoji_grid.dart';
import '../../feed/presentation/feed_format.dart';
import '../../feed/presentation/person_avatar.dart';
import '../../feed/presentation/reaction_picker.dart';
import '../../feed/presentation/rich_body.dart';
import '../../feed/presentation/share_post.dart';
import '../application/chat_providers.dart';
import '../data/chat_repository.dart';
import '../domain/chat_message.dart';
import '../domain/conversation.dart';
import 'chat_info_dialog.dart';

/// One conversation (1:1 or group).
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key, required this.conversationId, this.onClose});

  final String conversationId;

  /// Set when the chat is shown inside the home page's side panel instead of
  /// as its own page: shows a close button instead of "back".
  final VoidCallback? onClose;

  static const String routePath = '/chats/:id';
  static const String routeName = 'chat';
  static String pathFor(String id) => '/chats/$id';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final me = ref.watch(myProfileProvider).value;
    final conversation = ref
        .watch(conversationsProvider)
        .value
        ?.where((c) => c.id == conversationId)
        .firstOrNull;
    if (me == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (conversation == null) {
      final loading = ref.watch(conversationsProvider).isLoading;
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: loading
              ? const CircularProgressIndicator()
              : Text(l10n.errorUnknown),
        ),
      );
    }
    return _ChatView(conversation: conversation, me: me, onClose: onClose);
  }
}

class _ChatView extends ConsumerStatefulWidget {
  const _ChatView({required this.conversation, required this.me, this.onClose});

  final Conversation conversation;
  final MyProfile me;
  final VoidCallback? onClose;

  @override
  ConsumerState<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<_ChatView> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final List<PendingUpload> _uploads = [];
  ChatMessage? _replyTo;
  ChatMessage? _editing;
  bool _sending = false;

  String get _id => widget.conversation.id;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      // The list is reversed: "after" = older messages at the top.
      if (_scroll.position.extentAfter < 400) {
        ref.read(chatControllerProvider(_id).notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final l10n = AppLocalizations.of(context);
    final files = await FilePicker.pickFiles();
    for (final f in files) {
      final size = await f.length();
      if (size != null && size > maxUploadBytes) {
        if (mounted) _snack(l10n.fileTooBig(f.name));
        continue;
      }
      final upload = PendingUpload(name: f.name, bytes: await f.readAsBytes());
      if (upload.tooBig) {
        if (mounted) _snack(l10n.fileTooBig(f.name));
        continue;
      }
      if (mounted) setState(() => _uploads.add(upload));
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _send() async {
    final body = _text.text.trim();
    if (_sending || (body.isEmpty && _uploads.isEmpty)) return;
    final repo = ref.read(chatRepositoryProvider);
    final controller = ref.read(chatControllerProvider(_id).notifier);
    final l10n = AppLocalizations.of(context);

    if (_editing != null) {
      final editing = _editing!;
      setState(() => _editing = null);
      _text.clear();
      try {
        await repo.edit(editing.id, body);
        await controller.refresh();
      } catch (_) {
        if (mounted) _snack(l10n.errorUnknown);
      }
      return;
    }

    final uploads = List<PendingUpload>.from(_uploads);
    final replyTo = _replyTo;
    final tempId = 'pending-${DateTime.now().microsecondsSinceEpoch}';
    controller.addPending(
      ChatMessage(
        id: tempId,
        conversationId: _id,
        sender: _mePerson,
        body: body,
        createdAt: DateTime.now(),
        pending: true,
        replyTo: replyTo == null
            ? null
            : QuotedMessage(
                id: replyTo.id,
                body: replyTo.body,
                senderName: replyTo.sender.fullName,
                deleted: false,
              ),
      ),
    );
    setState(() {
      _sending = uploads.isNotEmpty;
      _uploads.clear();
      _replyTo = null;
    });
    _text.clear();
    _focus.requestFocus();
    try {
      await repo.send(
        conversationId: _id,
        senderId: widget.me.id,
        body: body,
        replyToId: replyTo?.id,
        uploads: uploads,
      );
      await controller.refresh();
    } catch (_) {
      if (mounted) _snack(l10n.errorUnknown);
    } finally {
      controller.removePending(tempId);
      if (mounted) setState(() => _sending = false);
    }
  }

  Person get _mePerson => Person(
    id: widget.me.id,
    fullName: widget.me.fullName,
    jobTitle: widget.me.jobTitle,
  );

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _send();
      return KeyEventResult.handled;
    }
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape &&
        (_replyTo != null || _editing != null)) {
      setState(() {
        if (_editing != null) _text.clear();
        _replyTo = null;
        _editing = null;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _onMessageAction(
    BuildContext anchor,
    ChatMessage m,
    _MessageAction action,
  ) async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(chatRepositoryProvider);
    final controller = ref.read(chatControllerProvider(_id).notifier);
    try {
      switch (action) {
        case _MessageAction.react:
          final choice = await showReactionPicker(anchor);
          if (choice is ReactionPicked) await _toggleReaction(m, choice.emoji);
        case _MessageAction.reply:
          setState(() {
            _editing = null;
            _replyTo = m;
          });
          _focus.requestFocus();
        case _MessageAction.copy:
          await Clipboard.setData(ClipboardData(text: m.body));
          if (mounted) _snack(l10n.copied);
        case _MessageAction.edit:
          setState(() {
            _replyTo = null;
            _editing = m;
            _text.text = m.body;
          });
          _focus.requestFocus();
        case _MessageAction.delete:
          final ok = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              content: Text(l10n.deleteMessageConfirm),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(l10n.deleteForEveryone),
                ),
              ],
            ),
          );
          if (ok == true) {
            await repo.deleteForEveryone(m.id);
            await controller.refresh();
          }
        case _MessageAction.info:
          if (mounted) await showReceiptsDialog(context, m);
      }
    } catch (_) {
      if (mounted) _snack(l10n.errorUnknown);
    }
  }

  Future<void> _toggleReaction(ChatMessage m, String emoji) async {
    final repo = ref.read(chatRepositoryProvider);
    final mine = m.reactions[emoji]?.contains(widget.me.id) ?? false;
    if (mine) {
      await repo.removeReaction(m.id, widget.me.id, emoji);
    } else {
      await repo.addReaction(m.id, widget.me.id, emoji);
    }
    await ref.read(chatControllerProvider(_id).notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = widget.conversation;
    final chat = ref.watch(chatControllerProvider(_id));
    final typing = ref.watch(typingProvider(_id));
    final online = ref.watch(onlinePeopleProvider);

    final String subtitle;
    if (typing.isNotEmpty) {
      subtitle = typing.length == 1
          ? l10n.typingOne(typing.values.first.split(' ').first)
          : l10n.typingMany;
    } else if (c.isGroup) {
      subtitle = l10n.memberCount(c.memberCount);
    } else {
      subtitle = online.contains(c.otherPerson?.id)
          ? l10n.online
          : l10n.offline;
    }

    final onClose = widget.onClose;
    return Scaffold(
      backgroundColor: onClose == null ? null : Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: onClose == null,
        backgroundColor: onClose == null ? null : Colors.transparent,
        leading: onClose == null
            ? null
            : IconButton(
                key: const Key('closeChatPanel'),
                tooltip: AppLocalizations.of(context).closeChat,
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
        titleSpacing: onClose == null ? 0 : 4,
        title: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: c.isGroup
              ? CircleAvatar(
                  child: Icon(
                    Icons.group,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                )
              : PersonAvatar(c.avatarPerson),
          title: Text(
            c.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            subtitle,
            key: const Key('chatSubtitle'),
            style: typing.isNotEmpty
                ? TextStyle(color: theme.colorScheme.primary)
                : null,
          ),
        ),
        actions: [
          IconButton(
            key: const Key('chatInfoButton'),
            tooltip: l10n.chatInfo,
            icon: const Icon(Icons.info_outline),
            onPressed: () async {
              final left = await showChatInfoDialog(
                context,
                conversation: c,
                me: widget.me,
              );
              if (left && context.mounted) context.pop();
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            children: [
              Expanded(
                child: switch (chat) {
                  AsyncData(:final value) =>
                    value.messages.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.lock_outline, size: 18),
                                  const SizedBox(width: 8),
                                  Flexible(child: Text(l10n.chatPrivacyNote)),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            key: const Key('messageList'),
                            controller: _scroll,
                            reverse: true,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            itemCount:
                                value.messages.length +
                                (value.loadingMore ? 1 : 0),
                            itemBuilder: (context, i) {
                              if (i >= value.messages.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              final m = value.messages[i];
                              final older = i + 1 < value.messages.length
                                  ? value.messages[i + 1]
                                  : null;
                              final newDay =
                                  older == null ||
                                  !_sameDay(older.createdAt, m.createdAt);
                              final grouped =
                                  older != null &&
                                  !newDay &&
                                  older.sender.id == m.sender.id &&
                                  m.createdAt
                                          .difference(older.createdAt)
                                          .inMinutes <
                                      5;
                              return Column(
                                children: [
                                  if (newDay) _DaySeparator(day: m.createdAt),
                                  _MessageBubble(
                                    key: ValueKey(m.id),
                                    message: m,
                                    me: widget.me,
                                    showSender: c.isGroup && !grouped,
                                    onAction: _onMessageAction,
                                    onReactionTap: (emoji) =>
                                        _toggleReaction(m, emoji),
                                  ),
                                ],
                              );
                            },
                          ),
                  AsyncError() => Center(
                    child: TextButton.icon(
                      onPressed: () =>
                          ref.invalidate(chatControllerProvider(_id)),
                      icon: const Icon(Icons.refresh),
                      label: Text('${l10n.errorNetwork}\n${l10n.retry}'),
                    ),
                  ),
                  _ => const Center(child: CircularProgressIndicator()),
                },
              ),
              _composer(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composer(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final banner = _editing != null
        ? l10n.editingMessage
        : _replyTo != null
        ? l10n.replyingTo(_replyTo!.sender.fullName)
        : null;
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (banner != null)
                Row(
                  children: [
                    Icon(_editing != null ? Icons.edit : Icons.reply, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(banner, style: theme.textTheme.bodySmall),
                    ),
                    IconButton(
                      iconSize: 16,
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        if (_editing != null) _text.clear();
                        _replyTo = null;
                        _editing = null;
                      }),
                    ),
                  ],
                ),
              if (_uploads.isNotEmpty)
                Wrap(
                  spacing: 6,
                  children: [
                    for (final (i, u) in _uploads.indexed)
                      InputChip(
                        avatar: Icon(
                          u.kind == AttachmentKind.image
                              ? Icons.image
                              : Icons.attach_file,
                          size: 18,
                        ),
                        label: Text(
                          '${u.name} (${formatBytes(u.bytes.length)})',
                        ),
                        onDeleted: () => setState(() => _uploads.removeAt(i)),
                      ),
                  ],
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: l10n.addFile,
                    icon: const Icon(Icons.attach_file),
                    onPressed: _editing != null ? null : _pickFiles,
                  ),
                  IconButton(
                    tooltip: l10n.addEmoji,
                    icon: const Icon(Icons.emoji_emotions_outlined),
                    onPressed: () async {
                      final emoji = await showEmojiGrid(context);
                      if (emoji == null) return;
                      final sel = _text.selection;
                      final start = sel.isValid ? sel.start : _text.text.length;
                      final end = sel.isValid ? sel.end : _text.text.length;
                      _text.value = TextEditingValue(
                        text: _text.text.replaceRange(start, end, emoji),
                        selection: TextSelection.collapsed(
                          offset: start + emoji.length,
                        ),
                      );
                      _focus.requestFocus();
                    },
                  ),
                  Expanded(
                    child: Focus(
                      onKeyEvent: _onKey,
                      child: TextField(
                        key: const Key('messageField'),
                        controller: _text,
                        focusNode: _focus,
                        autofocus: true,
                        minLines: 1,
                        maxLines: 6,
                        keyboardType: TextInputType.multiline,
                        decoration: InputDecoration(
                          hintText: l10n.typeMessage,
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        onChanged: (_) =>
                            ref.read(typingProvider(_id).notifier).iAmTyping(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    key: const Key('sendMessageButton'),
                    tooltip: l10n.sendMessage,
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_editing != null ? Icons.check : Icons.send),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class _DaySeparator extends StatelessWidget {
  const _DaySeparator({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final label = _sameDay(day, now)
        ? l10n.today
        : _sameDay(day, now.subtract(const Duration(days: 1)))
        ? l10n.yesterday
        : DateFormat.yMMMMd(
            Localizations.localeOf(context).toLanguageTag(),
          ).format(day);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Chip(label: Text(label), visualDensity: VisualDensity.compact),
      ),
    );
  }
}

enum _MessageAction { react, reply, copy, edit, delete, info }

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.me,
    required this.showSender,
    required this.onAction,
    required this.onReactionTap,
  });

  final ChatMessage message;
  final MyProfile me;
  final bool showSender;
  final Future<void> Function(
    BuildContext anchor,
    ChatMessage m,
    _MessageAction a,
  )
  onAction;
  final void Function(String emoji) onReactionTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = message;
    final mine = m.sender.id == me.id;
    final bubbleColor = mine
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final textColor = mine ? scheme.onPrimaryContainer : scheme.onSurface;
    final time = DateFormat.jm(
      Localizations.localeOf(context).toLanguageTag(),
    ).format(m.createdAt);

    final actions = <PopupMenuEntry<_MessageAction>>[
      if (!m.isDeleted && !m.pending) ...[
        PopupMenuItem(value: _MessageAction.react, child: Text(l10n.react)),
        PopupMenuItem(value: _MessageAction.reply, child: Text(l10n.reply)),
        if (m.body.isNotEmpty)
          PopupMenuItem(value: _MessageAction.copy, child: Text(l10n.copy)),
        if (mine && m.body.isNotEmpty)
          PopupMenuItem(value: _MessageAction.edit, child: Text(l10n.edit)),
        if (mine)
          PopupMenuItem(
            value: _MessageAction.info,
            child: Text(l10n.messageInfo),
          ),
        if (mine)
          PopupMenuItem(
            value: _MessageAction.delete,
            child: Text(l10n.deleteForEveryone),
          ),
      ],
    ];

    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSender && !mine)
            Text(
              m.sender.fullName,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.primary,
              ),
            ),
          if (m.replyTo != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
                border: BorderDirectional(
                  start: BorderSide(color: scheme.primary, width: 3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.replyTo!.senderName,
                    style: theme.textTheme.labelMedium,
                  ),
                  Text(
                    m.replyTo!.deleted ? l10n.messageDeleted : m.replyTo!.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          if (m.isDeleted)
            Text(
              l10n.messageDeleted,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: scheme.outline,
              ),
            )
          else ...[
            if (m.attachments.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 320,
                  child: AttachmentsView(
                    attachments: m.attachments,
                    bucket: ChatRepository.bucket,
                  ),
                ),
              ),
            if (SharedPostLink.split(m.body) case (
              final text,
              final postId,
            )) ...[
              if (text.isNotEmpty)
                RichBody(
                  text,
                  style: theme.textTheme.bodyLarge?.copyWith(color: textColor),
                ),
              if (postId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SharedPostPreview(postId: postId),
                ),
            ],
          ],
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (m.editedAt != null && !m.isDeleted)
                Text('${l10n.edited} · ', style: theme.textTheme.labelSmall),
              Text(time, style: theme.textTheme.labelSmall),
              if (mine && !m.isDeleted) ...[
                const SizedBox(width: 4),
                _ReceiptTicks(status: m.status),
              ],
            ],
          ),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(top: showSender ? 8 : 2),
      child: Align(
        alignment: mine
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: Column(
          crossAxisAlignment: mine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Builder(
              builder: (anchor) => GestureDetector(
                onLongPress: actions.isEmpty
                    ? null
                    : () => _openMenu(anchor, actions),
                onSecondaryTap: actions.isEmpty
                    ? null
                    : () => _openMenu(anchor, actions),
                onDoubleTap: m.isDeleted || m.pending
                    ? null
                    : () => onReactionTap('❤️'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: bubble),
                    if (actions.isNotEmpty)
                      PopupMenuButton<_MessageAction>(
                        key: Key('messageMenu-${m.id}'),
                        iconSize: 18,
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.more_vert,
                          size: 18,
                          color: scheme.outline,
                        ),
                        onSelected: (a) => onAction(anchor, m, a),
                        itemBuilder: (_) => actions,
                      ),
                  ],
                ),
              ),
            ),
            if (m.reactions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Wrap(
                  spacing: 4,
                  children: [
                    for (final e in m.reactions.entries)
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => onReactionTap(e.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: e.value.contains(me.id)
                                ? scheme.primaryContainer
                                : scheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedEmoji(e.key, size: 18, onHover: true),
                              if (e.value.length > 1)
                                Text(
                                  ' ${e.value.length}',
                                  style: theme.textTheme.labelSmall,
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMenu(
    BuildContext anchor,
    List<PopupMenuEntry<_MessageAction>> actions,
  ) async {
    final box = anchor.findRenderObject() as RenderBox?;
    if (box == null) return;
    final overlay = Overlay.of(anchor).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      box.localToGlobal(Offset.zero, ancestor: overlay) & box.size,
      Offset.zero & overlay.size,
    );
    final chosen = await showMenu<_MessageAction>(
      context: anchor,
      position: position,
      items: actions,
    );
    if (chosen != null && anchor.mounted) {
      await onAction(anchor, message, chosen);
    }
  }
}

class _ReceiptTicks extends StatelessWidget {
  const _ReceiptTicks({required this.status});

  final ReceiptStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final outline = Theme.of(context).colorScheme.outline;
    return switch (status) {
      ReceiptStatus.sending => Icon(Icons.schedule, size: 14, color: outline),
      ReceiptStatus.sent => Icon(
        Icons.check,
        size: 16,
        color: outline,
        semanticLabel: l10n.delivered,
      ),
      ReceiptStatus.delivered => Icon(
        Icons.done_all,
        size: 16,
        color: outline,
        semanticLabel: l10n.delivered,
      ),
      ReceiptStatus.seen => Icon(
        Icons.done_all,
        key: const Key('seenTicks'),
        size: 16,
        color: Colors.lightBlue,
        semanticLabel: l10n.seen,
      ),
    };
  }
}

/// ✓✓ details: who received and who saw a message, and when.
Future<void> showReceiptsDialog(BuildContext context, ChatMessage message) {
  return showDialog<void>(
    context: context,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final l10n = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l10n.messageInfo),
          content: SizedBox(
            width: 420,
            height: 360,
            child: FutureBuilder(
              future: ref
                  .read(chatRepositoryProvider)
                  .fetchReceipts(message.id),
              builder: (context, snapshot) {
                final items = snapshot.data;
                if (snapshot.hasError) {
                  return Center(child: Text(l10n.errorNetwork));
                }
                if (items == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                return ListView(
                  children: [
                    for (final r in items)
                      ListTile(
                        leading: PersonAvatar(r.person),
                        title: Text(r.person.fullName),
                        subtitle: Text(
                          '${l10n.seen}: ${r.seenAt == null ? l10n.notYet : fullTime(context, r.seenAt!)}\n'
                          '${l10n.delivered}: ${r.deliveredAt == null ? l10n.notYet : fullTime(context, r.deliveredAt!)}',
                        ),
                        isThreeLine: true,
                        trailing: Icon(
                          r.seenAt != null
                              ? Icons.done_all
                              : (r.deliveredAt != null
                                    ? Icons.done_all
                                    : Icons.check),
                          color: r.seenAt != null ? Colors.lightBlue : null,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.ok),
            ),
          ],
        );
      },
    ),
  );
}
