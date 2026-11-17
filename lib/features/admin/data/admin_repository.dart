import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_bootstrap.dart';
import '../domain/department.dart';
import '../domain/employee.dart';

/// Admin-only reads and writes. The database (RLS) checks that the caller is
/// an admin on every call; the app hiding buttons is only for convenience.
class AdminRepository {
  AdminRepository(this._client);

  final SupabaseClient _client;

  Future<List<Employee>> listEmployees() async {
    final rows = await _client.rpc<List<dynamic>>('admin_list_employees');
    return rows
        .map((row) => Employee.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<void> addEmployee(EmployeeDraft draft) async {
    await _client.from('profiles').insert(draft.toJson());
  }

  Future<void> updateEmployee(String id, EmployeeDraft draft) async {
    await _client.from('profiles').update(draft.toJson()).eq('id', id);
  }

  /// Deactivating takes effect immediately: the database stops answering
  /// that employee's requests and their session cannot be refreshed.
  Future<void> setActive(String id, {required bool active}) async {
    await _client.from('profiles').update({'is_active': active}).eq('id', id);
  }

  Future<List<Department>> listDepartments() async {
    final rows = await _client
        .from('departments')
        .select('id, name_ar, name_en')
        .order('name_en');
    return rows.map(Department.fromJson).toList();
  }

  Future<void> addDepartment({
    required String nameAr,
    required String nameEn,
  }) async {
    await _client.from('departments').insert({
      'name_ar': nameAr,
      'name_en': nameEn,
    });
  }

  Future<void> updateDepartment(
    String id, {
    required String nameAr,
    required String nameEn,
  }) async {
    await _client
        .from('departments')
        .update({'name_ar': nameAr, 'name_en': nameEn})
        .eq('id', id);
  }
}

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.watch(supabaseClientProvider)),
);

final employeesProvider = FutureProvider.autoDispose<List<Employee>>(
  (ref) => ref.watch(adminRepositoryProvider).listEmployees(),
);

final departmentsProvider = FutureProvider.autoDispose<List<Department>>(
  (ref) => ref.watch(adminRepositoryProvider).listDepartments(),
);
