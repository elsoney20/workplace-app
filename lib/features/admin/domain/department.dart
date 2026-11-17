import 'package:material_ui/material_ui.dart';

class Department {
  const Department({
    required this.id,
    required this.nameAr,
    required this.nameEn,
  });

  factory Department.fromJson(Map<String, dynamic> json) => Department(
    id: json['id'] as String,
    nameAr: json['name_ar'] as String,
    nameEn: json['name_en'] as String,
  );

  final String id;
  final String nameAr;
  final String nameEn;

  String localizedName(Locale locale) =>
      locale.languageCode == 'ar' ? nameAr : nameEn;
}
