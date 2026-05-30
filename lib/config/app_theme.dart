import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme_controller.dart';
import 'package:atmos_trs_system/config/atmos_theme_extension.dart';

/// ATMOS TRS theme — accent color follows [AppThemeController] (user Settings).
class AppTheme {
  AppTheme._();

  static AppThemeController get _c => AppThemeController.instance;

  /// Fixed Asenso orange for landing, login, signup (matches provincial branding).
  static const Color brandOrange = Color(0xFFF97316);
  static const Color brandOrangeLight = Color(0xFFFB923C);
  static const Color brandOrangeDark = Color(0xFFEA580C);

  /// Runtime accent from Settings → Theme color. Prefer [Theme.of](context).colorScheme.primary in widgets.
  static Color get primary => _c.primary;
  static Color get primaryLight => _c.primaryLight;
  static Color get primaryDark => _c.primaryDark;
  static Color get onPrimary => _c.onPrimary;

  static const Color scaffoldBackground = Color(0xFFFFFFFF);
  static const Color cardBackground = Colors.white;
  static const Color unselectedMuted = Color(0xFF6B7280);

  static Color get gradientOrange => primary;
  static const Color gradientDarkBlue = Color(0xFF0A1628);

  static double get mapMarkerHue {
    final hsv = HSVColor.fromColor(primary);
    return hsv.hue;
  }

  /// Google Maps marker hue for branded explore / municipality maps.
  static double get brandMapMarkerHue {
    final hsv = HSVColor.fromColor(brandOrange);
    return hsv.hue;
  }

  static ThemeData get asensoTheme => buildTheme(primary);

  static ThemeData buildTheme(Color seed) {
    final primaryLight = Color.lerp(seed, Colors.white, 0.22)!;
    final primaryDark = Color.lerp(seed, Colors.black, 0.12)!;
    final onPrimaryColor = seed.computeLuminance() > 0.55
        ? const Color(0xFF111827)
        : Colors.white;

    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
      primary: seed,
      onPrimary: onPrimaryColor,
      secondary: Color.lerp(seed, const Color(0xFF0A1628), 0.35)!,
      onSecondary: Colors.white,
      surface: cardBackground,
      onSurface: const Color(0xFF111827),
      surfaceContainerHighest: const Color(0xFFF9FAFB),
      outline: unselectedMuted.withValues(alpha: 0.45),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      extensions: [
        AtmosThemeExtension(
          primaryLight: primaryLight,
          primaryDark: primaryDark,
          onPrimary: onPrimaryColor,
        ),
      ],
      scaffoldBackgroundColor: scaffoldBackground,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: seed,
        foregroundColor: onPrimaryColor,
        iconTheme: IconThemeData(color: onPrimaryColor),
        titleTextStyle: TextStyle(
          color: onPrimaryColor,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBackground,
        elevation: 2,
        shadowColor: Colors.black38,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: seed, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: const TextStyle(color: unselectedMuted),
        hintStyle: TextStyle(color: unselectedMuted.withValues(alpha: 0.85)),
        prefixIconColor: unselectedMuted,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: onPrimaryColor,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 2,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: onPrimaryColor,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: seed),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: seed,
          side: BorderSide(color: seed.withValues(alpha: 0.75)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: seed,
        unselectedItemColor: const Color(0xFF9CA3AF),
        type: BottomNavigationBarType.fixed,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF3F4F6),
        selectedColor: seed,
        labelStyle: const TextStyle(color: Color(0xFF111827)),
        secondaryLabelStyle: const TextStyle(color: unselectedMuted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      iconTheme: const IconThemeData(color: Color(0xFF6B7280), size: 24),
      primaryIconTheme: IconThemeData(color: seed, size: 24),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF111827),
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        actionTextColor: primaryLight,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardBackground,
        titleTextStyle: const TextStyle(
          color: Color(0xFF111827),
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(color: unselectedMuted, fontSize: 15),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: seed,
        circularTrackColor: seed.withValues(alpha: 0.15),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: seed,
        foregroundColor: onPrimaryColor,
      ),
    );
  }
}
