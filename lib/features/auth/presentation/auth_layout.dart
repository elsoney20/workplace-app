import 'package:material_ui/material_ui.dart';

import '../../../core/config/brand_config.dart';
import '../../../core/widgets/brand_logo.dart';
import '../../../core/widgets/language_menu_button.dart';
import '../../../core/l10n/generated/app_localizations.dart';
import '../domain/auth_failure.dart';

/// Centered card used by all login screens.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(actions: const [LanguageMenuButton()]),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: BrandLogo(size: 64)),
                    const SizedBox(height: 12),
                    Text(
                      BrandConfig.localizedAppName(
                        Localizations.localeOf(context),
                      ),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(title, style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text(subtitle, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 24),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 6-digit code input.
class CodeField extends StatelessWidget {
  const CodeField({
    super.key,
    required this.controller,
    required this.label,
    required this.onSubmitted,
    this.autofocus = true,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onSubmitted;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const Key('codeField'),
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.number,
      maxLength: 6,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 24, letterSpacing: 8),
      decoration: InputDecoration(labelText: label, counterText: ''),
      onSubmitted: (_) => onSubmitted(),
    );
  }
}

/// Red error text under a form.
class AuthErrorText extends StatelessWidget {
  const AuthErrorText(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final text = message;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        text,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}

/// Translated message for a login problem.
String authFailureMessage(AppLocalizations l10n, Object error) =>
    switch (AuthFailure.from(error)) {
      AuthFailure.notRegistered => l10n.errorNotRegistered,
      AuthFailure.notActive => l10n.errorNotActive,
      AuthFailure.wrongCode => l10n.errorWrongCode,
      AuthFailure.tooManyAttempts => l10n.errorTooMany,
      AuthFailure.network => l10n.errorNetwork,
      AuthFailure.unknown => l10n.errorUnknown,
    };

/// Normalizes a typed code: keeps Latin and Arabic-Indic digits only.
String cleanCode(String input) => input
    .replaceAllMapped(
      RegExp('[٠-٩]'),
      (m) => String.fromCharCode(m[0]!.codeUnitAt(0) - 0x0660 + 0x30),
    )
    .replaceAll(RegExp(r'\D'), '');
