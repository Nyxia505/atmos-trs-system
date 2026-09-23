import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sleek establishment dashboard visual tokens (orange accent, cool slate chrome).
abstract final class AeDashTokens {
  static const Color background = Color(0xFFF4F6F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color card = surface;
  static const Color sidebar = Color(0xFF0F172A);
  static const Color sidebarMuted = Color(0xFF1E293B);
  static const Color border = Color(0xFFE2E8F0);
  static const Color text = Color(0xFF0F172A);
  static const Color muted = Color(0xFF64748B);
  static const Color subtitle = muted;
  static const Color mutedSurface = Color(0xFFF1F5F9);
  static const Color accent = Color(0xFFF97316);
  static const Color softAccent = Color(0xFFFFF7ED);
  static const Color softOrange = softAccent;
  static const Color success = Color(0xFF16A34A);
  static const Color danger = Color(0xFFDC2626);
  static const Color info = Color(0xFF0284C7);
  static const Color chartSecondary = Color(0xFF6366F1);
  static const Color chartTertiary = Color(0xFF14B8A6);

  static const double radius = 14;
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 14;
  static const double radiusCard = 14;
  static const double sidebarExpanded = 248;
  static const double sidebarCollapsed = 72;

  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.04),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  static BoxDecoration cardDecoration({Color? color}) => BoxDecoration(
        color: color ?? surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
        boxShadow: cardShadow,
      );

  static TextStyle heading({double size = 20, Color? color}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color ?? text,
        letterSpacing: -0.3,
        height: 1.2,
      );

  static TextStyle section({double size = 13, Color? color}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w700,
        color: color ?? text,
        letterSpacing: -0.1,
      );

  static TextStyle sectionTitle({double size = 13, Color? color}) =>
      section(size: size, color: color);

  static TextStyle body({double size = 13, Color? color, FontWeight? weight}) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight ?? FontWeight.w500,
        color: color ?? muted,
        height: 1.35,
      );

  static TextStyle number({double size = 22, Color? color}) => GoogleFonts.inter(
        fontSize: size,
        fontWeight: FontWeight.w800,
        color: color ?? text,
        letterSpacing: -0.4,
        height: 1.1,
      );

  static String greetingForNow() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }
}
