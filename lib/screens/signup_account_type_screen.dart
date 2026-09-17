import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/widgets/web_glass_auth_scaffold.dart';
import 'package:google_fonts/google_fonts.dart';

/// Chooses Tourist, LGU, or Tourism Establishment before continuing signup.
class SignupAccountTypeScreen extends StatelessWidget {
  const SignupAccountTypeScreen({super.key});

  static const Color _heroOrange = Color(0xFFF97316);
  static const Color _textDark = Color(0xFF1F2937);
  static const Color _textMuted = Color(0xFF6B7280);

  static const _options = <_SignupAccountOption>[
    _SignupAccountOption(
      title: 'Tourist',
      subtitle: 'Register for travel & QR check-in',
      icon: Icons.luggage_rounded,
      route: '/signup-tourist',
      watermark: _AccountWatermark.tourist,
    ),
    _SignupAccountOption(
      title: 'LGU',
      subtitle: 'Local government tourism office',
      icon: Icons.account_balance_rounded,
      route: '/signup-lgu',
      watermark: _AccountWatermark.lgu,
    ),
    _SignupAccountOption(
      title: 'Tourism Establishment',
      subtitle: 'Hotel, resort, restaurant, attraction & more',
      icon: Icons.storefront_rounded,
      route: '/signup-establishment',
      watermark: _AccountWatermark.establishment,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = kIsWeb &&
        MediaQuery.sizeOf(context).width >= kWebGlassAuthBreakpoint;

    if (wide) {
      return _buildDesktopGlass(context);
    }
    return _buildMobile(context);
  }

  Widget _buildDesktopGlass(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: WebGlassAuthScaffold(
        maxWidth: 520,
        child: WebGlassAuthCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: WebGlassBackButton(
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Create an account',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Select your account type to continue',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(height: 28),
                for (final option in _options) ...[
                  _AccountTypeCard(
                    option: option,
                    glass: true,
                    onTap: () => Navigator.pushNamed(context, option.route),
                  ),
                  const SizedBox(height: 14),
                ],
                TextButton(
                  onPressed: () =>
                      Navigator.pushReplacementNamed(context, '/login'),
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontWeight: FontWeight.w700,
                      ),
                      children: const [
                        TextSpan(text: 'Already have an account? '),
                        TextSpan(
                          text: 'Log in',
                          style: TextStyle(
                            color: AppTheme.brandOrange,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobile(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F1),
      body: Column(
        children: [
          // Orange header with topo pattern
          SizedBox(
            width: double.infinity,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(color: _heroOrange),
                ),
                Positioned.fill(
                  child: CustomPaint(painter: const _TopoPatternPainter()),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(12, topPad + 6, 16, 18),
                  child: Row(
                    children: [
                      Material(
                        color: Colors.white.withValues(alpha: 0.22),
                        shape: const CircleBorder(),
                        child: IconButton(
                          icon: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          onPressed: () => Navigator.pop(context),
                          tooltip: 'Back',
                        ),
                      ),
                      const Expanded(
                        child: Text(
                          'Sign up',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 88,
                        child: Text(
                          'Explore.\nExperience.\nBelong.',
                          textAlign: TextAlign.right,
                          style: GoogleFonts.greatVibes(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.05,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                // Soft peach gradient body
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFFFFBF7),
                          Color(0xFFFFF8F1),
                          Color(0xFFFFF1E6),
                        ],
                      ),
                    ),
                  ),
                ),
                // Flight path decoration (top-right)
                Positioned(
                  top: 8,
                  right: 12,
                  child: CustomPaint(
                    size: const Size(120, 70),
                    painter: const _FlightPathMiniPainter(),
                  ),
                ),
                // Coastal sunset footer
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: SizedBox(
                    height: 168 + bottomPad,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CustomPaint(
                          painter: const _CoastalSunsetPainter(),
                        ),
                        Positioned(
                          left: 18,
                          bottom: 18 + bottomPad,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Misamis Occidental',
                                style: GoogleFonts.greatVibes(
                                  color: Colors.white,
                                  fontSize: 26,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'A PROVINCE OF ENDLESS POSSIBILITIES',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  fontSize: 9,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.7,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    22,
                    22,
                    22,
                    180 + bottomPad,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 3.5,
                        decoration: BoxDecoration(
                          color: _heroOrange,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text.rich(
                        TextSpan(
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: _textDark,
                            height: 1.15,
                            letterSpacing: -0.4,
                          ),
                          children: const [
                            TextSpan(text: 'Create an '),
                            TextSpan(
                              text: 'account',
                              style: TextStyle(color: _heroOrange),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Select your account type to continue',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: _textMuted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'ONE PLATFORM. A BRIGHTER MISAMIS OCCIDENTAL.',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                          color: _textMuted.withValues(alpha: 0.75),
                        ),
                      ),
                      const SizedBox(height: 26),
                      for (final option in _options) ...[
                        _AccountTypeCard(
                          option: option,
                          glass: false,
                          onTap: () =>
                              Navigator.pushNamed(context, option.route),
                        ),
                        const SizedBox(height: 14),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: GestureDetector(
                              onTap: () => Navigator.pushReplacementNamed(
                                context,
                                '/login',
                              ),
                              child: Text.rich(
                                TextSpan(
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    color: _textMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  children: const [
                                    TextSpan(text: 'Already have an account? '),
                                    TextSpan(
                                      text: 'Log in',
                                      style: TextStyle(
                                        color: _heroOrange,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                        ],
                      ),
                    ],
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

enum _AccountWatermark { tourist, lgu, establishment }

class _SignupAccountOption {
  const _SignupAccountOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
    required this.watermark,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
  final _AccountWatermark watermark;
}

class _AccountTypeCard extends StatelessWidget {
  const _AccountTypeCard({
    required this.option,
    required this.glass,
    required this.onTap,
  });

  final _SignupAccountOption option;
  final bool glass;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (glass) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.brandOrange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(option.icon, color: AppTheme.brandOrange),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          option.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          option.subtitle,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: Colors.white70),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                Positioned(
                  right: 28,
                  top: 8,
                  bottom: 8,
                  width: 72,
                  child: CustomPaint(
                    painter: _WatermarkPainter(option.watermark),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE8D6),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          option.icon,
                          color: const Color(0xFFF97316),
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              option.title,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              option.subtitle,
                              style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.3,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFFF97316),
                        size: 26,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopoPatternPainter extends CustomPainter {
  const _TopoPatternPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    for (var i = 0; i < 7; i++) {
      final y = size.height * (0.18 + i * 0.12);
      final path = Path()..moveTo(0, y);
      for (var x = 0.0; x <= size.width; x += 18) {
        path.lineTo(
          x,
          y + math.sin((x / size.width) * math.pi * 3 + i) * 5,
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FlightPathMiniPainter extends CustomPainter {
  const _FlightPathMiniPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final dash = Paint()
      ..color = const Color(0xFFF97316).withValues(alpha: 0.28)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path()
      ..moveTo(8, size.height * 0.55)
      ..quadraticBezierTo(
        size.width * 0.4,
        size.height * 0.05,
        size.width * 0.78,
        size.height * 0.42,
      );

    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        final next = (d + 3).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(d, next), dash);
        d += 7;
      }
    }

    // plane
    canvas.drawIconApprox(
      Offset(6, size.height * 0.5),
      const Color(0xFFF97316).withValues(alpha: 0.35),
    );
    // pin
    final pin = Offset(size.width * 0.86, size.height * 0.45);
    canvas.drawCircle(
      pin,
      3.5,
      Paint()..color = const Color(0xFFF97316).withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

extension on Canvas {
  void drawIconApprox(Offset tip, Color color) {
    save();
    translate(tip.dx, tip.dy);
    rotate(-0.5);
    final p = Path()
      ..moveTo(8, 0)
      ..lineTo(-6, 4)
      ..lineTo(-3, 1)
      ..lineTo(-9, -1)
      ..lineTo(-3, -1)
      ..lineTo(-5, -4)
      ..close();
    drawPath(p, Paint()..color = color);
    restore();
  }
}

class _WatermarkPainter extends CustomPainter {
  const _WatermarkPainter(this.kind);

  final _AccountWatermark kind;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFF97316).withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeJoin = StrokeJoin.round;

    switch (kind) {
      case _AccountWatermark.tourist:
        // mountains + palm
        final m = Path()
          ..moveTo(4, size.height * 0.85)
          ..lineTo(size.width * 0.35, size.height * 0.35)
          ..lineTo(size.width * 0.55, size.height * 0.7)
          ..lineTo(size.width * 0.85, size.height * 0.28)
          ..lineTo(size.width, size.height * 0.8);
        canvas.drawPath(m, paint);
        canvas.drawLine(
          Offset(size.width * 0.2, size.height * 0.9),
          Offset(size.width * 0.2, size.height * 0.45),
          paint,
        );
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(size.width * 0.2, size.height * 0.42),
            width: 28,
            height: 22,
          ),
          math.pi,
          math.pi,
          false,
          paint,
        );
        break;
      case _AccountWatermark.lgu:
        // building + flag
        final b = Path()
          ..moveTo(size.width * 0.2, size.height * 0.85)
          ..lineTo(size.width * 0.2, size.height * 0.4)
          ..lineTo(size.width * 0.5, size.height * 0.22)
          ..lineTo(size.width * 0.8, size.height * 0.4)
          ..lineTo(size.width * 0.8, size.height * 0.85)
          ..close();
        canvas.drawPath(b, paint);
        canvas.drawLine(
          Offset(size.width * 0.5, size.height * 0.22),
          Offset(size.width * 0.5, size.height * 0.08),
          paint,
        );
        canvas.drawLine(
          Offset(size.width * 0.5, size.height * 0.08),
          Offset(size.width * 0.72, size.height * 0.14),
          paint,
        );
        break;
      case _AccountWatermark.establishment:
        // resort house
        final h = Path()
          ..moveTo(size.width * 0.15, size.height * 0.7)
          ..lineTo(size.width * 0.5, size.height * 0.35)
          ..lineTo(size.width * 0.85, size.height * 0.7)
          ..lineTo(size.width * 0.85, size.height * 0.9)
          ..lineTo(size.width * 0.15, size.height * 0.9)
          ..close();
        canvas.drawPath(h, paint);
        canvas.drawLine(
          Offset(size.width * 0.75, size.height * 0.9),
          Offset(size.width * 0.75, size.height * 0.5),
          paint,
        );
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(size.width * 0.75, size.height * 0.45),
            width: 22,
            height: 18,
          ),
          math.pi * 1.1,
          math.pi * 0.9,
          false,
          paint,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CoastalSunsetPainter extends CustomPainter {
  const _CoastalSunsetPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // sky wash
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFFFE0C2).withValues(alpha: 0.0),
            const Color(0xFFFFB26B).withValues(alpha: 0.55),
            const Color(0xFFF97316),
          ],
          stops: const [0.0, 0.35, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // sun
    canvas.drawCircle(
      Offset(w * 0.78, h * 0.42),
      28,
      Paint()..color = const Color(0xFFFFEDD5).withValues(alpha: 0.9),
    );

    // far mountains
    final far = Path()
      ..moveTo(0, h * 0.58)
      ..lineTo(w * 0.18, h * 0.4)
      ..lineTo(w * 0.32, h * 0.52)
      ..lineTo(w * 0.48, h * 0.34)
      ..lineTo(w * 0.62, h * 0.5)
      ..lineTo(w * 0.8, h * 0.38)
      ..lineTo(w, h * 0.55)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(far, Paint()..color = const Color(0xFFEA580C));

    // near hills / water
    final near = Path()
      ..moveTo(0, h * 0.72)
      ..quadraticBezierTo(w * 0.3, h * 0.62, w * 0.55, h * 0.74)
      ..quadraticBezierTo(w * 0.78, h * 0.84, w, h * 0.7)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(near, Paint()..color = const Color(0xFFC2410C));

    // palm silhouettes (left)
    final palm = Paint()..color = const Color(0xFF9A3412);
    canvas.drawLine(
      Offset(w * 0.12, h * 0.88),
      Offset(w * 0.12, h * 0.48),
      palm..strokeWidth = 3,
    );
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(w * 0.12, h * 0.46),
        width: 46,
        height: 28,
      ),
      math.pi,
      math.pi,
      false,
      Paint()
        ..color = const Color(0xFF9A3412)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );

    // bottom orange wave
    final wave = Path()
      ..moveTo(0, h * 0.88)
      ..quadraticBezierTo(w * 0.25, h * 0.82, w * 0.5, h * 0.9)
      ..quadraticBezierTo(w * 0.75, h * 0.98, w, h * 0.86)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(wave, Paint()..color = const Color(0xFFF97316));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// LGU accounts are provisioned — not self-registered.
class LguSignupInfoScreen extends StatelessWidget {
  const LguSignupInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = kIsWeb &&
        MediaQuery.sizeOf(context).width >= kWebGlassAuthBreakpoint;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.account_balance_rounded,
          size: 56,
          color: wide ? Colors.white : AppTheme.brandOrange,
        ),
        const SizedBox(height: 20),
        Text(
          'LGU Tourism Office accounts',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: wide ? Colors.white : const Color(0xFF1C1917),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Municipal LGU tourism accounts are issued by the Provincial Tourism '
          'Office / system administrator. Self-registration is not available '
          'for this account type.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: wide
                ? Colors.white.withValues(alpha: 0.9)
                : const Color(0xFF57534E),
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => Navigator.pushReplacementNamed(context, '/login'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.brandOrange,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text('Go to Log in'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Back to account types',
            style: TextStyle(
              color: wide ? Colors.white : AppTheme.brandOrange,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );

    if (wide) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: WebGlassAuthScaffold(
          maxWidth: 480,
          child: WebGlassAuthCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
              child: content,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F1),
      appBar: AppBar(
        backgroundColor: AppTheme.brandOrange,
        foregroundColor: Colors.white,
        title: const Text('LGU signup'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: content,
        ),
      ),
    );
  }
}
