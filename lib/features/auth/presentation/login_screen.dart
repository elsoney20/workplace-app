import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../data/auth_repository.dart';
import '../domain/phone_number.dart';
import 'auth_layout.dart';

/// Step 1: phone number. Step 2: the 6-digit SMS code.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  static const String routePath = '/login';
  static const String routeName = 'login';

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const int _resendSeconds = 60;

  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();

  /// Set once the code was sent; switches the screen to step 2.
  String? _phoneE164;
  bool _busy = false;
  String? _error;
  int _resendLeft = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _timer?.cancel();
    setState(() => _resendLeft = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _resendLeft--);
      if (_resendLeft <= 0) timer.cancel();
    });
  }

  Future<void> _sendCode() async {
    final l10n = AppLocalizations.of(context);
    final phone = _phoneE164 ?? PhoneNumber.normalize(_phoneController.text);
    if (phone == null) {
      setState(() => _error = l10n.phoneInvalid);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authRepositoryProvider).sendCode(phone);
      if (!mounted) return;
      setState(() => _phoneE164 = phone);
      _startResendTimer();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = authFailureMessage(l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
      // On success the router moves on automatically.
      await ref.read(authRepositoryProvider).verifyCode(_phoneE164!, code);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = authFailureMessage(l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeNumber() {
    _timer?.cancel();
    setState(() {
      _phoneE164 = null;
      _codeController.clear();
      _error = null;
      _resendLeft = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final phone = _phoneE164;

    if (phone == null) {
      return AuthLayout(
        title: l10n.loginTitle,
        subtitle: l10n.loginSubtitle,
        children: [
          TextField(
            key: const Key('phoneField'),
            controller: _phoneController,
            autofocus: true,
            keyboardType: TextInputType.phone,
            // Phone numbers always read left to right, even in Arabic.
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: l10n.phoneLabel,
              hintText: l10n.phoneHint,
              prefixIcon: const Icon(Icons.phone_android),
            ),
            onSubmitted: (_) => _busy ? null : _sendCode(),
          ),
          AuthErrorText(_error),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('sendCodeButton'),
            onPressed: _busy ? null : _sendCode,
            child: _ButtonLabel(busy: _busy, text: l10n.sendCode),
          ),
        ],
      );
    }

    return AuthLayout(
      title: l10n.codeTitle,
      subtitle: l10n.codeSentTo('\u2066$phone\u2069'),
      children: [
        CodeField(
          controller: _codeController,
          label: l10n.codeLabel,
          onSubmitted: () => _busy ? null : _verify(),
        ),
        AuthErrorText(_error),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('verifyButton'),
          onPressed: _busy ? null : _verify,
          child: _ButtonLabel(busy: _busy, text: l10n.verify),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _busy ? null : _changeNumber,
              child: Text(l10n.changeNumber),
            ),
            TextButton(
              onPressed: _busy || _resendLeft > 0 ? null : _sendCode,
              child: Text(
                _resendLeft > 0 ? l10n.resendIn(_resendLeft) : l10n.resendCode,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ButtonLabel extends StatelessWidget {
  const _ButtonLabel({required this.busy, required this.text});

  final bool busy;
  final String text;

  @override
  Widget build(BuildContext context) {
    if (!busy) return Text(text);
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
