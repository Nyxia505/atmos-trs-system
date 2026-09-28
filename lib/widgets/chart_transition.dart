import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Smooth chart transitions shared by every dashboard.
///
/// When [swapKey] changes (e.g. range Week → Month) the old chart fades out
/// while the new one fades in and grows from the baseline: [builder] receives
/// a `progress` that animates 0 → 1. Same-key rebuilds (live data updates)
/// keep `progress == 1` so the chart's own implicit tween handles them.
class ChartTransition extends StatelessWidget {
  const ChartTransition({
    super.key,
    required this.swapKey,
    required this.builder,
    this.growDuration = const Duration(milliseconds: 750),
    this.fadeDuration = const Duration(milliseconds: 280),
  });

  final Object? swapKey;
  final Widget Function(BuildContext context, double progress) builder;
  final Duration growDuration;
  final Duration fadeDuration;

  /// fl_chart's own tween must be off while [progress] drives the frames.
  static Duration chartDuration(
    double progress, [
    Duration settled = const Duration(milliseconds: 450),
  ]) =>
      progress < 1 ? Duration.zero : settled;

  static List<double> scale(Iterable<num> values, double progress) =>
      [for (final v in values) v.toDouble() * progress];

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: fadeDuration,
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.passthrough,
        alignment: Alignment.center,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: TweenAnimationBuilder<double>(
        key: ValueKey<Object?>(swapKey),
        tween: Tween<double>(begin: 0, end: 1),
        duration: growDuration,
        curve: Curves.easeOutCubic,
        builder: (context, t, _) => builder(context, t),
      ),
    );
  }
}

/// Morphs a numeric series for hand-painted charts (CustomPainter).
///
/// The first build grows from zero; later value changes — including a
/// different length (7 days → 30 days) — resample the old series onto the new
/// length and tween point by point. [builder] also gets an animated axis max
/// so the scale eases instead of jumping.
class AnimatedSeries extends StatefulWidget {
  const AnimatedSeries({
    super.key,
    required this.values,
    required this.builder,
    this.duration = const Duration(milliseconds: 650),
    this.curve = Curves.easeInOutCubic,
  });

  final List<double> values;
  final Widget Function(
    BuildContext context,
    List<double> values,
    double maxValue,
  ) builder;
  final Duration duration;
  final Curve curve;

  static List<double> resample(List<double> src, int n) {
    if (n <= 0) return const [];
    if (src.isEmpty) return List<double>.filled(n, 0);
    if (src.length == n) return src;
    if (src.length == 1 || n == 1) return List<double>.filled(n, src.first);
    return List<double>.generate(n, (i) {
      final pos = i * (src.length - 1) / (n - 1);
      final lo = pos.floor();
      final hi = math.min(lo + 1, src.length - 1);
      return src[lo] + (src[hi] - src[lo]) * (pos - lo);
    });
  }

  static double maxOf(List<double> v) =>
      v.isEmpty ? 0 : v.reduce(math.max);

  @override
  State<AnimatedSeries> createState() => _AnimatedSeriesState();
}

class _AnimatedSeriesState extends State<AnimatedSeries>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration);
  late List<double> _from;
  late double _fromMax;

  @override
  void initState() {
    super.initState();
    _from = List<double>.filled(widget.values.length, 0);
    _fromMax = AnimatedSeries.maxOf(widget.values);
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant AnimatedSeries oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (listEquals(oldWidget.values, widget.values)) return;
    final t = oldWidget.curve.transform(_controller.value);
    _from = _lerp(oldWidget.values, t);
    _fromMax = _lerpMax(oldWidget.values, t);
    _controller.forward(from: 0);
  }

  List<double> _lerp(List<double> target, double t) {
    final from = AnimatedSeries.resample(_from, target.length);
    return [
      for (var i = 0; i < target.length; i++)
        from[i] + (target[i] - from[i]) * t,
    ];
  }

  double _lerpMax(List<double> target, double t) {
    final to = AnimatedSeries.maxOf(target);
    return _fromMax + (to - _fromMax) * t;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = widget.curve.transform(_controller.value);
        return widget.builder(
          context,
          _lerp(widget.values, t),
          _lerpMax(widget.values, t),
        );
      },
    );
  }
}
