import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../data/moderation_repository.dart';

/// Asks why, then reports a post or a comment. Shows a thank-you snack bar.
Future<void> showReportDialog(
  BuildContext context,
  WidgetRef ref, {
  String? postId,
  String? commentId,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final repo = ref.read(moderationRepositoryProvider);
  final reason = await showDialog<String>(
    context: context,
    builder: (context) => const _ReportDialog(),
  );
  if (reason == null) return;
  try {
    await repo.report(postId: postId, commentId: commentId, reason: reason);
    messenger.showSnackBar(SnackBar(content: Text(l10n.reportSent)));
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.errorUnknown)));
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog();

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.reportTitle),
      content: SizedBox(
        width: 400,
        child: TextField(
          key: const Key('reportReason'),
          controller: _controller,
          autofocus: true,
          maxLines: 3,
          maxLength: 500,
          decoration: InputDecoration(hintText: l10n.reportReasonHint),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('reportSend'),
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(l10n.reportAction),
        ),
      ],
    );
  }
}
