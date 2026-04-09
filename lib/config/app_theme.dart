import 'package:flutter/material.dart';

/// ATMOS TRS (Asenso Tourismo Misamis Occidental Smart Tourist Registration System) theme.
/// Primary orange #F97316; gradient orange to dark blue; modern soft UI.
class AppTheme {
  AppTheme._();

  // --- ASENSO MISAMIS OCCIDENTAL Orange palette ---
  static const Color primary = Color(0xFFF97316); // orange-500
  static const Color primaryLight = Color(0xFFFB923C); // orange-400
  static const Color primaryDark = Color(0xFFEA580C); // orange-600

  // Global light theme colors (white + orange, same feel as login screen)
  static const Color scaffoldBackground = Color(0xFFFFF7ED); // warm cream
  static const Color cardBackground = Colors.white;
  static const Color unselectedMuted = Color(0xFF6B7280); // gray-500

  /// Gradient: orange to dark blue (for home background).
  static const Color gradientOrange = Color(0xFFF97316);
  static const Color gradientDarkBlue = Color(0xFF0A1628);

  /// For map markers: orange hue (0 = red, 30 = orange).
  static const double mapMarkerHue = 30.0;

  static ThemeData get asensoTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: primary,
        onPrimary: Colors.white,
        surface: cardBackground,
        onSurface: const Color(0xFF111827), // near-black text
        surfaceContainerHighest: cardBackground,
        outline: unselectedMuted.withOpacity(0.4),
        background: scaffoldBackground,
        onBackground: const Color(0xFF111827),
      ),
      scaffoldBackgroundColor: scaffoldBackground,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: primary,
        foregroundColor: Colors.white,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle: TextStyle(color: unselectedMuted),
        hintStyle: TextStyle(color: unselectedMuted.withOpacity(0.8)),
        prefixIconColor: unselectedMuted,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 2,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 1,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: primary),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary.withOpacity(0.7)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primary,
        unselectedItemColor: Color(0xFF9CA3AF), // gray-400
        type: BottomNavigationBarType.fixed,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF3F4F6), // gray-100
        selectedColor: primary,
        labelStyle: const TextStyle(color: Color(0xFF111827)),
        secondaryLabelStyle: TextStyle(color: unselectedMuted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      iconTheme: const IconThemeData(color: Color(0xFF6B7280), size: 24),
      primaryIconTheme: const IconThemeData(color: primary, size: 24),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF111827),
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        actionTextColor: primary,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardBackground,
        titleTextStyle: const TextStyle(
          color: Color(0xFF111827),
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(color: unselectedMuted, fontSize: 15),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primary,
        circularTrackColor: Color(0xFF1E3A5C),
      ),
    );
  }
}
