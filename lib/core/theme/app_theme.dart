import 'package:material_ui/material_ui.dart';

import '../config/brand_config.dart';

/// Games2Egypt look: dark by default (like the website), with a light
/// "daylight" version for people who prefer it.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ColorScheme _scheme(Brightness brightness) {
    if (brightness == Brightness.dark) {
      return const ColorScheme(
        brightness: Brightness.dark,
        primary: BrandConfig.primaryColor,
        onPrimary: BrandConfig.background,
        primaryContainer: Color(0xFF2A3318),
        onPrimaryContainer: BrandConfig.primaryLight,
        secondary: BrandConfig.secondaryColor,
        onSecondary: BrandConfig.background,
        secondaryContainer: Color(0xFF3A2D12),
        onSecondaryContainer: Color(0xFFF8D489),
        tertiary: Color(0xFF3D7BFF),
        onTertiary: Colors.white,
        tertiaryContainer: Color(0xFF16264A),
        onTertiaryContainer: Color(0xFFB9CCFF),
        error: BrandConfig.danger,
        onError: Colors.white,
        surface: BrandConfig.surface,
        onSurface: BrandConfig.text,
        onSurfaceVariant: BrandConfig.mutedText,
        surfaceContainerLowest: BrandConfig.background,
        surfaceContainerLow: Color(0xFF111418),
        surfaceContainer: BrandConfig.surface,
        surfaceContainerHigh: BrandConfig.surfaceHigh,
        surfaceContainerHighest: Color(0xFF1F2329),
        outline: Color(0xFF3A4048),
        outlineVariant: BrandConfig.line,
        inverseSurface: BrandConfig.text,
        onInverseSurface: BrandConfig.background,
        inversePrimary: Color(0xFF5F7A22),
      );
    }
    return const ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF5F7A22),
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFE6EED2),
      onPrimaryContainer: Color(0xFF2E3B10),
      secondary: Color(0xFFB7791F),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFFBEBCB),
      onSecondaryContainer: Color(0xFF4A3008),
      tertiary: Color(0xFF2F5FD0),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFDDE6FF),
      onTertiaryContainer: Color(0xFF0F2A6B),
      error: Color(0xFFD12E3B),
      onError: Colors.white,
      surface: Colors.white,
      onSurface: Color(0xFF14171C),
      onSurfaceVariant: Color(0xFF5B6168),
      surfaceContainerLowest: Color(0xFFF3F5EE),
      surfaceContainerLow: Color(0xFFF7F8F4),
      surfaceContainer: Colors.white,
      surfaceContainerHigh: Color(0xFFF1F3EC),
      surfaceContainerHighest: Color(0xFFE9ECE3),
      outline: Color(0xFFC4CAB8),
      outlineVariant: Color(0xFFE1E6D6),
      inverseSurface: Color(0xFF14171C),
      onInverseSurface: Colors.white,
      inversePrimary: BrandConfig.primaryLight,
    );
  }

  static ThemeData _build(Brightness brightness) {
    final scheme = _scheme(brightness);
    final dark = brightness == Brightness.dark;
    final radius12 = BorderRadius.circular(12);
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: BrandConfig.fontFamily,
      fontFamilyFallback: const [BrandConfig.latinFontFamily],
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surfaceContainerLowest,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      textTheme: base.textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surfaceContainerLowest,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: BrandConfig.fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 44),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: radius12),
          textStyle: const TextStyle(
            fontFamily: BrandConfig.fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 44),
          shape: RoundedRectangleBorder(borderRadius: radius12),
          side: BorderSide(color: scheme.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: radius12),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: radius12,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: radius12,
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius12,
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: dark
            ? const Color(0x1F95AB52)
            : scheme.primaryContainer,
        labelStyle: TextStyle(
          color: dark ? BrandConfig.primaryLight : scheme.primary,
          fontFamily: BrandConfig.fontFamily,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide.none,
        shape: const StadiumBorder(),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius12,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: TextStyle(
          color: scheme.onSurface,
          fontFamily: BrandConfig.fontFamily,
        ),
        shape: RoundedRectangleBorder(borderRadius: radius12),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: scheme.primary,
        labelColor: dark ? BrandConfig.primaryLight : scheme.primary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        dividerColor: scheme.outlineVariant,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.primary,
        textColor: scheme.onPrimary,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        textStyle: TextStyle(color: scheme.onSurface, fontSize: 13),
      ),
    );
  }
}
