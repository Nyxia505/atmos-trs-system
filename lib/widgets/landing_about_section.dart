import 'package:atmos_trs_system/config/atmos_brand_typography.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LandingAboutStat {
  const LandingAboutStat({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;
}

/// About copy, capitol photo, and statistics, matching the approved layout.
class LandingAboutShowcase extends StatefulWidget {
  const LandingAboutShowcase({
    super.key,
    required this.body,
    required this.bodyStyle,
    required this.titleSize,
    required this.capitol,
    required this.stats,
    required this.bleed,
    required this.compact,
    required this.tablet,
  });

  final String body;
  final TextStyle bodyStyle;
  final double titleSize;
  final Widget capitol;
  final List<LandingAboutStat> stats;
  final double bleed;
  final bool compact;
  final bool tablet;

  static const Color page = Color(0xFFFFF8F3);
  static const Color orange = Color(0xFFF97316);
  static const Color navy = Color(0xFF1B2433);

  @override
  State<LandingAboutShowcase> createState() => _LandingAboutShowcaseState();
}

class _LandingAboutShowcaseState extends State<LandingAboutShowcase>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal;
  ScrollPosition? _position;
  bool _started = false;
  bool _reduceMotion = false;
  double _screenHeight = 800;

  @override
  void initState() {
    super.initState();
    _reveal = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 640),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = Scrollable.maybeOf(context)?.position;
    if (!identical(next, _position)) {
      _position?.removeListener(_onScroll);
      _position = next;
      _position?.addListener(_onScroll);
    }
    _screenHeight = MediaQuery.sizeOf(context).height;
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _reveal.value = 1;
      _started = true;
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    _reveal.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || _started) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    final top = box.localToGlobal(Offset.zero).dy;
    if (top < _screenHeight * 0.92) {
      _started = true;
      if (_reduceMotion) {
        _reveal.value = 1;
      } else {
        _reveal.forward();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final photoHeight = widget.compact ? 240.0 : (widget.tablet ? 300.0 : 340.0);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: -widget.bleed,
          right: -widget.bleed,
          top: 0,
          bottom: 0,
          child: const ColoredBox(
            color: LandingAboutShowcase.page,
            child: CustomPaint(painter: _AboutBackdropPainter()),
          ),
        ),
        AnimatedBuilder(
          animation: _reveal,
          builder: (context, child) {
            final t = Curves.easeOutCubic.transform(_reveal.value);
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * 24),
                child: child,
              ),
            );
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.compact)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AboutCopy(body: widget.body, bodyStyle: widget.bodyStyle, titleSize: widget.titleSize),
                    const SizedBox(height: 24),
                    _CapitolPhoto(height: photoHeight, image: widget.capitol),
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _AboutCopy(
                        body: widget.body,
                        bodyStyle: widget.bodyStyle,
                        titleSize: widget.titleSize,
                      ),
                    ),
                    SizedBox(width: widget.tablet ? 24 : 40),
                    Expanded(
                      child: _CapitolPhoto(height: photoHeight, image: widget.capitol),
                    ),
                  ],
                ),
              SizedBox(height: widget.compact ? 28 : 40),
              const _NumbersHeading(),
              const SizedBox(height: 22),
              _StatsGrid(
                stats: widget.stats,
                compact: widget.compact,
                tablet: widget.tablet,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AboutCopy extends StatelessWidget {
  const _AboutCopy({
    required this.body,
    required this.bodyStyle,
    required this.titleSize,
  });

  final String body;
  final TextStyle bodyStyle;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    final title = AtmosBrandTypography.displayTitle(
      color: LandingAboutShowcase.navy,
      fontSize: titleSize,
      letterSpacing: 0.3,
      height: 1.15,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1E6),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFF8D7C0)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.circle, size: 8, color: LandingAboutShowcase.orange),
              const SizedBox(width: 8),
              Text(
                'ABOUT ATMOS-TRS',
                style: GoogleFonts.montserrat(
                  color: LandingAboutShowcase.orange,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text.rich(
          TextSpan(
            style: title,
            children: [
              const TextSpan(text: 'Advancing Tourism in\n'),
              TextSpan(
                text: 'Misamis Occidental',
                style: TextStyle(color: LandingAboutShowcase.orange),
              ),
            ],
          ),
          textAlign: TextAlign.start,
        ),
        const SizedBox(height: 12),
        Container(
          width: 42,
          height: 4,
          decoration: BoxDecoration(
            color: LandingAboutShowcase.orange,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 18),
        Text(body, style: bodyStyle),
      ],
    );
  }
}

class _CapitolPhoto extends StatelessWidget {
  const _CapitolPhoto({required this.height, required this.image});

