import 'package:flutter/material.dart';

/// Display fonts for ATMOS TRS branding (onboarding, home greeting, auth, landing).
abstract final class AtmosBrandTypography {
  static const String displayFontFamily = 'Ananda Black';

  /// App name lines: "ATMOS TRS", user first name, etc.
  static TextStyle displayTitle({
    required Color color,
    double fontSize = 36,
    FontWeight fontWeight = FontWeight.bold,
    double letterSpacing = 0.6,
    double height = 1.05,
  }) {
    return TextStyle(
      fontFamily: displayFontFamily,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// Large hero lines on photo/video backgrounds.
  static TextStyle heroHeadline({
    required Color color,
    double fontSize = 44,
    FontWeight fontWeight = FontWeight.bold,
    double height = 1.12,
    double letterSpacing = 0.4,
    List<Shadow>? shadows,
  }) {
    return TextStyle(
      fontFamily: displayFontFamily,
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
      shadows: shadows,
    );
  }
}
