import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../l10n/generated/app_localizations.dart';
import '../l10n/locale_controller.dart';

/// App bar button to switch between Arabic, English and the OS language.
class LanguageMenuButton extends ConsumerWidget {
  const LanguageMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(localeControllerProvider.notifier);

    return PopupMenuButton<String>(
      key: const Key('languageMenu'),
      icon: const Icon(Icons.translate),
      tooltip: l10n.languageSectionTitle,
      onSelected: (code) =>
          controller.setLocale(code == 'system' ? null : Locale(code)),
      itemBuilder: (context) => [
        PopupMenuItem(value: 'ar', child: Text(l10n.languageArabic)),
        PopupMenuItem(value: 'en', child: Text(l10n.languageEnglish)),
        PopupMenuItem(value: 'system', child: Text(l10n.languageSystem)),
      ],
    );
  }
}
