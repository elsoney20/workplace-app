import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/brand_config.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../../core/widgets/language_menu_button.dart';
import '../../../core/widgets/motion.dart';
import '../../admin/presentation/admin_errors.dart';
import '../../admin/presentation/admin_screen.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/my_profile.dart';
import '../../auth/presentation/security_screen.dart';
import '../../chat/application/chat_providers.dart';
import '../../chat/presentation/chat_screen.dart';
import '../../chat/presentation/chats_screen.dart';
import '../../directory/presentation/directory_screen.dart';
import '../../feed/domain/feed_scope.dart';
import '../../feed/presentation/feed_view.dart';
import '../../groups/presentation/groups_screen.dart';
import '../../moderation/presentation/reports_screen.dart';
import '../../notifications/application/notifications_providers.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../search/presentation/search_screen.dart';

/// Home after login (design #4 "G2E Classic"): an icon rail on the side,
/// the company feed in the middle, and a chat panel on wide screens.
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

    // Deactivated (or removed) while signed in: explain, then sign out.
    ref.listen(myProfileProvider, (previous, next) async {
      if (next case AsyncData(value: null)) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.accountNotActiveTitle),
            content: Text(l10n.errorNotActive),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.ok),
              ),
            ],
          ),
        );
        await ref.read(authRepositoryProvider).signOut();
      }
    });

    return Scaffold(
      body: BrandBackdrop(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final wide = box.maxWidth >= HomeScreen.chatPanelMinWidth;
              final p = profile.value;
              return Row(
                children: [
                  _Rail(profile: p, panelOpen: wide),
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
                              onPressed: () =>
                                  ref.invalidate(myProfileProvider),
                              icon: const Icon(Icons.refresh),
                              label: Text(
                                '${l10n.errorNetwork}\n${l10n.retry}',
                              ),
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
        ),
      ),
    );
  }
}

/// The slim icon rail. Items keep the old keys so tests and habits still work.
class _Rail extends ConsumerWidget {
  const _Rail({required this.profile, required this.panelOpen});

  final MyProfile? profile;

  /// When the chat panel is visible the chats button is still shown,
  /// it just opens the full chats page.
  final bool panelOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final p = profile;

    return Container(
      width: 76,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: .72),
        border: BorderDirectional(
          end: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Tooltip(
            message: BrandConfig.localizedAppName(
              Localizations.localeOf(context),
            ),
            child: const BrandLogo(size: 40),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _RailButton(
                    icon: Icons.home_rounded,
                    label: l10n.homeTitle,
                    selected: true,
                    onTap: () {},
                  ),
                  _RailButton(
                    key: const Key('openGroups'),
                    icon: Icons.groups_rounded,
                    label: l10n.groupsTitle,
                    onTap: () => context.push(GroupsScreen.routePath),
                  ),
                  const _ChatsButton(),
                  const _NotificationsButton(),
                  _RailButton(
                    key: const Key('openSearch'),
                    icon: Icons.search_rounded,
                    label: l10n.searchTitle,
                    onTap: () => context.push(SearchScreen.routePath),
                  ),
                  _RailButton(
                    key: const Key('openDirectory'),
                    icon: Icons.contacts_rounded,
                    label: l10n.directoryTitle,
                    onTap: () => context.push(DirectoryScreen.routePath),
                  ),
                  if (p != null && (p.isAdmin || p.role == 'manager'))
                    _RailButton(
                      key: const Key('openReports'),
                      icon: Icons.flag_rounded,
                      label: l10n.reportsTitle,
                      onTap: () => context.push(ReportsScreen.routePath),
                    ),
                  if (p != null && p.isAdmin)
                    _RailButton(
                      key: const Key('openAdminPanel'),
                      icon: Icons.admin_panel_settings_rounded,
                      label: l10n.adminPanel,
                      onTap: () => context.push(AdminScreen.routePath),
                    ),
                ],
              ),
            ),
          ),
          const LanguageMenuButton(),
          _RailButton(
            icon: Icons.shield_outlined,
            label: l10n.securityTitle,
            onTap: () => context.push(SecurityScreen.routePath),
          ),
          _RailButton(
            key: const Key('openMyProfile'),
            icon: Icons.person_rounded,
            label: l10n.myProfile,
            onTap: () => context.push(MyProfileScreen.routePath),
          ),
          _RailButton(
            key: const Key('signOutButton'),
            icon: Icons.logout_rounded,
            label: l10n.signOut,
            onTap: () => ref.read(authRepositoryProvider).signOut(),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Tooltip(
        message: label,
        preferBelow: false,
        child: Pressable(
          child: Material(
            color: selected
                ? scheme.primary.withValues(alpha: .16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                  child: PopOnChange(
                    trigger: badge,
                    child: Badge(
                      isLabelVisible: badge > 0,
                      label: Text(badge > 99 ? '99+' : '$badge'),
                      child: Icon(
                        icon,
                        color: selected
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Chats with an unread badge. Watching it also keeps the "online" status
/// and live chat updates running while the app is open.
class _ChatsButton extends ConsumerWidget {
  const _ChatsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    ref.watch(onlinePeopleProvider);
    final unread = ref.watch(unreadChatsProvider);
    return _RailButton(
      key: const Key('openChats'),
      icon: Icons.chat_bubble_rounded,
      label: l10n.chatsTitle,
      badge: unread,
      onTap: () => context.push(ChatsScreen.routePath),
    );
  }
}

/// Bell with the unread count. Watching the tick keeps the live
/// notifications channel (and Windows toasts) running while the app is open.
class _NotificationsButton extends ConsumerWidget {
  const _NotificationsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    ref.watch(notificationsTickProvider);
    final unread = ref.watch(unreadNotificationsProvider).value ?? 0;
    return _RailButton(
      key: const Key('openNotifications'),
      icon: Icons.notifications_rounded,
      label: l10n.notificationsTitle,
      badge: unread,
      onTap: () async {
        await context.push(NotificationsScreen.routePath);
        ref.invalidate(unreadNotificationsProvider);
      },
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
