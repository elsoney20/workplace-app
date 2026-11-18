import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../data/auth_repository.dart';
import '../domain/phone_number.dart';
import '../application/auth_providers.dart';
import 'auth_layout.dart';
import 'otp_code_input.dart';

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
  OtpStatus _codeStatus = OtpStatus.idle;
  int _resendLeft = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(() {
      final text = _codeController.text;
      // Typing again after a wrong code clears the red state.
      if (_codeStatus == OtpStatus.error && text.length < OtpCodeInput.length) {
        setState(() => _codeStatus = OtpStatus.idle);
      }
      // The message stays until the first new digit is typed.
      if (_codeStatus == OtpStatus.idle && _error != null && text.isNotEmpty) {
        setState(() => _error = null);
      }
    });
  }

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
      setState(() {
        _error = l10n.codeInvalid;
        _codeStatus = OtpStatus.error;
      });
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _codeStatus = OtpStatus.checking;
    });
    final hold = ref.read(loginHoldProvider.notifier);
    // Keep this screen up until the check mark has been drawn.
    hold.set(true);
    try {
      await Future.wait([
        ref.read(authRepositoryProvider).verifyCode(_phoneE164!, code),
        // Let the tiles finish merging before showing the result.
        Future<void>.delayed(const Duration(milliseconds: 650)),
      ]);
      if (mounted) {
        setState(() => _codeStatus = OtpStatus.success);
        // Let the puzzle solve itself and turn green before moving on.
        await Future<void>.delayed(OtpCodeInput.successDuration);
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = authFailureMessage(l10n, error);
        _codeStatus = OtpStatus.error;
      });
      // Like the video: the red code shakes, then empties for a new try.
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        if (mounted && _codeStatus == OtpStatus.error) {
          setState(() => _codeStatus = OtpStatus.idle);
          _codeController.clear();
        }
      });
    } finally {
      // The router moves on by itself once the hold is released.
      hold.set(false);
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeNumber() {
    _timer?.cancel();
    setState(() {
      _phoneE164 = null;
      _codeController.clear();
      _error = null;
      _codeStatus = OtpStatus.idle;
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
        OtpCodeInput(
          controller: _codeController,
          status: _codeStatus,
          onCompleted: _verify,
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
            ResendCountdown(
              secondsLeft: _resendLeft,
              total: _resendSeconds,
              onResend: _busy ? null : _sendCode,
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
