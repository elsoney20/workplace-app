import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../data/admin_repository.dart';
import '../domain/department.dart';
import 'admin_errors.dart';

/// Add (department == null) or rename a department. Returns true when saved.
Future<bool?> showDepartmentFormDialog(
  BuildContext context, {
  Department? department,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (context) => _DepartmentFormDialog(department: department),
);

class _DepartmentFormDialog extends ConsumerStatefulWidget {
  const _DepartmentFormDialog({required this.department});

  final Department? department;

  @override
  ConsumerState<_DepartmentFormDialog> createState() =>
      _DepartmentFormDialogState();
}

class _DepartmentFormDialogState extends ConsumerState<_DepartmentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameAr = TextEditingController(
    text: widget.department?.nameAr ?? '',
  );
  late final TextEditingController _nameEn = TextEditingController(
    text: widget.department?.nameEn ?? '',
  );
  late String? _managerId = widget.department?.managerId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameAr.dispose();
    _nameEn.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(adminRepositoryProvider);
      final department = widget.department;
      if (department == null) {
        await repository.addDepartment(
          nameAr: _nameAr.text.trim(),
          nameEn: _nameEn.text.trim(),
          managerId: _managerId,
        );
      } else {
        await repository.updateDepartment(
          department.id,
          nameAr: _nameAr.text.trim(),
          nameEn: _nameEn.text.trim(),
          managerId: _managerId,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on Object catch (error) {
      if (mounted) setState(() => _error = adminErrorMessage(l10n, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String? required(String? v) =>
        (v ?? '').trim().isEmpty ? l10n.fieldRequired : null;

    return AlertDialog(
      title: Text(
        widget.department == null ? l10n.addDepartment : l10n.editDepartment,
      ),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameAr,
                autofocus: true,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(labelText: l10n.departmentNameAr),
                validator: required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameEn,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: l10n.departmentNameEn),
                validator: required,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: const Key('departmentManagerField'),
                initialValue: _managerId,
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n.departmentManager),
                items: [
                  DropdownMenuItem(value: null, child: Text(l10n.noManager)),
                  for (final e
                      in ref.watch(employeesProvider).value ?? const [])
                    if (e.isActive || e.id == _managerId)
                      DropdownMenuItem(value: e.id, child: Text(e.fullName)),
                ],
                onChanged: _busy ? null : (v) => setState(() => _managerId = v),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _busy ? null : _save, child: Text(l10n.save)),
      ],
    );
  }
}
