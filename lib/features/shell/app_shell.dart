import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/config/brand_config.dart';
import '../../core/l10n/generated/app_localizations.dart';
import '../../core/widgets/brand_logo.dart';
import '../../core/widgets/language_menu_button.dart';
import '../../core/widgets/liquid_rail.dart';
import '../../core/widgets/motion.dart';
import '../admin/presentation/admin_screen.dart';
import '../auth/application/auth_providers.dart';
import '../auth/data/auth_repository.dart';
import '../auth/presentation/security_screen.dart';
import '../chat/application/chat_providers.dart';
import '../chat/presentation/chat_drawer.dart';
import '../chat/presentation/chats_screen.dart';
import '../directory/presentation/directory_screen.dart';
import '../groups/presentation/groups_screen.dart';
import '../home/presentation/home_screen.dart';
import '../moderation/presentation/reports_screen.dart';
import '../notifications/application/notifications_providers.dart';
import '../notifications/presentation/notifications_screen.dart';
import '../search/presentation/search_screen.dart';

/// Everything after login lives inside this frame: the liquid icon rail on
/// the side, the animated brand background, and the current page.
class AppShell extends ConsumerWidget {
  const AppShell({
    super.key,
    required this.location,
    required this.child,
    this.shell,
  });

  /// Current route path, used to light up the right rail item.
  final String location;
  final Widget child;

  /// Switches between the rail pages, which all stay alive.
  final StatefulNavigationShell? shell;

  /// Root path of each rail page, in the router's branch order.
  static const List<String> branchRoots = [
    HomeScreen.routePath,
    GroupsScreen.routePath,
    ChatsScreen.routePath,
    NotificationsScreen.routePath,
    SearchScreen.routePath,
    DirectoryScreen.routePath,
    ReportsScreen.routePath,
    AdminScreen.routePath,
    SecurityScreen.routePath,
    MyProfileScreen.routePath,
  ];

  // Liquid colours per item (Games2Egypt palette + PlayStation blue).
  static const _home = Color(0xFFA9C25A);
  static const _groups = Color(0xFFF4B63D);
  static const _chats = Color(0xFF3D7BFF);
  static const _notifications = Color(0xFFFF4D8D);
  static const _search = Color(0xFF9B6BFF);
  static const _directory = Color(0xFF2EC4B6);
  static const _reports = Color(0xFFFF8A3D);
  static const _admin = Color(0xFF7BE8A8);
  static const _security = Color(0xFF5AC8FA);
  static const _profile = Color(0xFFFF6FB5);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final p = ref.watch(myProfileProvider).value;

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

    // Watching these keeps the live chat / notifications channels running.
    ref.watch(onlinePeopleProvider);
    ref.watch(notificationsTickProvider);
    final unreadChats = ref.watch(unreadChatsProvider);
    final unreadNotes = ref.watch(unreadNotificationsProvider).value ?? 0;

    final drawerOpen = ref.watch(chatDrawerProvider.select((s) => s.open));
    final drawer = ref.read(chatDrawerProvider.notifier);

    void go(String path) {
      drawer.close();
      final branch = branchRoots.indexOf(path);
      final shell = this.shell;
      if (shell != null && branch >= 0) {
        // Tapping the page you are on goes back to its start.
        shell.goBranch(branch, initialLocation: branch == shell.currentIndex);
      } else if (location != path) {
        context.go(path);
      }
    }

    final canSeeReports = p != null && (p.isAdmin || p.role == 'manager');
    final isAdmin = p != null && p.isAdmin;

