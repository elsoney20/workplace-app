import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../auth/application/auth_providers.dart';
import '../data/admin_repository.dart';
import '../domain/department.dart';
import '../domain/employee.dart';
import 'admin_errors.dart';
import 'department_form_dialog.dart';
import 'employee_form_dialog.dart';

/// Admin panel: employees (the login allowlist) and departments.
class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  static const String routePath = '/admin';
  static const String routeName = 'admin';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profile = ref.watch(myProfileProvider).value;

    if (profile == null || !profile.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.adminPanel)),
        body: Center(child: Text(l10n.notAllowed)),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.adminPanel),
          bottom: TabBar(
            tabs: [
              Tab(icon: const Icon(Icons.badge), text: l10n.employeesTab),
              Tab(icon: const Icon(Icons.apartment), text: l10n.departmentsTab),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _EmployeesTab(myProfileId: profile.id),
            const _DepartmentsTab(),
          ],
        ),
      ),
    );
  }
}

enum _StatusFilter { all, active, inactive }

class _EmployeesTab extends ConsumerStatefulWidget {
  const _EmployeesTab({required this.myProfileId});

  final String myProfileId;

  @override
  ConsumerState<_EmployeesTab> createState() => _EmployeesTabState();
}

class _EmployeesTabState extends ConsumerState<_EmployeesTab> {
  String _query = '';
  _StatusFilter _filter = _StatusFilter.all;

  List<Employee> _filtered(List<Employee> all) {
    final query = _query.trim().toLowerCase();
    final digits = query.replaceAll(RegExp(r'\D'), '');
    return all.where((e) {
      final statusOk = switch (_filter) {
        _StatusFilter.all => true,
        _StatusFilter.active => e.isActive,
        _StatusFilter.inactive => !e.isActive,
      };
      if (!statusOk) return false;
      if (query.isEmpty) return true;
      return e.fullName.toLowerCase().contains(query) ||
          (digits.length >= 3 &&
              e.phone.contains(digits.replaceFirst(RegExp('^0'), ''))) ||
          (e.jobTitle?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  Future<void> _openForm({Employee? employee}) async {
    final departments = await ref.read(departmentsProvider.future);
    if (!mounted) return;
    final saved = await showEmployeeFormDialog(
      context,
      departments: departments,
      employee: employee,
      isSelf: employee?.id == widget.myProfileId,
    );
    if (saved == true) {
      ref.invalidate(employeesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).savedMessage)),
      );
    }
  }

  Future<void> _toggleActive(Employee employee) async {
    final l10n = AppLocalizations.of(context);
    if (employee.isActive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.deactivateTitle(employee.fullName)),
          content: Text(l10n.deactivateBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.deactivate),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    try {
      await ref
          .read(adminRepositoryProvider)
          .setActive(employee.id, active: !employee.isActive);
      ref.invalidate(employeesProvider);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(adminErrorMessage(l10n, error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final employees = ref.watch(employeesProvider);
    final departments = ref.watch(departmentsProvider).value ?? const [];
    final departmentsById = {for (final d in departments) d.id: d};

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('addEmployeeButton'),
        onPressed: () => _openForm(),
        icon: const Icon(Icons.person_add),
        label: Text(l10n.addEmployee),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 320,
                  child: TextField(
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: l10n.searchEmployees,
                      isDense: true,
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                SegmentedButton<_StatusFilter>(
                  segments: [
                    ButtonSegment(
                      value: _StatusFilter.all,
                      label: Text(l10n.filterAll),
                    ),
                    ButtonSegment(
                      value: _StatusFilter.active,
                      label: Text(l10n.filterActive),
                    ),
                    ButtonSegment(
                      value: _StatusFilter.inactive,
                      label: Text(l10n.filterInactive),
                    ),
                  ],
                  selected: {_filter},
                  onSelectionChanged: (s) => setState(() => _filter = s.first),
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (employees) {
              AsyncData(:final value) => _buildList(
                context,
                _filtered(value),
                departmentsById,
              ),
              AsyncError(:final error) => Center(
                child: Text(adminErrorMessage(l10n, error)),
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    List<Employee> list,
    Map<String, Department> departmentsById,
  ) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context);
    final colors = Theme.of(context).colorScheme;

    if (list.isEmpty) return Center(child: Text(l10n.employeesEmpty));

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: list.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Text(
            l10n.employeeCount(list.length),
            style: Theme.of(context).textTheme.labelLarge,
          );
        }
        final e = list[index - 1];
        final isSelf = e.id == widget.myProfileId;
        final department = departmentsById[e.departmentId]?.localizedName(
          locale,
        );
        final details = [?e.jobTitle, ?department].join(' · ');

        return Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: e.isActive
                  ? colors.primaryContainer
                  : colors.surfaceContainerHighest,
              child: Text(e.fullName.characters.first.toUpperCase()),
            ),
            title: Text(
              e.fullName,
              style: TextStyle(
                decoration: e.isActive ? null : TextDecoration.lineThrough,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.phone, textDirection: TextDirection.ltr),
                if (details.isNotEmpty) Text(details),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _Badge(roleLabel(l10n, e.role), colors.secondaryContainer),
                    _Badge(
                      e.isActive ? l10n.statusActive : l10n.statusInactive,
                      e.isActive
                          ? Colors.green.withValues(alpha: 0.2)
                          : colors.errorContainer,
                    ),
                    if (!e.hasLoggedIn && e.isActive)
                      _Badge(
                        l10n.notLoggedInYet,
                        colors.surfaceContainerHighest,
                      ),
                  ],
                ),
              ],
            ),
            isThreeLine: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: l10n.editEmployee,
                  icon: const Icon(Icons.edit),
                  onPressed: () => _openForm(employee: e),
                ),
                Tooltip(
                  message: e.isActive ? l10n.deactivate : l10n.reactivate,
                  child: Switch(
                    value: e.isActive,
                    onChanged: isSelf ? null : (_) => _toggleActive(e),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

class _DepartmentsTab extends ConsumerWidget {
  const _DepartmentsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final departments = ref.watch(departmentsProvider);

    Future<void> open({Department? department}) async {
      final saved = await showDepartmentFormDialog(
        context,
        department: department,
      );
      if (saved == true) ref.invalidate(departmentsProvider);
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => open(),
        icon: const Icon(Icons.add),
        label: Text(l10n.addDepartment),
      ),
      body: switch (departments) {
        AsyncData(:final value) when value.isEmpty => Center(
          child: Text(l10n.departmentsEmpty),
        ),
        AsyncData(:final value) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: value.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final d = value[index];
            return Card(
              child: ListTile(
                leading: const Icon(Icons.apartment),
                title: Text(d.nameAr),
                subtitle: Text(d.nameEn),
                trailing: IconButton(
                  tooltip: l10n.editDepartment,
                  icon: const Icon(Icons.edit),
                  onPressed: () => open(department: d),
                ),
              ),
            );
          },
        ),
        AsyncError(:final error) => Center(
          child: Text(adminErrorMessage(l10n, error)),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
