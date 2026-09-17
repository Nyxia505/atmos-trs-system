import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Visual tokens matching the Governor premium concept image.
abstract final class GovernorDashboardTokens {
  static const Color primary = Color(0xFFF97316);
  static const Color primarySecondary = Color(0xFFFB923C);
  static const Color primaryDark = Color(0xFFEA580C);
  static const Color background = Color(0xFFF8FAFC);
  static const Color card = Color(0xFFFFFFFF);
  static const Color border = Color(0xFFE5E7EB);
  static const Color success = Color(0xFF22C55E);
  static const Color danger = Color(0xFFEF4444);
  static const Color text = Color(0xFF0F172A);
  static const Color subtitle = Color(0xFF6B7280);
  static const Color mutedSurface = Color(0xFFF1F5F9);
  static const Color softOrange = Color(0xFFFFEDD5);
  /// Outer sidebar frame fallback (solid). Prefer [headerGradient].
  static const Color sidebarFrame = Color(0xFFF97316);

  /// Shared orange gradient used by dashboard header + sidebar outer frame.
  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFB923C), // lighter orange
      Color(0xFFF97316), // primary
      Color(0xFFEA580C), // primary dark
    ],
    stops: [0.0, 0.55, 1.0],
  );

  static const double radiusCard = 24;
  static const double radiusLg = 20;
  static const double radiusMd = 16;
  static const double radiusSm = 12;

  static const double sidebarExpanded = 268;
  static const double sidebarCollapsed = 72;

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.045),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.03),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];

  static List<BoxShadow> get cardShadowHover => [
        BoxShadow(
          color: primary.withValues(alpha: 0.14),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.05),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ];

  static LinearGradient get primaryGradient => const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0xFFFB923C), Color(0xFFF97316), Color(0xFFEA580C)],
      );

  static TextStyle heading({double size = 22, Color? color}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color ?? text,
        letterSpacing: -0.35,
        height: 1.15,
      );

  static TextStyle sectionTitle({double size = 15, Color? color}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w600,
        color: color ?? text,
        letterSpacing: -0.15,
      );

  static TextStyle body({double size = 14, Color? color}) => GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w400,
        color: color ?? subtitle,
        height: 1.35,
      );

  static TextStyle number({double size = 28, Color? color}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w800,
        color: color ?? text,
        letterSpacing: -0.7,
        height: 1.0,
      );

  static String greetingForNow([DateTime? now]) {
    final hour = (now ?? DateTime.now()).hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  static String greetingEmoji([DateTime? now]) {
    final hour = (now ?? DateTime.now()).hour;
    if (hour < 12) return '👋';
    if (hour < 17) return '☀️';
    return '🌙';
  }

  static const List<Color> categoryPalette = [
    Color(0xFFF97316),
    Color(0xFF60A5FA),
    Color(0xFF22C55E),
    Color(0xFFA855F7),
    Color(0xFF94A3B8),
  ];

  static const Color genderMale = Color(0xFFEF4444);
  static const Color genderFemale = Color(0xFF3B82F6);
  static const Color genderOther = Color(0xFF94A3B8);
  static const Color localVisitor = Color(0xFFF97316);
  static const Color foreignVisitor = Color(0xFF3B82F6);
}
