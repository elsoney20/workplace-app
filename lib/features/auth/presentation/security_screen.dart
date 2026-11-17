import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../data/auth_repository.dart';
import 'auth_layout.dart';

/// The verified authenticator app of the signed-in user (null = off).
final _authenticatorProvider = FutureProvider.autoDispose<Factor?>(
  (ref) => ref.watch(authRepositoryProvider).verifiedAuthenticator(),
);

/// Turn the authenticator app (second lock) on or off.
class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});

  static const String routePath = '/security';
  static const String routeName = 'security';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final authenticator = ref.watch(_authenticatorProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.securityTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              switch (authenticator) {
                AsyncData(value: final factor?) => _EnabledCard(factor: factor),
                AsyncData() => const _SetupCard(),
                AsyncError(:final error) => Text(
                  authFailureMessage(l10n, error),
                ),
                _ => const Center(child: CircularProgressIndicator()),
              },
            ],
          ),
        ),
      ),
    );
  }
}

class _EnabledCard extends ConsumerWidget {
  const _EnabledCard({required this.factor});

  final Factor factor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    Future<void> disable() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: Text(l10n.authenticatorDisableConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.authenticatorDisable),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      try {
        await ref.read(authRepositoryProvider).removeAuthenticator(factor.id);
        ref.invalidate(_authenticatorProvider);
      } on Object catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(authFailureMessage(l10n, error))),
        );
      }
    }

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: const Icon(Icons.verified_user, color: Colors.green, size: 36),
        title: Text(l10n.authenticatorOn),
        subtitle: Text(l10n.authenticatorOnBody),
        trailing: OutlinedButton(
          onPressed: disable,
          child: Text(l10n.authenticatorDisable),
        ),
      ),
    );
  }
}

class _SetupCard extends ConsumerStatefulWidget {
  const _SetupCard();

  @override
  ConsumerState<_SetupCard> createState() => _SetupCardState();
}

class _SetupCardState extends ConsumerState<_SetupCard> {
  final _codeController = TextEditingController();
  AuthMFAEnrollResponse? _enrollment;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final enrollment = await ref
          .read(authRepositoryProvider)
          .startAuthenticatorSetup();
      if (mounted) setState(() => _enrollment = enrollment);
    } on Object catch (error) {
      if (mounted) setState(() => _error = authFailureMessage(l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
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
      await ref
          .read(authRepositoryProvider)
          .verifyAuthenticatorCode(_enrollment!.id, code);
      ref.invalidate(_authenticatorProvider);
    } on Object catch (error) {
      if (mounted) setState(() => _error = authFailureMessage(l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final enrollment = _enrollment;
    final totp = enrollment?.totp;

    if (enrollment == null || totp == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.shield_outlined, size: 36),
                title: Text(l10n.authenticatorOff),
                subtitle: Text(l10n.authenticatorOffBody),
              ),
              AuthErrorText(_error),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : _start,
                child: Text(l10n.authenticatorEnable),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.authenticatorStep1),
            const SizedBox(height: 12),
            Text(l10n.authenticatorStep2),
            const SizedBox(height: 12),
            Center(
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(data: totp.uri, size: 200),
              ),
            ),
            const SizedBox(height: 12),
            Text(l10n.authenticatorManual),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    totp.secret,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: totp.secret));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(l10n.copied)));
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(l10n.authenticatorStep3),
            const SizedBox(height: 8),
            CodeField(
              controller: _codeController,
              label: l10n.codeLabel,
              onSubmitted: () => _busy ? null : _confirm(),
            ),
            AuthErrorText(_error),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _confirm,
              child: Text(l10n.verify),
            ),
          ],
        ),
      ),
    );
  }
}
