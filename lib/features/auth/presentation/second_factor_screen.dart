import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../data/auth_repository.dart';
import 'auth_layout.dart';

/// Shown after the SMS code when the employee has an authenticator app on.
class SecondFactorScreen extends ConsumerStatefulWidget {
  const SecondFactorScreen({super.key});

  static const String routePath = '/login/authenticator';
  static const String routeName = 'second-factor';

  @override
  ConsumerState<SecondFactorScreen> createState() => _SecondFactorScreenState();
}

class _SecondFactorScreenState extends ConsumerState<SecondFactorScreen> {
  final _codeController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final l10n = AppLocalizations.of(context);
    final code = cleanCode(_codeController.text);
    if (code.length != 6) {
      setState(() => _error = l10n.codeInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(authRepositoryProvider);
      final factor = await repository.verifiedAuthenticator();
      if (factor == null) {
        // Nothing to verify (removed meanwhile); refresh the session.
        await repository.signOut();
        return;
      }
      await repository.verifyAuthenticatorCode(factor.id, code);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = authFailureMessage(l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthLayout(
      title: l10n.secondFactorTitle,
      subtitle: l10n.secondFactorSubtitle,
      children: [
        CodeField(
          controller: _codeController,
          label: l10n.codeLabel,
          onSubmitted: () => _busy ? null : _verify(),
        ),
        AuthErrorText(_error),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _verify,
          child: Text(l10n.verify),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy
              ? null
              : () => ref.read(authRepositoryProvider).signOut(),
          child: Text(l10n.signOut),
        ),
      ],
    );
  }
}
