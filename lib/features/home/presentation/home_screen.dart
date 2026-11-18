import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/widgets/motion.dart';
import '../../admin/presentation/admin_errors.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/domain/my_profile.dart';
import '../../feed/domain/feed_scope.dart';
import '../../feed/presentation/feed_view.dart';
import '../../search/presentation/search_screen.dart';

/// Home after login: the company feed. The rail and the chat panel live in
/// AppShell.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  static const String routePath = '/';
  static const String routeName = 'home';

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(myProfileProvider);

    return Scaffold(
      body: Builder(
        builder: (context) {
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
