import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// One existing How It Works step. Titles, descriptions, and icons stay as-is.
class LandingHowItWorksStep {
  const LandingHowItWorksStep({
    required this.number,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String number;
  final String title;
  final String description;
  final IconData icon;
}

/// Premium five-step section matching the approved How It Works design.
class LandingHowItWorksSection extends StatelessWidget {
  const LandingHowItWorksSection({super.key, required this.steps});

  final List<LandingHowItWorksStep> steps;

  static const Color page = Color(0xFFFFF8F3);
  static const Color orange = Color(0xFFF97316);
  static const Color navy = Color(0xFF1B2433);
  static const Color muted = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned.fill(
              child: CustomPaint(painter: _HowItWorksBackdropPainter()),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _HowItWorksHeading(),
                const SizedBox(height: 28),
                _HowItWorksGrid(width: constraints.maxWidth, steps: steps),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _HowItWorksHeading extends StatelessWidget {
  const _HowItWorksHeading();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = width < 720 ? 32.0 : (width < 1100 ? 40.0 : 46.0);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1E6),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFF8D7C0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.format_list_numbered_rounded,
                size: 14,
                color: LandingHowItWorksSection.orange,
              ),
              const SizedBox(width: 6),
              Text(
                '5 EASY STEPS',
                style: GoogleFonts.montserrat(
                  color: LandingHowItWorksSection.orange,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'How It '),
              TextSpan(
                text: 'Works',
                style: TextStyle(color: LandingHowItWorksSection.orange),
              ),
            ],
          ),
          textAlign: TextAlign.center,
          style: GoogleFonts.montserrat(
            color: LandingHowItWorksSection.navy,
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            height: 1.1,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Get started with ATMOS-TRS in 5 simple steps',
          textAlign: TextAlign.center,
          style: GoogleFonts.montserrat(
            color: LandingHowItWorksSection.muted,
            fontSize: width < 720 ? 14.5 : 16.5,
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _HowItWorksGrid extends StatelessWidget {
  const _HowItWorksGrid({required this.width, required this.steps});

  final double width;
  final List<LandingHowItWorksStep> steps;

  @override
  Widget build(BuildContext context) {
    const gap = 16.0;
    if (width >= 1100) {
      return _equalRow([
        for (final step in steps) Expanded(child: _StepCard(step: step)),
      ], gap);
    }
    if (width >= 700) {
      final columns = width >= 900 ? 3 : 2;
      return _wrapGrid(columns, gap);
    }
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(height: gap),
          Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _StepCard(step: steps[i]),
            ),
          ),
        ],
      ],
    );
  }

  Widget _wrapGrid(int columns, double gap) {
    final rows = <Widget>[];
    for (var i = 0; i < steps.length; i += columns) {
      final slice = steps.skip(i).take(columns).toList();
      rows.add(
        _equalRow([
          for (final step in slice) Expanded(child: _StepCard(step: step)),
          for (var pad = slice.length; pad < columns; pad++)
            const Expanded(child: SizedBox.shrink()),
        ], gap),
      );
      if (i + columns < steps.length) rows.add(SizedBox(height: gap));
    }
    return Column(children: rows);
  }

  Widget _equalRow(List<Widget> children, double gap) {
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) spaced.add(SizedBox(width: gap));
      spaced.add(children[i]);
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: spaced,
      ),
    );
  }
}

class _StepCard extends StatefulWidget {
  const _StepCard({required this.step});

  final LandingHowItWorksStep step;

  @override
  State<_StepCard> createState() => _StepCardState();
}

