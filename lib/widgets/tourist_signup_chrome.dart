import 'package:atmos_trs_system/widgets/trip_plan_auth_brand.dart';
import 'package:flutter/material.dart';
import 'package:atmos_trs_system/utils/logo_utils.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared visual chrome for tourist signup — matches the registration mock.
abstract final class TouristSignupChrome {
  static const Color heroOrange = Color(0xFFF97316);
  static const Color peachBanner = Color(0xFFFFF1E6);
  static const Color softPeachBg = Color(0xFFFFF8F1);
  static const Color textDark = Color(0xFF1F2937);
  static const Color textMuted = Color(0xFF9CA3AF);
  static const Color inputFill = Color(0xFFF3F4F6);
  static const Color inputBorder = Color(0xFFE5E7EB);
  static const Color requiredRed = Color(0xFFEF4444);
  static const String heroAsset = 'assets/images/login_hero_bg.png';

  static const List<String> progressLabels = [
    'Personal Details',
    'Personal Info',
    'Contact & Address',
  ];
}

class TouristSignupHeroWaveClipper extends CustomClipper<Path> {
  const TouristSignupHeroWaveClipper();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..lineTo(0, h - 22)
      ..quadraticBezierTo(w * 0.5, h + 6, w, h - 22)
      ..lineTo(w, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class TouristSignupFooterPainter extends CustomPainter {
  const TouristSignupFooterPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final line = Paint()
      ..color = TouristSignupChrome.heroOrange.withValues(alpha: 0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(Offset(w * 0.78, h * 0.28), 6, line);
    final mountains = Path()
      ..moveTo(w * 0.42, h * 0.85)
      ..lineTo(w * 0.55, h * 0.35)
      ..lineTo(w * 0.62, h * 0.62)
      ..lineTo(w * 0.72, h * 0.22)
      ..lineTo(w * 0.88, h * 0.78)
      ..lineTo(w * 0.98, h * 0.48);
    canvas.drawPath(mountains, line);
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(w * 0.68, h * 0.88),
        width: 70,
        height: 12,
      ),
      0.1,
      2.9,
      false,
      line,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Original ATMOS TRS logo on a white circle — same treatment as login.
class TouristSignupBrandRow extends StatelessWidget {
  const TouristSignupBrandRow({
    super.key,
    this.onDark = true,
    this.tripPlanner = false,
    this.height = 72,
  });

  final bool onDark;
  final bool tripPlanner;
  final double height;

  static const double _logoInset = 6;

  @override
  Widget build(BuildContext context) {
    if (tripPlanner) {
      return TripPlanAuthBrand(compact: true, onDark: onDark);
    }

    final inner = height - (_logoInset * 2);
    return Center(
      child: Container(
        width: height,
        height: height,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipOval(
          child: Padding(
            padding: const EdgeInsets.all(_logoInset),
            child: TransparentLogo(
              width: inner,
              height: inner,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

class TouristSignupScriptSlogan extends StatelessWidget {
  const TouristSignupScriptSlogan({
    super.key,
    required this.text,
    this.color = TouristSignupChrome.heroOrange,
    this.fontSize = 22,
  });

  final String text;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.right,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.greatVibes(
        fontSize: fontSize,
        height: 1.05,
        color: color,
        fontWeight: FontWeight.w400,
      ),
    );
  }
}

/// 3-step progress tracker matching the mock.
class TouristSignupProgressTracker extends StatelessWidget {
  const TouristSignupProgressTracker({
    super.key,
    required this.visualStepIndex,
    this.highestReachedIndex,
    this.onStepSelected,
    this.onDark = false,
  });

  final int visualStepIndex;

  /// Furthest visual step the user has opened (inclusive).
  /// Defaults to [visualStepIndex] so later steps stay locked until visited.
  final int? highestReachedIndex;
  final ValueChanged<int>? onStepSelected;
  final bool onDark;

  int get _highestReached => highestReachedIndex ?? visualStepIndex;

  bool _canOpen(int index) =>
      onStepSelected != null &&
      index <= _highestReached &&
      index != visualStepIndex;

  @override
  Widget build(BuildContext context) {
    final labels = TouristSignupChrome.progressLabels;
    final muted = onDark
        ? Colors.white.withValues(alpha: 0.45)
        : const Color(0xFFD1D5DB);
    final labelMuted = onDark
        ? Colors.white.withValues(alpha: 0.55)
        : TouristSignupChrome.textMuted;

    return Column(
      children: [
        SizedBox(
          height: 36,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final stepW = constraints.maxWidth / labels.length;
              final start = stepW / 2;
              final end = stepW * visualStepIndex + stepW / 2;
              return Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: Center(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 28),
                    color: muted,
                  ),
                ),
              ),
              if (visualStepIndex > 0)
                Positioned(
                  left: start,
                  width: (end - start).clamp(0.0, constraints.maxWidth).toDouble(),
                  top: 17,
                  child: Container(
                    height: 2,
                    color: TouristSignupChrome.heroOrange,
                  ),
                ),
              Row(
                children: List.generate(labels.length, (index) {
                  final current = index == visualStepIndex;
                  final completed = !current && index <= _highestReached;
                  return Expanded(
                    child: Center(
                      child: _ProgressStepHitTarget(
                        enabled: _canOpen(index),
                        semanticLabel: labels[index],
                        keyName: 'signup-progress-step-$index',
                        onTap: () => onStepSelected?.call(index),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: completed || current
                                ? TouristSignupChrome.heroOrange
                                : (onDark
                                    ? Colors.white.withValues(alpha: 0.12)
                                    : Colors.white),
                            border: Border.all(
                              color: completed || current
                                  ? TouristSignupChrome.heroOrange
                                  : muted,
                              width: 1.6,
                            ),
                          ),
                          child: Center(
                            child: completed
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  )
                                : Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: current
                                          ? Colors.white
                                          : (onDark
                                              ? Colors.white.withValues(
                                                  alpha: 0.7,
                                                )
                                              : TouristSignupChrome.textMuted),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(labels.length, (index) {
            final current = index == visualStepIndex;
            return Expanded(
              child: _ProgressStepHitTarget(
                enabled: _canOpen(index),
                semanticLabel: labels[index],
                keyName: 'signup-progress-label-$index',
                onTap: () => onStepSelected?.call(index),
                child: Text(
                  labels[index],
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.15,
                    fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                    color: current
                        ? TouristSignupChrome.heroOrange
                        : (index < visualStepIndex
                            ? TouristSignupChrome.heroOrange
                            : labelMuted),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _ProgressStepHitTarget extends StatelessWidget {
  const _ProgressStepHitTarget({
    required this.enabled,
    required this.semanticLabel,
    required this.keyName,
    required this.onTap,
    required this.child,
  });

  final bool enabled;
  final String semanticLabel;
  final String keyName;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: enabled,
      enabled: enabled,
      label: semanticLabel,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          key: ValueKey(keyName),
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: child,
        ),
      ),
    );
  }
}

class TouristSignupInfoBanner extends StatelessWidget {
  const TouristSignupInfoBanner({
    super.key,
    required this.icon,
    required this.child,
  });

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: TouristSignupChrome.peachBanner,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: TouristSignupChrome.heroOrange,
            ),
            child: Icon(icon, size: 15, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class TouristSignupSectionHeader extends StatelessWidget {
  const TouristSignupSectionHeader({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    this.onDark = false,
  });

  final String title;
  final String description;
  final IconData icon;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: TouristSignupChrome.heroOrange.withValues(alpha: 0.12),
            ),
            child: Icon(icon, color: TouristSignupChrome.heroOrange, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: onDark ? Colors.white : TouristSignupChrome.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: onDark
                        ? Colors.white.withValues(alpha: 0.75)
                        : TouristSignupChrome.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TouristSignupFooterMotif extends StatelessWidget {
  const TouristSignupFooterMotif({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        children: [
          SizedBox(
            height: 28,
            width: double.infinity,
            child: CustomPaint(painter: const TouristSignupFooterPainter()),
          ),
          TouristSignupScriptSlogan(
            text: 'Misamis Occidental',
            fontSize: 20,
            color: TouristSignupChrome.heroOrange.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }
}

class TouristSignupExploreStrip extends StatelessWidget {
  const TouristSignupExploreStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 72,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              TouristSignupChrome.heroAsset,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (_, __, ___) => const ColoredBox(
                color: Color(0xFFFFE7D1),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    TouristSignupChrome.heroOrange.withValues(alpha: 0.55),
                    TouristSignupChrome.heroOrange.withValues(alpha: 0.35),
                  ],
                ),
              ),
            ),
            const Center(
              child: TouristSignupScriptSlogan(
                text: 'Explore Experience Belong.',
                color: Colors.white,
                fontSize: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
