import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Display fonts for ATMOS TRS branding (onboarding, home greeting, auth, landing).
abstract final class AtmosBrandTypography {
  static const String displayFontFamily = 'Ananda Black';

  /// Body / UI font used across the tourist (user) side — matches ATMOS-TRS logo meaning.
  static const FontWeight mediumWeight = FontWeight.w500;

  /// Short app mark on auth screens (`ATMOS-TRS`): Montserrat bold for legibility.
  static TextStyle authAppMark({
    required Color color,
    double fontSize = 34,
    double letterSpacing = 2.0,
    double height = 1.05,
  }) {
    return GoogleFonts.montserrat(
      color: color,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// ATMOS-TRS-style meaning / full-name line under the logo (Montserrat Medium).
  static TextStyle meaningTagline({
    required Color color,
    double fontSize = 12,
    double letterSpacing = 0.6,
    double height = 1.4,
    FontWeight fontWeight = mediumWeight,
  }) {
    return GoogleFonts.montserrat(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

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