class _StepCardState extends State<_StepCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    final lift = _hover && !reduce;
    return MouseRegion(
      onEnter: (event) {
        if (event.kind != PointerDeviceKind.mouse) return;
        setState(() => _hover = true);
      },
      onExit: (_) {
        if (_hover) setState(() => _hover = false);
      },
      child: AnimatedContainer(
        duration: reduce ? Duration.zero : const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        transform: Matrix4.translationValues(0, lift ? -6 : 0, 0),
        padding: const EdgeInsets.fromLTRB(14, 22, 14, 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFF4D5C2)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF97316).withValues(alpha: lift ? 0.12 : 0.05),
              blurRadius: lift ? 24 : 14,
              offset: Offset(0, lift ? 12 : 6),
            ),
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _StepIcon(icon: widget.step.icon, number: widget.step.number, hovered: lift),
            const SizedBox(height: 16),
            Text(
              widget.step.title,
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                color: LandingHowItWorksSection.navy,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.step.description,
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                color: LandingHowItWorksSection.muted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({
    required this.icon,
    required this.number,
    required this.hovered,
  });

  final IconData icon;
  final String number;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return SizedBox(
      width: 78,
      height: 78,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          const Positioned(
            right: 2,
            bottom: 4,
            child: _SoftBlob(size: 36),
          ),
          AnimatedScale(
            scale: hovered && !reduce ? 1.06 : 1,
            duration: reduce ? Duration.zero : const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: LandingHowItWorksSection.orange,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: LandingHowItWorksSection.orange.withValues(alpha: 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFF8D3B8)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF97316).withValues(alpha: 0.16),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                number,
                style: GoogleFonts.montserrat(
                  color: LandingHowItWorksSection.orange,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftBlob extends StatelessWidget {
  const _SoftBlob({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFFFFE6D2),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _HowItWorksBackdropPainter extends CustomPainter {
  const _HowItWorksBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final wash = Paint()..color = const Color(0xFFFFEBD9).withValues(alpha: 0.45);
    canvas.drawCircle(Offset(size.width * 0.08, size.height * 0.2), 72, wash);
    canvas.drawCircle(Offset(size.width * 0.9, 28), 48, wash);

    final hill = Path()
      ..moveTo(0, size.height * 0.55)
      ..quadraticBezierTo(size.width * 0.12, size.height * 0.32, size.width * 0.24, size.height * 0.5)
      ..quadraticBezierTo(size.width * 0.32, size.height * 0.62, size.width * 0.18, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(hill, Paint()..color = const Color(0xFFFFE4CC).withValues(alpha: 0.55));

    final shore = Path()
      ..moveTo(0, size.height * 0.72)
      ..quadraticBezierTo(size.width * 0.16, size.height * 0.62, size.width * 0.28, size.height * 0.78)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(shore, Paint()..color = const Color(0xFFD7EAF8).withValues(alpha: 0.35));

    _building(canvas, Offset(size.width * 0.86, size.height * 0.42));
    _palm(canvas, Offset(size.width * 0.74, size.height * 0.38));
    _palm(canvas, Offset(size.width * 0.96, size.height * 0.36));

    final pin = Offset(size.width * 0.9, 18);
    final pinPath = Path()
      ..moveTo(pin.dx, pin.dy + 14)
      ..quadraticBezierTo(pin.dx + 10, pin.dy, pin.dx, pin.dy - 10)
      ..quadraticBezierTo(pin.dx - 10, pin.dy, pin.dx, pin.dy + 14);
    canvas.drawPath(pinPath, Paint()..color = const Color(0xFFF97316).withValues(alpha: 0.85));

    final route = Paint()
      ..color = const Color(0xFFF6C9A8).withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    final wave = Path()
      ..moveTo(size.width * 0.18, 22)
      ..quadraticBezierTo(size.width * 0.32, 48, size.width * 0.46, 18);
    canvas.drawPath(wave, route);

    final dots = Paint()..color = const Color(0xFFF3C7A6);
    for (var i = 0; i < 7; i++) {
      canvas.drawCircle(Offset(size.width * 0.55 + i * 11, 36 + (i % 2) * 6), 1.5, dots);
    }
    canvas.drawPath(
      Path()
        ..addArc(
          Rect.fromCircle(center: Offset(size.width * 0.12, size.height * 0.12), radius: 36),
          math.pi * 0.15,
          math.pi * 0.8,
        ),
      route,
    );
  }

  void _building(Canvas canvas, Offset origin) {
    final stone = Paint()..color = const Color(0xFFF6E6D4).withValues(alpha: 0.9);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(origin.dx, origin.dy, 92, 46),
        const Radius.circular(2),
      ),
      stone,
    );
    canvas.drawRect(
      Rect.fromLTWH(origin.dx - 6, origin.dy - 8, 104, 10),
      Paint()..color = const Color(0xFFEED3B8).withValues(alpha: 0.9),
    );
    final column = Paint()..color = const Color(0xFFFFF8F3);
    for (var i = 0; i < 4; i++) {
      canvas.drawRect(Rect.fromLTWH(origin.dx + 10 + i * 20, origin.dy + 8, 6, 30), column);
    }
  }

  void _palm(Canvas canvas, Offset base) {
    canvas.drawLine(
      base,
      base.translate(2, 28),
      Paint()
        ..color = const Color(0xFFE7C4A4)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    final leaf = Paint()..color = const Color(0xFFF3D2B4).withValues(alpha: 0.95);
    canvas.drawOval(Rect.fromCenter(center: base.translate(-8, 0), width: 16, height: 6), leaf);
    canvas.drawOval(Rect.fromCenter(center: base.translate(10, -2), width: 16, height: 6), leaf);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
