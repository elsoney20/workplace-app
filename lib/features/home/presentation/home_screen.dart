import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/widgets/motion.dart';
import '../../admin/presentation/admin_errors.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/my_profile.dart';
import '../../chat/application/chat_providers.dart';
import '../../chat/presentation/chat_screen.dart';
import '../../chat/presentation/chats_screen.dart';
import '../../feed/domain/feed_scope.dart';
import '../../feed/presentation/feed_view.dart';
import '../../search/presentation/search_screen.dart';

/// Home after login (design #4 "G2E Classic"): the company feed in the
/// middle and a chat panel on wide screens. The rail lives in AppShell.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  static const String routePath = '/';
  static const String routeName = 'home';

  /// The chat panel only appears when the window is at least this wide.
  static const double chatPanelMinWidth = 1200;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Conversation open in the side panel, if any.
  String? _openChat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(myProfileProvider);

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= HomeScreen.chatPanelMinWidth;
          final p = profile.value;
          return Row(
            children: [
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: switch (profile) {
                      AsyncData(value: final p?) => FeedView(
                        me: p,
                        scope: FeedScope.company(isAdmin: p.isAdmin),
                        header: _HomeHeader(profile: p),
                      ),
                      AsyncError() => Center(
                        child: TextButton.icon(
                          onPressed: () => ref.invalidate(myProfileProvider),
                          icon: const Icon(Icons.refresh),
                          label: Text('${l10n.errorNetwork}\n${l10n.retry}'),
                        ),
                      ),
                      _ => const Center(child: CircularProgressIndicator()),
                    },
                  ),
                ),
              ),
              if (wide && p != null)
                _ChatPanel(
                  openChat: _openChat,
                  onOpen: (id) => setState(() => _openChat = id),
                  onClose: () => setState(() => _openChat = null),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Greeting + search above the feed.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.profile});

  final MyProfile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final details = [roleLabel(l10n, profile.role), ?profile.jobTitle];

    return FadeSlideIn(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.homeHello(profile.fullName),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              details.join(' · '),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Material(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => context.push(SearchScreen.routePath),
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        l10n.searchShort,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Right-hand chat panel (wide windows only): the inbox, or one open chat.
class _ChatPanel extends ConsumerWidget {
  const _ChatPanel({
    required this.openChat,
    required this.onOpen,
    required this.onClose,
  });

  final String? openChat;
  final ValueChanged<String> onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final chats = ref.watch(conversationsProvider);

    final Widget body;
    if (openChat case final id?) {
      body = ChatScreen(
        key: ValueKey('panel-$id'),
        conversationId: id,
        onClose: onClose,
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 18, 8, 8),
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
                TextButton(
                  onPressed: () => context.push(ChatsScreen.routePath),
                  child: Text(l10n.seeAll),
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (chats) {
              AsyncData(:final value) when value.isEmpty => Center(
                child: Text(l10n.pickAChat, textAlign: TextAlign.center),
              ),
              AsyncData(:final value) => ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: value.length,
                itemBuilder: (context, i) => FadeSlideIn(
                  index: i,
                  child: ConversationTile(
                    conversation: value[i],
                    onOpen: () => onOpen(value[i].id),
                  ),
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
      );
    }

    return Material(
      color: theme.colorScheme.surfaceContainerLow.withValues(alpha: .72),
      shape: BorderDirectional(
        start: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: SizedBox(
        width: 380,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: kSmooth,
          child: body,
        ),
      ),
    );
  }
}
