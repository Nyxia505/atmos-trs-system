import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Display fonts for ATMOS TRS branding (onboarding, home greeting, auth, landing).
abstract final class AtmosBrandTypography {
  static const String displayFontFamily = 'Ananda Black';

  /// Body / UI font used across the tourist (user) side — matches ATMOS-TRS logo meaning.
  static const FontWeight mediumWeight = FontWeight.w500;

  /// Wordmark ink (ATMOS + hyphen) on light surfaces.
  static const Color wordmarkInk = Color(0xFF1F1F1F);

  /// TRS gradient stops — high-contrast brand orange.
  static const Color wordmarkTrsStart = Color(0xFFF97316);
  static const Color wordmarkTrsEnd = Color(0xFFFB923C);

  /// Custom ATMOS-TRS wordmark: geometric rounded sans (Plus Jakarta Sans).
  /// Inspired by clean minimalist branding — not a copy of any proprietary face.
  static TextStyle wordmarkAtmos({
    required Color color,
    double fontSize = 30,
    double letterSpacing = 1.05,
    double height = 1.0,
  }) {
    return GoogleFonts.plusJakartaSans(
      color: color,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// TRS segment — one step heavier than ATMOS for clear hierarchy.
  static TextStyle wordmarkTrs({
    required Color color,
    double fontSize = 30,
    double letterSpacing = 1.15,
    double height = 1.0,
  }) {
    return GoogleFonts.plusJakartaSans(
      color: color,
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  /// Hyphen between ATMOS and TRS (same family, balanced weight).
  static TextStyle wordmarkHyphen({
    required Color color,
    double fontSize = 30,
    double height = 1.0,
  }) {
    return GoogleFonts.plusJakartaSans(
      color: color,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
      height: height,
    );
  }

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

  /// Landing header app mark (`ATMOS-TRS`): Quicksand — rounded geometric sans.
  static TextStyle landingAppMark({
    required Color color,
    double fontSize = 34,
    double letterSpacing = 1.4,
    double height = 1.05,
  }) {
    return GoogleFonts.quicksand(
      color: color,
      fontSize: fontSize,
      fontWeight: FontWeight.w700,
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
