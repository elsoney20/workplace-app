import 'package:material_ui/material_ui.dart';

class Department {
  const Department({
    required this.id,
    required this.nameAr,
    required this.nameEn,
    this.managerId,
  });

  factory Department.fromJson(Map<String, dynamic> json) => Department(
    id: json['id'] as String,
    nameAr: json['name_ar'] as String,
    nameEn: json['name_en'] as String,
    managerId: json['manager_id'] as String?,
  );

  final String id;
  final String nameAr;
  final String nameEn;

  /// The manager moderates the department's group.
  final String? managerId;

  String localizedName(Locale locale) =>
      locale.languageCode == 'ar' ? nameAr : nameEn;
}
