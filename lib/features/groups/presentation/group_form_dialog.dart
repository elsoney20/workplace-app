import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../data/groups_repository.dart';
import '../domain/work_group.dart';

/// Create a group (group == null) or edit its name/description/privacy.
/// Returns the group id when saved.
Future<String?> showGroupFormDialog(BuildContext context, {WorkGroup? group}) =>
    showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GroupFormDialog(group: group),
    );

class _GroupFormDialog extends ConsumerStatefulWidget {
  const _GroupFormDialog({this.group});

  final WorkGroup? group;

  @override
  ConsumerState<_GroupFormDialog> createState() => _GroupFormDialogState();
}

class _GroupFormDialogState extends ConsumerState<_GroupFormDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.group?.name ?? '');
  late final _description = TextEditingController(
    text: widget.group?.description ?? '',
  );
  late GroupPrivacy _privacy = widget.group?.privacy ?? GroupPrivacy.public;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(groupsRepositoryProvider);
    try {
      final group = widget.group;
      final description = _description.text.trim().isEmpty
          ? null
          : _description.text.trim();
      if (group == null) {
        final id = await repo.createGroup(
          name: _name.text.trim(),
          description: description,
          privacy: _privacy,
        );
        if (mounted) Navigator.pop(context, id);
      } else {
        await repo.updateGroup(
          group.id,
          name: _name.text.trim(),
          description: description,
          privacy: _privacy,
        );
        if (mounted) Navigator.pop(context, group.id);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AppLocalizations.of(context).errorUnknown;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isDepartment = widget.group?.isDepartment ?? false;
    return AlertDialog(
      title: Text(widget.group == null ? l10n.createGroup : l10n.editGroup),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('groupNameField'),
                controller: _name,
                autofocus: true,
                maxLength: 120,
                decoration: InputDecoration(labelText: l10n.groupName),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null,
              ),
              TextFormField(
                controller: _description,
                maxLines: 3,
                maxLength: 2000,
                decoration: InputDecoration(labelText: l10n.groupDescription),
              ),
              if (!isDepartment) ...[
                RadioGroup<GroupPrivacy>(
                  groupValue: _privacy,
                  onChanged: (v) => setState(() => _privacy = v ?? _privacy),
                  child: Column(
                    children: [
                      RadioListTile(
                        value: GroupPrivacy.public,
                        title: Text(l10n.groupPublic),
                        subtitle: Text(l10n.groupPublicHint),
                        secondary: const Icon(Icons.public),
                      ),
                      RadioListTile(
                        value: GroupPrivacy.private,
                        title: Text(l10n.groupPrivate),
                        subtitle: Text(l10n.groupPrivateHint),
                        secondary: const Icon(Icons.lock_outline),
                      ),
                    ],
                  ),
                ),
              ],
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('saveGroupButton'),
          onPressed: _busy ? null : _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
