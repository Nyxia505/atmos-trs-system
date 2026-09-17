import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme_controller.dart';
import 'package:atmos_trs_system/config/atmos_theme_extension.dart';
import 'package:google_fonts/google_fonts.dart';

/// ATMOS TRS theme — accent color and light/dark mode follow [AppThemeController].
class AppTheme {
  AppTheme._();

  static AppThemeController get _c => AppThemeController.instance;

  /// Fixed Asenso orange for landing, login, signup (matches provincial branding).
  static const Color brandOrange = Color(0xFFF97316);
  static const Color brandOrangeLight = Color(0xFFFB923C);
  static const Color brandOrangeDark = Color(0xFFEA580C);

  /// Runtime accent from Settings → Color.
  static Color get primary => _c.primary;
  static Color get primaryLight => _c.primaryLight;
  static Color get primaryDark => _c.primaryDark;
  static Color get onPrimary => _c.onPrimary;

  static bool get isDark => _c.isDarkMode;

  static Color get scaffoldBackground =>
      isDark ? const Color(0xFF0F172A) : const Color(0xFFFFFFFF);

  static Color get pageBackground =>
      isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

  static Color get cardBackground =>
      isDark ? const Color(0xFF1E293B) : Colors.white;

  static Color get textPrimary =>
      isDark ? const Color(0xFFF1F5F9) : const Color(0xFF111827);

  static Color get unselectedMuted =>
      isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);

  static Color get gradientOrange => primary;
  static const Color gradientDarkBlue = Color(0xFF0A1628);

  static double get mapMarkerHue {
    final hsv = HSVColor.fromColor(primary);
    return hsv.hue;
  }

  static double get brandMapMarkerHue {
    final hsv = HSVColor.fromColor(brandOrange);
    return hsv.hue;
  }

  static ThemeData get asensoTheme => buildTheme(primary, brightness: Brightness.light);

  static ThemeData get asensoDarkTheme =>
      buildTheme(primary, brightness: Brightness.dark);

  static ThemeData get currentTheme =>
      isDark ? asensoDarkTheme : asensoTheme;

  static ThemeData buildTheme(Color seed, {required Brightness brightness}) {
    final isDarkTheme = brightness == Brightness.dark;
    final primaryLight = Color.lerp(seed, Colors.white, 0.22)!;
    final primaryDark = Color.lerp(seed, Colors.black, 0.12)!;
    final onPrimaryColor = seed.computeLuminance() > 0.55
        ? const Color(0xFF111827)
        : Colors.white;

    final surface = isDarkTheme ? const Color(0xFF1E293B) : Colors.white;
    final scaffold = isDarkTheme ? const Color(0xFF0F172A) : const Color(0xFFFFFFFF);
    final onSurface = isDarkTheme ? const Color(0xFFF1F5F9) : const Color(0xFF111827);
    final muted = isDarkTheme ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);
    final surfaceHigh =
        isDarkTheme ? const Color(0xFF334155) : const Color(0xFFF9FAFB);
    final inputFill = isDarkTheme ? const Color(0xFF1E293B) : Colors.white;

    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      primary: seed,
      onPrimary: onPrimaryColor,
      secondary: Color.lerp(seed, const Color(0xFF0A1628), 0.35)!,
      onSecondary: Colors.white,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: surfaceHigh,
      outline: muted.withValues(alpha: 0.45),
    );

    final baseText = ThemeData(
      useMaterial3: true,
      brightness: brightness,
    ).textTheme;
    final montserrat = GoogleFonts.montserratTextTheme(baseText).apply(
      bodyColor: onSurface,
      displayColor: onSurface,
    );
    TextStyle mediumOf(TextStyle? style) =>
        (style ?? const TextStyle()).copyWith(fontWeight: FontWeight.w500);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: GoogleFonts.montserrat().fontFamily,
      textTheme: montserrat.copyWith(
        bodyLarge: mediumOf(montserrat.bodyLarge),
        bodyMedium: mediumOf(montserrat.bodyMedium),
        bodySmall: mediumOf(montserrat.bodySmall),
        titleLarge: mediumOf(montserrat.titleLarge),
        titleMedium: mediumOf(montserrat.titleMedium),
        titleSmall: mediumOf(montserrat.titleSmall),
        labelLarge: mediumOf(montserrat.labelLarge),
        labelMedium: mediumOf(montserrat.labelMedium),
        labelSmall: mediumOf(montserrat.labelSmall),
      ),
      extensions: [
        AtmosThemeExtension(
          primaryLight: primaryLight,
          primaryDark: primaryDark,
          onPrimary: onPrimaryColor,
        ),
      ],
      scaffoldBackgroundColor: scaffold,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: seed,
        foregroundColor: onPrimaryColor,
        iconTheme: IconThemeData(color: onPrimaryColor),
        titleTextStyle: GoogleFonts.montserrat(
          color: onPrimaryColor,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: isDarkTheme ? 0 : 2,
        shadowColor: Colors.black38,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: muted.withValues(alpha: isDarkTheme ? 0.35 : 0.25),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: seed, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: TextStyle(color: muted),
        hintStyle: TextStyle(color: muted.withValues(alpha: 0.85)),
        prefixIconColor: muted,
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
        backgroundColor: isDarkTheme ? const Color(0xFF1E293B) : Colors.white,
        selectedItemColor: seed,
        unselectedItemColor: isDarkTheme ? const Color(0xFF64748B) : const Color(0xFF9CA3AF),
        type: BottomNavigationBarType.fixed,
      ),
      dividerTheme: DividerThemeData(
        color: muted.withValues(alpha: 0.25),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        textStyle: TextStyle(color: onSurface),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        titleTextStyle: GoogleFonts.montserrat(
          color: onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: GoogleFonts.montserrat(
          color: muted,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceHigh,
        selectedColor: seed,
        labelStyle: TextStyle(color: onSurface),
        secondaryLabelStyle: TextStyle(color: muted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      iconTheme: IconThemeData(color: muted, size: 24),
      primaryIconTheme: IconThemeData(color: seed, size: 24),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDarkTheme ? const Color(0xFF334155) : const Color(0xFF111827),
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        actionTextColor: primaryLight,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: seed,
        circularTrackColor: seed.withValues(alpha: 0.15),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: seed,
        foregroundColor: onPrimaryColor,
      ),
      listTileTheme: ListTileThemeData(
        textColor: onSurface,
        iconColor: muted,
      ),
    );
  }
}
