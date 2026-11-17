/// The signed-in employee's own profile (from `public.get_my_profile()`).
class MyProfile {
  const MyProfile({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.role,
    this.departmentId,
    this.jobTitle,
    this.locale,
  });

  factory MyProfile.fromJson(Map<String, dynamic> json) => MyProfile(
    id: json['id'] as String,
    fullName: json['full_name'] as String,
    phone: json['phone'] as String,
    role: json['role'] as String,
    departmentId: json['department_id'] as String?,
    jobTitle: json['job_title'] as String?,
    locale: json['locale'] as String?,
  );

  final String id;
  final String fullName;
  final String phone;

  /// 'admin', 'manager' or 'employee'.
  final String role;
  final String? departmentId;
  final String? jobTitle;
  final String? locale;

  bool get isAdmin => role == 'admin';
}
