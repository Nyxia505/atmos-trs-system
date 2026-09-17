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
    'Uploads',
  ];

  static String sloganForVisualStep(int visualStepIndex) {
    switch (visualStepIndex.clamp(0, 3)) {
      case 0:
        return 'Start Your Journey';
      case 1:
        return 'More Than Registration';
      case 2:
        return 'Discover More Together';
      default:
        return 'Almost There';
    }
  }
}

class TouristSignupHeroWaveClipper extends CustomClipper<Path> {
  const TouristSignupHeroWaveClipper();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..lineTo(0, h - 36)
      ..cubicTo(w * 0.2, h - 6, w * 0.4, h - 52, w * 0.58, h - 28)
      ..cubicTo(w * 0.75, h - 8, w * 0.9, h - 42, w, h - 18)
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

/// Compact logo + ATMOS-TRS + tagline (mock header brand row).
class TouristSignupBrandRow extends StatelessWidget {
  const TouristSignupBrandRow({super.key, this.onDark = true});

  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final titleColor = onDark ? Colors.white : TouristSignupChrome.textDark;
    final subColor = onDark
        ? Colors.white.withValues(alpha: 0.9)
        : TouristSignupChrome.textMuted;

    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const ClipOval(
            child: Padding(
              padding: EdgeInsets.all(4),
              child: TransparentLogo(
                width: 44,
                height: 44,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ATMOS-TRS',
                style: TextStyle(
                  color: titleColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Explore Misamis Occidental',
                style: TextStyle(
                  color: subColor,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
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

/// 4-step progress tracker matching the mock.
class TouristSignupProgressTracker extends StatelessWidget {
  const TouristSignupProgressTracker({
    super.key,
    required this.visualStepIndex,
    this.onDark = false,
  });

  final int visualStepIndex;
  final bool onDark;

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
          child: Stack(
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
              Row(
                children: List.generate(labels.length, (index) {
                  final completed = index < visualStepIndex;
                  final current = index == visualStepIndex;
                  return Expanded(
                    child: Center(
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
                  );
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(labels.length, (index) {
            final current = index == visualStepIndex;
            return Expanded(
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
                      : labelMuted,
                  decoration: current ? TextDecoration.underline : null,
                  decorationColor: TouristSignupChrome.heroOrange,
                  decorationThickness: 1.4,
                ),
              ),
            );
          }),
        ),
      ],
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
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        children: [
          SizedBox(
            height: 56,
            width: double.infinity,
            child: CustomPaint(painter: const TouristSignupFooterPainter()),
          ),
          TouristSignupScriptSlogan(
            text: 'Misamis Occidental',
            fontSize: 26,
            color: TouristSignupChrome.heroOrange.withValues(alpha: 0.85),
          ),
          const SizedBox(height: 4),
          Text(
            'A PROVINCE OF ENDLESS POSSIBILITIES.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: TouristSignupChrome.heroOrange.withValues(alpha: 0.75),
            ),
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
