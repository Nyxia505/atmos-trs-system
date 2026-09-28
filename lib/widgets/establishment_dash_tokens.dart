import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Sleek establishment dashboard visual tokens (orange accent, cool slate chrome).
abstract final class AeDashTokens {
  static const Color background = Color(0xFFF5F7FA);
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
  static const double radiusXl = 18;
  static const double sidebarExpanded = 240;
  static const double sidebarCollapsed = 76;

  static const Color secondary = Color(0xFFFB923C);
  static const Color cream = Color(0xFFFFF7ED);
  static const Color warning = Color(0xFFF59E0B);
  static const Color purple = Color(0xFF8B5CF6);
  static const Color blue = Color(0xFF3B82F6);
  static const Color slate = Color(0xFF64748B);
  static const Color softBorder = Color(0xFFEEF2F6);

  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: const Color(0xFF0F172A).withValues(alpha: 0.05),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ];

  static BoxDecoration panelDecoration({Color? color}) => BoxDecoration(
        color: color ?? surface,
        borderRadius: BorderRadius.circular(radiusXl),
        border: Border.all(color: softBorder),
        boxShadow: softShadow,
      );

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

  static const LinearGradient sidebarGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFB923C), Color(0xFFF97316), Color(0xFFEA580C)],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFFF97316), Color(0xFFEA580C), Color(0xFFC2410C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Dashboard banner: same palette as [sidebarRichGradient] so the left edge
  /// continues the sidebar's top color.
  static const LinearGradient bannerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFB923C), Color(0xFFF97316), Color(0xFFEA580C)],
    stops: [0.0, 0.45, 1.0],
  );

  /// Sidebar: warm top-left fading into burnt orange at the bottom.
  static const LinearGradient sidebarRichGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFB923C), Color(0xFFF97316), Color(0xFFEA580C), Color(0xFFC2410C)],
    stops: [0.0, 0.35, 0.75, 1.0],
  );

  static Widget iconChip(IconData icon, Color color, {double size = 34}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(radiusSm),
      ),
      child: Icon(icon, color: color, size: size * 0.53),
    );
  }
}

/// Section title with icon chip, optional hint and trailing action.
class AeSectionHeader extends StatelessWidget {
  const AeSectionHeader({
    super.key,
    required this.title,
    required this.icon,
    this.hint,
    this.color = AeDashTokens.accent,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final String? hint;
  final Color color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AeDashTokens.iconChip(icon, color, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AeDashTokens.section(size: 14)),
                if (hint != null && hint!.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(hint!, style: AeDashTokens.body(size: 11.5)),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Friendly empty state: icon bubble + message.
class AeEmptyState extends StatelessWidget {
  const AeEmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.boxed = true,
  });

  final String message;
  final IconData icon;
  final bool boxed;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: AeDashTokens.mutedSurface,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AeDashTokens.muted, size: 22),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AeDashTokens.body(size: 12.5),
          ),
        ],
      ),
    );
    if (!boxed) return Center(child: content);
    return Container(
      width: double.infinity,
      decoration: AeDashTokens.cardDecoration(),
      child: content,
    );
  }
}
