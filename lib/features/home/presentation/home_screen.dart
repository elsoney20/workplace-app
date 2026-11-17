import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/config/brand_config.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../../core/widgets/language_menu_button.dart';
import '../../admin/presentation/admin_errors.dart';
import '../../admin/presentation/admin_screen.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/domain/my_profile.dart';
import '../../auth/presentation/security_screen.dart';
import '../../feed/presentation/feed_view.dart';

/// Home after login: the company feed.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const String routePath = '/';
  static const String routeName = 'home';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final appName = BrandConfig.localizedAppName(
      Localizations.localeOf(context),
    );
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
      appBar: AppBar(
        title: Row(
          children: [
            const BrandLogo(),
            const SizedBox(width: 12),
            Text(appName),
          ],
        ),
        actions: [
          const LanguageMenuButton(),
          IconButton(
            key: const Key('signOutButton'),
            tooltip: l10n.signOut,
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: switch (profile) {
            AsyncData(value: final p?) => FeedView(
              me: p,
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
    );
  }
}

/// Greeting + shortcuts above the feed.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.profile});

  final MyProfile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final details = [roleLabel(l10n, profile.role), ?profile.jobTitle];

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.homeHello(profile.fullName),
            style: theme.textTheme.headlineSmall,
          ),
          Text(details.join(' · '), style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (profile.isAdmin)
                _ActionCard(
                  key: const Key('openAdminPanel'),
                  icon: Icons.admin_panel_settings,
                  title: l10n.adminPanel,
                  onTap: () => context.push(AdminScreen.routePath),
                ),
              _ActionCard(
                icon: Icons.security,
                title: l10n.securityTitle,
                onTap: () => context.push(SecurityScreen.routePath),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(avatar: Icon(icon), label: Text(title), onPressed: onTap);
  }
}
