import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../features/admin/presentation/admin_screen.dart';
import '../../features/auth/application/auth_providers.dart';
import '../../features/auth/domain/auth_status.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/second_factor_screen.dart';
import '../../features/auth/presentation/security_screen.dart';
import '../../features/home/presentation/home_screen.dart';

/// App routes. Logged-out users only ever see the login screens.
final appRouterProvider = Provider<GoRouter>((ref) {
  // Tells the router to re-run [redirect] when the login state changes.
  final refresh = ValueNotifier<AuthStatus>(ref.read(authStatusProvider));
  ref.listen(authStatusProvider, (_, next) => refresh.value = next);

  final router = GoRouter(
    initialLocation: HomeScreen.routePath,
    refreshListenable: refresh,
    redirect: (context, state) {
      final location = state.matchedLocation;
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
        path: HomeScreen.routePath,
        name: HomeScreen.routeName,
        builder: (context, state) => const HomeScreen(),
      ),
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
      GoRoute(
        path: AdminScreen.routePath,
        name: AdminScreen.routeName,
        builder: (context, state) => const AdminScreen(),
      ),
      GoRoute(
        path: SecurityScreen.routePath,
        name: SecurityScreen.routeName,
        builder: (context, state) => const SecurityScreen(),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});
