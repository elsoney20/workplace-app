/// One row of the admin employee list (`public.admin_list_employees()`).
class Employee {
  const Employee({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.isActive,
    required this.hasLoggedIn,
    this.departmentId,
    this.jobTitle,
    this.deactivatedAt,
  });

  factory Employee.fromJson(Map<String, dynamic> json) => Employee(
    id: json['id'] as String,
    fullName: json['full_name'] as String,
    phone: json['phone'] as String,
    role: json['role'] as String,
    isActive: json['is_active'] as bool,
    hasLoggedIn: json['has_logged_in'] as bool,
    departmentId: json['department_id'] as String?,
    jobTitle: json['job_title'] as String?,
    deactivatedAt: json['deactivated_at'] == null
        ? null
        : DateTime.parse(json['deactivated_at'] as String),
  );

  final String id;
  final String fullName;
  final String phone;
  final String role;
  final bool isActive;
  final bool hasLoggedIn;
  final String? departmentId;
  final String? jobTitle;
  final DateTime? deactivatedAt;
}

/// Data the admin fills in when adding or editing an employee.
class EmployeeDraft {
  const EmployeeDraft({
    required this.fullName,
    required this.phone,
    required this.role,
    this.departmentId,
    this.jobTitle,
  });

  final String fullName;

  /// E.164, e.g. +201001234567.
  final String phone;
  final String role;
  final String? departmentId;
  final String? jobTitle;

  Map<String, dynamic> toJson() => {
    'full_name': fullName,
    'phone': phone,
    'role': role,
    'department_id': departmentId,
    'job_title': jobTitle,
  };
}

const List<String> appRoles = ['employee', 'manager', 'admin'];