    final top = <(String, LiquidRailItem)>[
      (
        HomeScreen.routePath,
        LiquidRailItem(
          key: const Key('openHome'),
          icon: Icons.home_rounded,
          label: l10n.homeTitle,
          color: _home,
          onTap: () => go(HomeScreen.routePath),
        ),
      ),
      (
        GroupsScreen.routePath,
        LiquidRailItem(
          key: const Key('openGroups'),
          icon: Icons.groups_rounded,
          label: l10n.groupsTitle,
          color: _groups,
          onTap: () => go(GroupsScreen.routePath),
        ),
      ),
      (
        ChatsScreen.routePath,
        LiquidRailItem(
          key: const Key('openChats'),
          icon: Icons.chat_bubble_rounded,
          label: l10n.chatsTitle,
          color: _chats,
          badge: unreadChats,
          onTap: drawer.toggle,
        ),
      ),
      (
        NotificationsScreen.routePath,
        LiquidRailItem(
          key: const Key('openNotifications'),
          icon: Icons.notifications_rounded,
          label: l10n.notificationsTitle,
          color: _notifications,
          badge: unreadNotes,
          onTap: () => go(NotificationsScreen.routePath),
        ),
      ),
      (
        SearchScreen.routePath,
        LiquidRailItem(
          key: const Key('openSearch'),
          icon: Icons.search_rounded,
          label: l10n.searchTitle,
          color: _search,
          onTap: () => go(SearchScreen.routePath),
        ),
      ),
      (
        DirectoryScreen.routePath,
        LiquidRailItem(
          key: const Key('openDirectory'),
          icon: Icons.contacts_rounded,
          label: l10n.directoryTitle,
          color: _directory,
          onTap: () => go(DirectoryScreen.routePath),
        ),
      ),
      if (canSeeReports)
        (
          ReportsScreen.routePath,
          LiquidRailItem(
            key: const Key('openReports'),
            icon: Icons.flag_rounded,
            label: l10n.reportsTitle,
            color: _reports,
            onTap: () => go(ReportsScreen.routePath),
          ),
        ),
      if (isAdmin)
        (
          AdminScreen.routePath,
          LiquidRailItem(
            key: const Key('openAdminPanel'),
            icon: Icons.admin_panel_settings_rounded,
            label: l10n.adminPanel,
            color: _admin,
            onTap: () => go(AdminScreen.routePath),
          ),
        ),
    ];
    final bottom = <(String?, LiquidRailItem)>[
      (
        SecurityScreen.routePath,
        LiquidRailItem(
          icon: Icons.shield_rounded,
          label: l10n.securityTitle,
          color: _security,
          onTap: () => go(SecurityScreen.routePath),
        ),
      ),
      (
        MyProfileScreen.routePath,
        LiquidRailItem(
          key: const Key('openMyProfile'),
          icon: Icons.person_rounded,
          label: l10n.myProfile,
          color: _profile,
          onTap: () => go(MyProfileScreen.routePath),
        ),
      ),
      (
        null,
        LiquidRailItem(
          key: const Key('signOutButton'),
          icon: Icons.logout_rounded,
          label: l10n.signOut,
          color: _profile,
          onTap: () => ref.read(authRepositoryProvider).signOut(),
        ),
      ),
    ];

    // The rail item whose page (or a page under it) is open.
    int? selected;
    final paths = [...top.map((e) => e.$1), ...bottom.map((e) => e.$1)];
    var best = -1;
    for (var i = 0; i < paths.length; i++) {
      final path = paths[i];
      if (path == null) continue;
      final match = path == '/'
          ? location == '/' || location.startsWith('/posts')
          : location == path || location.startsWith('$path/');
      if (match && path.length > best) {
        best = path.length;
        selected = i;
      }
    }
    // The chat panel is open, or a chat page: "Chats" is lit.
    if (drawerOpen || (selected == null && location.startsWith('/chats'))) {
      selected = top.indexWhere((e) => e.$1 == ChatsScreen.routePath);
    }

    final theme = Theme.of(context);
    return Scaffold(
      body: BrandBackdrop(
        pattern: true,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => Row(
              children: [
                LiquidRail(
                  header: Tooltip(
                    message: BrandConfig.localizedAppName(
                      Localizations.localeOf(context),
                    ),
                    child: const BrandLogo(size: 40),
                  ),
                  top: [for (final e in top) e.$2],
                  bottom: [for (final e in bottom) e.$2],
                  extra: const [LanguageMenuButton()],
                  selected: selected,
                ),
                ChatDrawer(available: box.maxWidth - LiquidRail.width),
                Expanded(
                  // Pages are see-through so the animated background shows.
                  child: Theme(
                    data: theme.copyWith(
                      scaffoldBackgroundColor: Colors.transparent,
                    ),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
