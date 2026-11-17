import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../auth/domain/phone_number.dart';
import '../data/admin_repository.dart';
import '../domain/department.dart';
import '../domain/employee.dart';
import 'admin_errors.dart';

/// Add (employee == null) or edit an employee. Returns true when saved.
Future<bool?> showEmployeeFormDialog(
  BuildContext context, {
  required List<Department> departments,
  Employee? employee,
  bool isSelf = false,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (context) => _EmployeeFormDialog(
    departments: departments,
    employee: employee,
    isSelf: isSelf,
  ),
);

class _EmployeeFormDialog extends ConsumerStatefulWidget {
  const _EmployeeFormDialog({
    required this.departments,
    required this.employee,
    required this.isSelf,
  });

  final List<Department> departments;
  final Employee? employee;
  final bool isSelf;

  @override
  ConsumerState<_EmployeeFormDialog> createState() =>
      _EmployeeFormDialogState();
}

class _EmployeeFormDialogState extends ConsumerState<_EmployeeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _jobTitle;
  late String _role;
  String? _departmentId;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.employee != null;

  @override
  void initState() {
    super.initState();
    final e = widget.employee;
    _name = TextEditingController(text: e?.fullName ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _jobTitle = TextEditingController(text: e?.jobTitle ?? '');
    _role = e?.role ?? 'employee';
    final departmentIds = widget.departments.map((d) => d.id).toSet();
    _departmentId = departmentIds.contains(e?.departmentId)
        ? e?.departmentId
        : null;
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _jobTitle.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    final jobTitle = _jobTitle.text.trim();
    final draft = EmployeeDraft(
      fullName: _name.text.trim(),
      phone: PhoneNumber.normalize(_phone.text)!,
      role: _role,
      departmentId: _departmentId,
      jobTitle: jobTitle.isEmpty ? null : jobTitle,
    );

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repository = ref.read(adminRepositoryProvider);
      final employee = widget.employee;
      if (employee == null) {
        await repository.addEmployee(draft);
      } else {
        await repository.updateEmployee(employee.id, draft);
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
    final locale = Localizations.localeOf(context);
    final phoneChanged =
        _isEdit &&
        widget.employee!.hasLoggedIn &&
        PhoneNumber.normalize(_phone.text) != widget.employee!.phone;

    return AlertDialog(
      title: Text(_isEdit ? l10n.editEmployee : l10n.addEmployee),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  key: const Key('employeeName'),
                  controller: _name,
                  autofocus: true,
                  decoration: InputDecoration(labelText: l10n.fullNameLabel),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? l10n.fieldRequired : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('employeePhone'),
                  controller: _phone,
                  enabled: !widget.isSelf,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: l10n.phoneLabel,
                    hintText: l10n.phoneHint,
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) => PhoneNumber.normalize(v ?? '') == null
                      ? l10n.phoneInvalid
                      : null,
                ),
                if (phoneChanged)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      l10n.phoneChangeWarning,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _jobTitle,
                  decoration: InputDecoration(labelText: l10n.jobTitleLabel),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _departmentId,
                  decoration: InputDecoration(labelText: l10n.departmentLabel),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(l10n.noDepartment),
                    ),
                    for (final d in widget.departments)
                      DropdownMenuItem(
                        value: d.id,
                        child: Text(d.localizedName(locale)),
                      ),
                  ],
                  onChanged: (v) => setState(() => _departmentId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: InputDecoration(labelText: l10n.roleLabel),
                  items: [
                    for (final role in appRoles)
                      DropdownMenuItem(
                        value: role,
                        child: Text(roleLabel(l10n, role)),
                      ),
                  ],
                  onChanged: widget.isSelf
                      ? null
                      : (v) => setState(() => _role = v ?? 'employee'),
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
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('employeeSave'),
          onPressed: _busy ? null : _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
