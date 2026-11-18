import 'package:material_ui/material_ui.dart';

/// Single source of truth for the brand (Games2Egypt).
///
/// Colors and fonts are taken from games2egypt.com so the app feels like part
/// of the same company. Change them here and the whole app follows.
abstract final class BrandConfig {
  /// App name shown to English-speaking users.
  static const String appName = 'G2E Workplace';

  /// App name shown to Arabic-speaking users.
  static const String appNameAr = 'مساحة G2E';

  /// Games2Egypt green: buttons, active items, links.
  static const Color primaryColor = Color(0xFF95AB52);

  /// Lighter green for text and icons on dark backgrounds.
  static const Color primaryLight = Color(0xFFBCD767);

  /// Games2Egypt gold: highlights and badges.
  static const Color secondaryColor = Color(0xFFF4B63D);

  // Dark surfaces from the website.
  static const Color background = Color(0xFF0B0D10);
  static const Color surface = Color(0xFF14171C);
  static const Color surfaceHigh = Color(0xFF1A1D22);
  static const Color line = Color(0xFF23272E);
  static const Color text = Color(0xFFEEF0F3);
  static const Color mutedText = Color(0xFF9AA1A9);
  static const Color danger = Color(0xFFFF4D5A);
  static const Color online = Color(0xFF7BE8A8);

  /// Arabic + main font, and the font for Latin numbers / names.
  static const String fontFamily = 'Tajawal';
  static const String latinFontFamily = 'Poppins';

  /// The round "2" mark of Games2Egypt.
  // Nullable on purpose: set to null to fall back to a letter avatar.
  // ignore: unnecessary_nullable_for_final_variable_declarations
  static const String? logoAsset = 'assets/brand/g2e_mark.png';

  /// Returns the app name for the given language code.
  static String localizedAppName(Locale locale) =>
      locale.languageCode == 'ar' ? appNameAr : appName;
}
