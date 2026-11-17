import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/brand_config.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/l10n/locale_controller.dart';
import '../../../core/supabase/backend_status_provider.dart';
import '../../../core/widgets/brand_logo.dart';

/// Temporary Phase 0 screen that proves theme, localization, RTL and the
/// Supabase connection all work. Replaced by the feed in Phase 3.
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

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const BrandLogo(),
            const SizedBox(width: 12),
            Text(appName),
          ],
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                l10n.homeWelcome(appName),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(l10n.homeSubtitle),
              const SizedBox(height: 24),
              const _LanguageCard(),
              const SizedBox(height: 16),
              const _DirectionCard(),
              const SizedBox(height: 16),
              const _BackendCard(),
              const SizedBox(height: 16),
              const _BrandColorsCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

enum _LanguageOption { system, english, arabic }

class _LanguageCard extends ConsumerWidget {
  const _LanguageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(localeControllerProvider);

    final selected = switch (locale?.languageCode) {
      'en' => _LanguageOption.english,
      'ar' => _LanguageOption.arabic,
      _ => _LanguageOption.system,
    };

    return _SectionCard(
      title: l10n.languageSectionTitle,
      child: SegmentedButton<_LanguageOption>(
        segments: [
          ButtonSegment(
            value: _LanguageOption.system,
            label: Text(l10n.languageSystem),
            icon: const Icon(Icons.computer),
          ),
          ButtonSegment(
            value: _LanguageOption.english,
            label: Text(l10n.languageEnglish),
          ),
          ButtonSegment(
            value: _LanguageOption.arabic,
            label: Text(l10n.languageArabic),
          ),
        ],
        selected: {selected},
        onSelectionChanged: (selection) {
          final newLocale = switch (selection.first) {
            _LanguageOption.system => null,
            _LanguageOption.english => const Locale('en'),
            _LanguageOption.arabic => const Locale('ar'),
          };
          ref.read(localeControllerProvider.notifier).setLocale(newLocale);
        },
      ),
    );
  }
}

class _DirectionCard extends StatelessWidget {
  const _DirectionCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return _SectionCard(
      title: l10n.directionSectionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // arrow_forward mirrors automatically in RTL.
              const Icon(Icons.arrow_forward),
              const SizedBox(width: 8),
              Text(
                l10n.directionCurrent(
                  isRtl ? l10n.directionRtl : l10n.directionLtr,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(decoration: InputDecoration(hintText: l10n.inputTestHint)),
        ],
      ),
    );
  }
}

class _BackendCard extends ConsumerWidget {
  const _BackendCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = ref.watch(backendStatusProvider);
    final colors = Theme.of(context).colorScheme;

    final (IconData icon, Color color, String label) = switch (status) {
      AsyncData(value: BackendStatus.online) => (
        Icons.cloud_done,
        Colors.green,
        l10n.backendOnline,
      ),
      AsyncData() ||
      AsyncError() => (Icons.cloud_off, colors.error, l10n.backendOffline),
      _ => (Icons.cloud_sync, colors.outline, l10n.backendChecking),
    };

    return _SectionCard(
      title: l10n.backendSectionTitle,
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          TextButton.icon(
            onPressed: () => ref.invalidate(backendStatusProvider),
            icon: const Icon(Icons.refresh),
            label: Text(l10n.retry),
          ),
        ],
      ),
    );
  }
}

class _BrandColorsCard extends StatelessWidget {
  const _BrandColorsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return _SectionCard(
      title: l10n.themeSectionTitle,
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          _ColorSwatch(
            color: BrandConfig.primaryColor,
            label: l10n.primaryColorLabel,
          ),
          _ColorSwatch(
            color: BrandConfig.secondaryColor,
            label: l10n.secondaryColorLabel,
          ),
          FilledButton(onPressed: () {}, child: Text(l10n.primaryColorLabel)),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}
