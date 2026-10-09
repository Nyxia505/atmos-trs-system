import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// "Why Choose ATMOS-TRS?" section rebuilt from the approved Features design.
class LandingFeaturesSection extends StatelessWidget {
  const LandingFeaturesSection({
    super.key,
    required this.onQrLearnMore,
    required this.onExploreVirtualTour,
    required this.onSeeHowItWorks,
    required this.onDigitalIdLearnMore,
    required this.onStartPlanning,
  });

  final VoidCallback onQrLearnMore;
  final VoidCallback onExploreVirtualTour;
  final VoidCallback onSeeHowItWorks;
  final VoidCallback onDigitalIdLearnMore;
  final VoidCallback onStartPlanning;

  static const Color page = Color(0xFFFFF8F4);
  static const Color navy = Color(0xFF1E293B);
  static const Color orange = Color(0xFFF97316);
  static const Color muted = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    final offers = <_FeatureOffer>[
      _FeatureOffer(
        icon: Icons.qr_code_2_rounded,
        title: 'QR Code Registration',
        body:
            'Quick and easy tourist registration with unique QR code identification for a faster, safer, and more convenient travel experience.',
        button: 'Learn More',
        onPressed: onQrLearnMore,
        art: const _QrPhoneArt(),
      ),
      _FeatureOffer(
        icon: Icons.image_outlined,
        title: '360° Virtual Tours',
        body:
            'Explore destinations in immersive 360° virtual tours before you visit and discover the beauty of Misamis Occidental.',
        button: 'Explore Now',
        onPressed: onExploreVirtualTour,
        art: const _VrPhoneArt(),
      ),
      _FeatureOffer(
        icon: Icons.location_on_outlined,
        title: 'Smart Check-ins',
        body:
            'Scan your QR at tourist spots with GPS verification for a seamless and secure check-in experience.',
        button: 'See How It Works',
        onPressed: onSeeHowItWorks,
        art: const _CheckInPhoneArt(),
      ),
      _FeatureOffer(
        icon: Icons.badge_outlined,
        title: 'Digital Tourist ID',
        body:
            'Your unique digital identification for all tourist activities, making your travels more personalized, organized, and secure.',
        button: 'Learn More',
        onPressed: onDigitalIdLearnMore,
        art: const _TouristIdArt(),
      ),
      _FeatureOffer(
        icon: Icons.map_outlined,
        title: 'Itinerary Planner',
        body:
            'Plan and organize your travel itinerary with day-by-day destinations, travel estimates, and personalized recommendations.',
        button: 'Start Planning',
        onPressed: onStartPlanning,
        art: const _ItineraryMapArt(),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            const Positioned.fill(child: CustomPaint(painter: _FeaturesBackdropPainter())),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _FeaturesHeading(),
                const SizedBox(height: 28),
                _FeaturesCardGrid(width: width, offers: offers),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _FeatureOffer {
  const _FeatureOffer({
    required this.icon,
    required this.title,
    required this.body,
    required this.button,
    required this.onPressed,
    required this.art,
  });

  final IconData icon;
  final String title;
  final String body;
  final String button;
  final VoidCallback onPressed;
  final Widget art;
}

class _FeaturesHeading extends StatelessWidget {
  const _FeaturesHeading();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final titleSize = width < 720 ? 30.0 : (width < 1100 ? 36.0 : 44.0);
    return Column(
      children: [
        Container(
          width: 46,
          height: 4,
          decoration: BoxDecoration(
            color: LandingFeaturesSection.orange,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 16),
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
                Icons.auto_awesome,
                size: 14,
                color: LandingFeaturesSection.orange,
              ),
              const SizedBox(width: 6),
              Text(
                'OFFICIAL PROVINCIAL PLATFORM',
                style: GoogleFonts.montserrat(
                  color: LandingFeaturesSection.orange,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.05,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Why Choose '),
              TextSpan(
                text: 'ATMOS-TRS?',
                style: TextStyle(color: LandingFeaturesSection.orange),
              ),
            ],
          ),
          textAlign: TextAlign.center,
          style: GoogleFonts.montserrat(
            color: const Color(0xFF1B2433),
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Text(
            'Smart registration, VR tours, itinerary planning & QR check-ins — all in one platform.',
            textAlign: TextAlign.center,
            style: GoogleFonts.montserrat(
              color: LandingFeaturesSection.muted,
              fontSize: width < 720 ? 14.5 : 16.5,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _FeaturesCardGrid extends StatelessWidget {
  const _FeaturesCardGrid({required this.width, required this.offers});

  final double width;
  final List<_FeatureOffer> offers;

  @override
  Widget build(BuildContext context) {
    const gap = 18.0;
    if (width >= 1100) {
      final top = (width - gap * 2) / 3;
      final bottom = math.min(top * 1.42, (width - gap) / 2);
      final side = math.max(0.0, (width - (bottom * 2 + gap)) / 2);
      return Column(
        children: [
          _equalRow([
            for (var i = 0; i < 3; i++)
              Expanded(child: _FeatureCard(offer: offers[i])),
          ], gap),
          const SizedBox(height: gap),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            child: _equalRow([
              Expanded(child: _FeatureCard(offer: offers[3])),
              Expanded(child: _FeatureCard(offer: offers[4])),
            ], gap),
          ),
        ],
      );
    }
    if (width >= 700) {
      return Column(
        children: [
          _equalRow([
            Expanded(child: _FeatureCard(offer: offers[0])),
            Expanded(child: _FeatureCard(offer: offers[1])),
          ], gap),
          const SizedBox(height: gap),
          _equalRow([
            Expanded(child: _FeatureCard(offer: offers[2])),
            Expanded(child: _FeatureCard(offer: offers[3])),
          ], gap),
          const SizedBox(height: gap),
          Align(
            alignment: Alignment.center,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: (width - gap) / 2),
              child: _FeatureCard(offer: offers[4]),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        for (var i = 0; i < offers.length; i++) ...[
          if (i > 0) const SizedBox(height: gap),
          _FeatureCard(offer: offers[i], compact: true),
        ],
      ],
    );
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

class _FeatureCard extends StatefulWidget {
  const _FeatureCard({required this.offer, this.compact = false});

  final _FeatureOffer offer;
  final bool compact;

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
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
        transform: Matrix4.translationValues(0, _hover && !reduce ? -4 : 0, 0),
        padding: EdgeInsets.fromLTRB(
          widget.compact ? 16 : 20,
          widget.compact ? 16 : 20,
          12,
          widget.compact ? 16 : 18,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFF4D5C2)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFF97316).withValues(alpha: _hover ? 0.10 : 0.05),
              blurRadius: _hover ? 22 : 16,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: const Color(0xFF0F172A).withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: LandingFeaturesSection.orange,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(widget.offer.icon, color: Colors.white, size: 22),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.offer.title,
                    style: GoogleFonts.montserrat(
                      color: LandingFeaturesSection.navy,
                      fontSize: widget.compact ? 16 : 17.5,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.offer.body,
                    style: GoogleFonts.montserrat(
                      color: LandingFeaturesSection.muted,
                      fontSize: widget.compact ? 12.5 : 13,
                      fontWeight: FontWeight.w500,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: _PeachPillButton(
                        label: widget.offer.button,
                        onPressed: widget.offer.onPressed,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: widget.offer.art,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeachPillButton extends StatelessWidget {
  const _PeachPillButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        backgroundColor: const Color(0xFFFFF1E8),
        foregroundColor: LandingFeaturesSection.orange,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: const Size(44, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            style: GoogleFonts.montserrat(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: LandingFeaturesSection.orange,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_forward_rounded, size: 16),
        ],
      ),
    );
  }
}

class _FeaturesBackdropPainter extends CustomPainter {
  const _FeaturesBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final peach = Paint()..color = const Color(0xFFFFE8D6).withValues(alpha: 0.55);
    canvas.drawCircle(Offset(size.width * 0.08, 36), 70, peach);
    canvas.drawCircle(Offset(size.width * 0.92, size.height * 0.15), 54, peach);
    canvas.drawCircle(
      Offset(size.width * 0.12, size.height * 0.82),
      46,
      Paint()..color = const Color(0xFFFFF1E6),
    );

    final line = Paint()
      ..color = const Color(0xFFF6C9A8).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final wave = Path()
      ..moveTo(size.width * 0.62, 18)
      ..quadraticBezierTo(size.width * 0.78, 48, size.width * 0.95, 12);
    canvas.drawPath(wave, line);

    final dot = Paint()..color = const Color(0xFFF8C9A4).withValues(alpha: 0.9);
    for (var i = 0; i < 8; i++) {
      canvas.drawCircle(
        Offset(size.width * 0.86 + (i % 4) * 10, 70 + (i ~/ 4) * 10),
        1.6,
        dot,
      );
    }
    final arc = Path()
      ..addArc(
        Rect.fromCircle(center: Offset(size.width - 20, size.height * 0.42), radius: 70),
        math.pi * 0.8,
        math.pi * 0.7,
      );
    canvas.drawPath(
      arc,
      Paint()
        ..color = const Color(0xFFF3D0B8).withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _QrPhoneArt extends StatelessWidget {
  const _QrPhoneArt();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 150,
      height: 168,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: 6,
            bottom: 10,
            child: _Blob(size: 78, color: Color(0xFFFFE3CC)),
          ),
          _PhoneFrame(
            width: 96,
            height: 152,
            bezel: Color(0xFFFF7A1A),
            tilt: -0.06,
            child: Padding(
              padding: EdgeInsets.fromLTRB(10, 18, 10, 16),
              child: CustomPaint(painter: _DecorativeQrPainter()),
            ),
          ),
          Positioned(
            right: 18,
            bottom: 22,
            child: _RoundBadge(
              color: Color(0xFFFF7A1A),
              icon: Icons.person_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _VrPhoneArt extends StatelessWidget {
  const _VrPhoneArt();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 168,
      height: 168,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 8,
            bottom: 16,
            child: _Blob(size: 88, color: Color(0xFFFFE7D4)),
          ),
          _PhoneFrame(
            width: 108,
            height: 150,
            bezel: Color(0xFF2A241F),
            child: CustomPaint(painter: _DestinationScenePainter()),
          ),
          Positioned(
            left: 8,
            bottom: 18,
            child: _RoundBadge(
              color: Color(0xFFFF7A1A),
              icon: Icons.threesixty_rounded,
              label: '360°',
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckInPhoneArt extends StatelessWidget {
  const _CheckInPhoneArt();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 160,
      height: 168,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: 0,
            top: 18,
            child: _Blob(size: 72, color: Color(0xFFFFE8D8)),
          ),
          _PhoneFrame(
            width: 92,
            height: 150,
            bezel: Color(0xFFF4F6F8),
            bezelBorder: Color(0xFFE5E7EB),
            child: CustomPaint(painter: _CheckInScenePainter()),
          ),
          Positioned(
            right: 16,
            top: 18,
            child: _RoundBadge(
              color: Color(0xFF22C55E),
              icon: Icons.check_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _TouristIdArt extends StatelessWidget {
  const _TouristIdArt();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 210,
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned(
            right: 8,
            bottom: 8,
            child: _Blob(size: 96, color: Color(0xFFFFE4D0)),
          ),
          Transform.rotate(
            angle: -0.04,
            child: Container(
              width: 188,
              height: 112,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFF3E4D8)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE8EEF5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_rounded, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        _IdLine(width: 72),
                        SizedBox(height: 6),
                        _IdLine(width: 54),
                        SizedBox(height: 6),
                        _IdLine(width: 64),
                      ],
                    ),
                  ),
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CustomPaint(painter: _DecorativeQrPainter()),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItineraryMapArt extends StatelessWidget {
  const _ItineraryMapArt();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 210,
      height: 150,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _ItineraryMapPainter()),
          ),
        ],
      ),
    );
  }
}

class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({
    required this.width,
    required this.height,
    required this.bezel,
    required this.child,
    this.bezelBorder,
    this.tilt = 0,
  });

  final double width;
  final double height;
  final Color bezel;
  final Color? bezelBorder;
  final double tilt;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final phone = Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: bezel,
        borderRadius: BorderRadius.circular(18),
        border: bezelBorder == null ? null : Border.all(color: bezelBorder!),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ColoredBox(color: Colors.white, child: child),
      ),
    );
    if (tilt == 0) return phone;
    return Transform.rotate(angle: tilt, child: phone);
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _RoundBadge extends StatelessWidget {
  const _RoundBadge({required this.color, required this.icon, this.label});

  final Color color;
  final IconData icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: label == null ? 34 : 46,
      height: label == null ? 34 : 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: label == null
          ? Icon(icon, color: Colors.white, size: 18)
          : Text(
              label!,
              style: GoogleFonts.montserrat(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

class _IdLine extends StatelessWidget {
  const _IdLine({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 6,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EDF3),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _DecorativeQrPainter extends CustomPainter {
  const _DecorativeQrPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Paint()..color = const Color(0xFF1F2937);
    final cell = size.shortestSide / 9;
    void block(int x, int y, int w, int h) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x * cell, y * cell, w * cell, h * cell),
          const Radius.circular(1.2),
        ),
        ink,
      );
    }

    void finder(int x, int y) {
      block(x, y, 3, 3);
      canvas.drawRect(
        Rect.fromLTWH((x + 1) * cell, (y + 1) * cell, cell, cell),
        Paint()..color = Colors.white,
      );
    }

    finder(0, 0);
    finder(6, 0);
    finder(0, 6);
    block(4, 2, 1, 1);
    block(5, 3, 1, 1);
    block(4, 4, 1, 1);
    block(6, 4, 1, 1);
    block(7, 5, 1, 1);
    block(5, 6, 1, 1);
    block(3, 7, 1, 1);
    block(8, 7, 1, 1);
    block(7, 8, 1, 1);

    final corner = Paint()
      ..color = const Color(0xFFFF7A1A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(cell * 3.2, cell * 0.2), Offset(cell * 3.2, cell * 1.1), corner);
    canvas.drawLine(Offset(cell * 3.2, cell * 0.2), Offset(cell * 4.2, cell * 0.2), corner);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _DestinationScenePainter extends CustomPainter {
  const _DestinationScenePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final sky = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      sky,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF8EC8F5), Color(0xFFE8F4FF)],
        ).createShader(sky),
    );
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.18),
      8,
      Paint()..color = const Color(0xFFFFE08A),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.5, size.height * 0.78),
        width: size.width,
        height: size.height * 0.38,
      ),
      Paint()..color = const Color(0xFF7DBE6A),
    );
    final building = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.22, size.height * 0.34, size.width * 0.56, size.height * 0.4),
      const Radius.circular(4),
    );
    canvas.drawRRect(building, Paint()..color = const Color(0xFFF3E0C4));
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.18, size.height * 0.30, size.width * 0.64, size.height * 0.08),
      Paint()..color = const Color(0xFFE7C99A),
    );
    final door = Paint()..color = const Color(0xFFC4A574);
    canvas.drawRect(
      Rect.fromLTWH(size.width * 0.44, size.height * 0.52, size.width * 0.12, size.height * 0.22),
      door,
    );
    _palm(canvas, Offset(size.width * 0.16, size.height * 0.62));
    _palm(canvas, Offset(size.width * 0.84, size.height * 0.58));
  }

  void _palm(Canvas canvas, Offset base) {
    canvas.drawLine(
      base,
      base.translate(0, 22),
      Paint()
        ..color = const Color(0xFF8A5A32)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    final leaf = Paint()
      ..color = const Color(0xFF2F8F4E)
      ..style = PaintingStyle.fill;
    canvas.drawOval(Rect.fromCenter(center: base.translate(-8, -2), width: 16, height: 7), leaf);
    canvas.drawOval(Rect.fromCenter(center: base.translate(8, -2), width: 16, height: 7), leaf);
    canvas.drawOval(Rect.fromCenter(center: base.translate(0, -6), width: 8, height: 12), leaf);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CheckInScenePainter extends CustomPainter {
  const _CheckInScenePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF8FAFC));
    final ring = Paint()
      ..color = const Color(0xFFBFDBFE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    final center = Offset(size.width * 0.5, size.height * 0.58);
    canvas.drawCircle(center, 22, ring);
    canvas.drawCircle(
      center,
      10,
      Paint()..color = const Color(0xFF3B82F6).withValues(alpha: 0.25),
    );
    final pin = Path()
      ..moveTo(center.dx, center.dy - 28)
      ..quadraticBezierTo(center.dx + 16, center.dy - 8, center.dx, center.dy + 6)
      ..quadraticBezierTo(center.dx - 16, center.dy - 8, center.dx, center.dy - 28);
    canvas.drawPath(pin, Paint()..color = const Color(0xFFF97316));
    canvas.drawCircle(Offset(center.dx, center.dy - 16), 4, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ItineraryMapPainter extends CustomPainter {
  const _ItineraryMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(18)),
      Paint()..color = const Color(0xFFFFF4EC),
    );
    final route = Path()
      ..moveTo(size.width * 0.18, size.height * 0.72)
      ..quadraticBezierTo(
        size.width * 0.4,
        size.height * 0.2,
        size.width * 0.62,
        size.height * 0.48,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.68,
        size.width * 0.86,
        size.height * 0.28,
      );
    canvas.drawPath(
      route,
      Paint()
        ..color = const Color(0xFFF97316)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    _pin(canvas, Offset(size.width * 0.2, size.height * 0.62));
    _pin(canvas, Offset(size.width * 0.58, size.height * 0.4));
    _pin(canvas, Offset(size.width * 0.82, size.height * 0.22));
    _thumb(canvas, Rect.fromLTWH(8, 10, 54, 40), const Color(0xFF7DBE6A), const Color(0xFF8EC8F5));
    _thumb(
      canvas,
      Rect.fromLTWH(size.width - 70, size.height - 52, 58, 40),
      const Color(0xFFF3E0C4),
      const Color(0xFFB7D7F5),
    );
  }

  void _pin(Canvas canvas, Offset tip) {
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..quadraticBezierTo(tip.dx + 10, tip.dy - 14, tip.dx, tip.dy - 22)
      ..quadraticBezierTo(tip.dx - 10, tip.dy - 14, tip.dx, tip.dy);
    canvas.drawPath(path, Paint()..color = const Color(0xFFF97316));
    canvas.drawCircle(tip.translate(0, -14), 3, Paint()..color = Colors.white);
  }

  void _thumb(Canvas canvas, Rect rect, Color ground, Color sky) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()..color = sky,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(rect.center.dx, rect.bottom - 8),
        width: rect.width,
        height: 16,
      ),
      Paint()..color = ground,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