  final double height;
  final Widget image;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          fit: StackFit.expand,
          children: [
            image,
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x00000000),
                    Color(0x140F172A),
                    Color(0xCCFFF8F3),
                  ],
                  stops: [0.45, 0.68, 1],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Provincial Governor',
                    style: TextStyle(
                      color: LandingAboutShowcase.orange,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Misamis Occidental',
                    style: TextStyle(
                      color: LandingAboutShowcase.navy,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumbersHeading extends StatelessWidget {
  const _NumbersHeading();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Column(
      children: [
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: LandingAboutShowcase.orange,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF1E6),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFF8D7C0)),
          ),
          child: Text(
            'IMPACT',
            style: GoogleFonts.montserrat(
              color: LandingAboutShowcase.orange,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'By the '),
              TextSpan(
                text: 'numbers',
                style: TextStyle(color: LandingAboutShowcase.orange),
              ),
            ],
          ),
          textAlign: TextAlign.center,
          style: AtmosBrandTypography.displayTitle(
            color: LandingAboutShowcase.navy,
            fontSize: width < 720 ? 28 : 36,
            letterSpacing: 0.2,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Growing smart tourism across Misamis Occidental',
          textAlign: TextAlign.center,
          style: GoogleFonts.montserrat(
            color: const Color(0xFF64748B),
            fontSize: width < 720 ? 14 : 15.5,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.stats,
    required this.compact,
    required this.tablet,
  });

  final List<LandingAboutStat> stats;
  final bool compact;
  final bool tablet;

  @override
  Widget build(BuildContext context) {
    const gap = 14.0;
    if (compact) {
      return Column(
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) const SizedBox(height: gap),
            _StatCard(stat: stats[i]),
          ],
        ],
      );
    }
    if (tablet) {
      return Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _StatCard(stat: stats[0])),
              const SizedBox(width: gap),
              Expanded(child: _StatCard(stat: stats[1])),
            ],
          ),
          const SizedBox(height: gap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _StatCard(stat: stats[2])),
              const SizedBox(width: gap),
              Expanded(child: _StatCard(stat: stats[3])),
            ],
          ),
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) const SizedBox(width: gap),
            Expanded(child: _StatCard(stat: stats[i])),
          ],
        ],
      ),
    );
  }
}

class _StatCard extends StatefulWidget {
  const _StatCard({required this.stat});

  final LandingAboutStat stat;

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> {
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
        transform: Matrix4.translationValues(0, lift ? -5 : 0, 0),
        padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFF4D5C2)),
          boxShadow: [
            BoxShadow(
              color: LandingAboutShowcase.orange.withValues(alpha: lift ? 0.12 : 0.05),
              blurRadius: lift ? 22 : 14,
              offset: Offset(0, lift ? 10 : 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: LandingAboutShowcase.orange,
                shape: BoxShape.circle,
              ),
              child: Icon(widget.stat.icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.stat.value,
                      maxLines: 1,
                      style: GoogleFonts.montserrat(
                        color: LandingAboutShowcase.navy,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.stat.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.montserrat(
                      color: const Color(0xFF64748B),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              widget.stat.icon,
              size: 42,
              color: const Color(0xFFFFE0CC),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutBackdropPainter extends CustomPainter {
  const _AboutBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final peach = Paint()..color = const Color(0xFFFFE7D4).withValues(alpha: 0.55);
    canvas.drawCircle(Offset(size.width * 0.22, 28), 34, peach);
    canvas.drawCircle(Offset(size.width * 0.08, size.height * 0.22), 18, peach);

    final mountain = Path()
      ..moveTo(0, size.height * 0.72)
      ..lineTo(size.width * 0.12, size.height * 0.5)
      ..lineTo(size.width * 0.24, size.height * 0.68)
      ..lineTo(size.width * 0.4, size.height * 0.42)
      ..lineTo(size.width * 0.58, size.height * 0.7)
      ..lineTo(size.width * 0.76, size.height * 0.46)
      ..lineTo(size.width, size.height * 0.68)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      mountain,
      Paint()..color = const Color(0xFFFFE4CC).withValues(alpha: 0.45),
    );

    _palm(canvas, Offset(size.width * 0.16, size.height * 0.18));
    _palm(canvas, Offset(size.width * 0.93, size.height * 0.16));

    final dots = Paint()..color = const Color(0xFFF6C9A8);
    for (var i = 0; i < 5; i++) {
      canvas.drawCircle(Offset(size.width * 0.62 + i * 8, 22), 1.4, dots);
    }
  }

  void _palm(Canvas canvas, Offset base) {
    canvas.drawLine(
      base,
      base.translate(1, 22),
      Paint()
        ..color = const Color(0xFFF0C8A8)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
    final leaf = Paint()..color = const Color(0xFFF6D3B6);
    canvas.drawOval(Rect.fromCenter(center: base.translate(-7, 0), width: 14, height: 5), leaf);
    canvas.drawOval(Rect.fromCenter(center: base.translate(8, -1), width: 14, height: 5), leaf);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
