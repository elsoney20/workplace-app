import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/admin/presentation/admin_screen.dart';
import '../../features/auth/application/auth_providers.dart';
import '../../features/auth/domain/auth_status.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/second_factor_screen.dart';
import '../../features/auth/presentation/security_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/chat/presentation/chats_screen.dart';
import '../../features/directory/presentation/directory_screen.dart';
import '../../features/feed/presentation/post_screen.dart';
import '../../features/groups/presentation/group_screen.dart';
import '../../features/groups/presentation/groups_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/moderation/presentation/reports_screen.dart';
import '../../features/notifications/application/desktop_notifier.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/shell/branch_switcher.dart';

/// App routes. Logged-out users only ever see the login screens.
final appRouterProvider = Provider<GoRouter>((ref) {
  // Tells the router to re-run [redirect] when the login state changes.
  final refresh = ValueNotifier<AuthStatus>(ref.read(authStatusProvider));
  ref.listen(authStatusProvider, (_, next) => refresh.value = next);
  final hold = ValueNotifier<bool>(ref.read(loginHoldProvider));
  ref.listen(loginHoldProvider, (_, next) => hold.value = next);

  final router = GoRouter(
    initialLocation: HomeScreen.routePath,
    refreshListenable: Listenable.merge([refresh, hold]),
    redirect: (context, state) {
      final location = state.matchedLocation;
      // The login screen is finishing its check-mark animation.
      if (hold.value && location == LoginScreen.routePath) return null;
      return switch (refresh.value) {
        AuthStatus.signedOut =>
          location == LoginScreen.routePath ? null : LoginScreen.routePath,
        AuthStatus.needsSecondFactor =>
          location == SecondFactorScreen.routePath
              ? null
              : SecondFactorScreen.routePath,
        AuthStatus.signedIn =>
          location.startsWith(LoginScreen.routePath)
              ? HomeScreen.routePath
              : null,
      };
    },
    routes: [
      GoRoute(
        path: LoginScreen.routePath,
        name: LoginScreen.routeName,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: SecondFactorScreen.routePath,
        name: SecondFactorScreen.routeName,
        builder: (context, state) => const SecondFactorScreen(),
      ),
      // Every signed-in page sits inside the shell (rail + background).
      // Each rail destination is its own branch that stays alive: switching
      // is instant and a page keeps its scroll position and data.
      // Keep the branch order in sync with AppShell.branchRoots.
      StatefulShellRoute(
        builder: (context, state, shell) =>
            AppShell(location: state.uri.path, shell: shell, child: shell),
        navigatorContainerBuilder: (context, shell, children) =>
            BranchSwitcher(index: shell.currentIndex, children: children),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: HomeScreen.routePath,
                name: HomeScreen.routeName,
                builder: (context, state) => const HomeScreen(),
              ),
              GoRoute(
                path: PostScreen.routePath,
                name: PostScreen.routeName,
                builder: (context, state) =>
                    PostScreen(postId: state.pathParameters['id']!),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: GroupsScreen.routePath,
                name: GroupsScreen.routeName,
                builder: (context, state) => const GroupsScreen(),
              ),
              GoRoute(
                path: GroupScreen.routePath,
                name: GroupScreen.routeName,
                builder: (context, state) =>
                    GroupScreen(groupId: state.pathParameters['id']!),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: ChatsScreen.routePath,
                name: ChatsScreen.routeName,
                builder: (context, state) => const ChatsScreen(),
              ),
              GoRoute(
                path: ChatScreen.routePath,
                name: ChatScreen.routeName,
                builder: (context, state) =>
                    ChatScreen(conversationId: state.pathParameters['id']!),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: NotificationsScreen.routePath,
                name: NotificationsScreen.routeName,
                builder: (context, state) => const NotificationsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: SearchScreen.routePath,
                name: SearchScreen.routeName,
                builder: (context, state) => const SearchScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: DirectoryScreen.routePath,
                name: DirectoryScreen.routeName,
                builder: (context, state) => const DirectoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: ReportsScreen.routePath,
                name: ReportsScreen.routeName,
                builder: (context, state) => const ReportsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AdminScreen.routePath,
                name: AdminScreen.routeName,
                builder: (context, state) => const AdminScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: SecurityScreen.routePath,
                name: SecurityScreen.routeName,
                builder: (context, state) => const SecurityScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: MyProfileScreen.routePath,
                name: MyProfileScreen.routeName,
                builder: (context, state) => const MyProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  // Clicking a Windows toast opens the post / group it is about.
  ref.read(desktopNotifierProvider).onOpen = (target) {
    final postId = target['post_id'] as String?;
    final groupId = target['group_id'] as String?;
    if (postId != null) {
      router.push(PostScreen.pathFor(postId));
    } else if (groupId != null) {
      router.push(GroupScreen.pathFor(groupId));
    } else {
      router.push(NotificationsScreen.routePath);
    }
  };
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
