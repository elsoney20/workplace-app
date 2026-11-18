import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/widgets/motion.dart';
import '../application/chat_providers.dart';
import 'chat_screen.dart';
import 'chats_screen.dart';

/// What the chat side panel shows: closed, the list of chats, or the list
/// plus one open chat.
class ChatDrawerState {
  const ChatDrawerState({this.open = false, this.chatId});

  final bool open;
  final String? chatId;
}

class ChatDrawerController extends Notifier<ChatDrawerState> {
  @override
  ChatDrawerState build() => const ChatDrawerState();

  /// The "Chats" button on the rail: open the list, or close the panel.
  void toggle() => state = state.open
      ? const ChatDrawerState()
      : const ChatDrawerState(open: true);

  void openChat(String id) => state = ChatDrawerState(open: true, chatId: id);

  /// Close the open chat but keep the list.
  void back() => state = const ChatDrawerState(open: true);

  void close() => state = const ChatDrawerState();
}

final chatDrawerProvider =
    NotifierProvider<ChatDrawerController, ChatDrawerState>(
      ChatDrawerController.new,
    );

/// The chat panel next to the rail (like Facebook's chat sidebar). It
/// slides open with the list of chats, and grows wider when a chat is
/// opened, so chatting never leaves the page you are on.
class ChatDrawer extends ConsumerStatefulWidget {
  const ChatDrawer({super.key, required this.available});

  /// Width next to the rail; the page keeps at least [minPage] of it.
  final double available;

  static const double listWidth = 340;
  static const double chatWidth = 460;
  static const double minPage = 420;

  @override
  ConsumerState<ChatDrawer> createState() => _ChatDrawerState();
}

class _ChatDrawerState extends ConsumerState<ChatDrawer> {
  /// What is drawn; kept while the panel slides shut so it doesn't go
  /// blank mid-animation.
  ChatDrawerState _shown = const ChatDrawerState();

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(chatDrawerProvider);
    if (s.open) _shown = s;
    final shown = _shown;
    final theme = Theme.of(context);

    final room = widget.available - ChatDrawer.minPage;
    final bothFit = room >= ChatDrawer.listWidth + ChatDrawer.chatWidth;
    final chatId = shown.chatId;
    final showChat = chatId != null;
    final showList = !showChat || bothFit;
    final inner =
        (showList ? ChatDrawer.listWidth : 0) +
        (showChat ? ChatDrawer.chatWidth : 0);
    final width = s.open
        ? inner.clamp(0, widget.available.clamp(0, double.infinity)).toDouble()
        : 0.0;

    return AnimatedContainer(
      key: const Key('chatDrawer'),
      duration: const Duration(milliseconds: 340),
      curve: kSmooth,
      width: width,
      onEnd: () {
        if (!ref.read(chatDrawerProvider).open && mounted) {
          setState(() => _shown = const ChatDrawerState());
        }
      },
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow.withValues(alpha: .94),
        border: width == 0
            ? null
            : BorderDirectional(
                end: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
      ),
      child: !shown.open
          ? null
          : ClipRect(
              child: OverflowBox(
                alignment: AlignmentDirectional.centerStart,
                minWidth: inner.toDouble(),
                maxWidth: inner.toDouble(),
                child: Row(
                  children: [
                    if (showList)
                      SizedBox(
                        width: ChatDrawer.listWidth,
                        child: _Inbox(selected: chatId),
                      ),
                    if (showList && showChat)
                      VerticalDivider(
                        width: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                    if (showChat)
                      Expanded(
                        child: ChatScreen(
                          key: ValueKey('drawer-$chatId'),
                          conversationId: chatId,
                          onClose: () =>
                              ref.read(chatDrawerProvider.notifier).back(),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Inbox extends ConsumerWidget {
  const _Inbox({required this.selected});

  final String? selected;

  Future<void> _newChat(BuildContext context, WidgetRef ref) async {
    final id = await showDialog<String>(
      context: context,
      builder: (_) => const NewChatDialog(),
    );
    if (id != null) {
      ref.invalidate(conversationsProvider);
      ref.read(chatDrawerProvider.notifier).openChat(id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final chats = ref.watch(conversationsProvider);
    final drawer = ref.read(chatDrawerProvider.notifier);

    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.chatsTitle,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('newChatButton'),
                  tooltip: l10n.newChat,
                  onPressed: () => _newChat(context, ref),
                  icon: const Icon(Icons.add_comment_rounded),
                ),
                IconButton(
                  key: const Key('closeChatDrawer'),
                  tooltip: l10n.close,
                  onPressed: drawer.close,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (chats) {
              AsyncData(:final value) when value.isEmpty => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l10n.chatsEmpty, textAlign: TextAlign.center),
                ),
              ),
              AsyncData(:final value) => ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: value.length,
                itemBuilder: (context, i) => ConversationTile(
                  conversation: value[i],
                  selected: value[i].id == selected,
                  onOpen: () => drawer.openChat(value[i].id),
                ),
              ),
              AsyncError() => Center(
                child: TextButton.icon(
                  onPressed: () => ref.invalidate(conversationsProvider),
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.retry),
                ),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}
