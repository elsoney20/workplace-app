import 'package:material_ui/material_ui.dart';

/// Single source of truth for the brand.
///
/// The app name and colors are not final yet. Change them here and the
/// whole app (window title, theme, logo, greetings) follows.
abstract final class BrandConfig {
  /// App name shown to English-speaking users.
  static const String appName = 'Workplace';

  /// App name shown to Arabic-speaking users.
  static const String appNameAr = 'مساحة العمل';

  /// Main brand color. The full Material color scheme is generated from it.
  static const Color primaryColor = Color(0xFF1F6FEB);

  /// Accent color for secondary actions, chips and highlights.
  static const Color secondaryColor = Color(0xFF0FA968);

  /// Path to the logo inside `assets/brand/`, or `null` to show a
  /// generated letter avatar until the real logo is ready.
  static const String? logoAsset = null;

  /// Returns the app name for the given language code.
  static String localizedAppName(Locale locale) =>
      locale.languageCode == 'ar' ? appNameAr : appName;
}
