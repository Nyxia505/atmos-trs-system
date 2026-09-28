import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// One step of a guided tour. A step without [target] shows a centered card.
class CoachStep {
  const CoachStep({
    this.target,
    required this.title,
    required this.body,
    this.requireTap = false,
    this.padding = 8,
    this.primaryLabel,
    this.icon,
    this.onShow,
    this.onAdvance,
    this.waitForTarget = Duration.zero,
  });

  final GlobalKey? target;
  final String title;
  final String body;

  /// The user must tap the highlighted widget to continue (no Next button).
  final bool requireTap;
  final double padding;
  final String? primaryLabel;
  final IconData? icon;

  /// Runs when this step becomes active (e.g. to scroll a carousel).
  final VoidCallback? onShow;

  /// Runs when the user moves past this step (Next or a tap on the target),
  /// e.g. to open or close the page the following step points at.
  final VoidCallback? onAdvance;

  /// How long to wait for [target] to appear (e.g. on a page being pushed)
  /// before this step is skipped.
  final Duration waitForTarget;
}

/// Spotlight-style guided tour drawn on the root overlay.
class CoachMarkOverlay {
  CoachMarkOverlay._();

  static OverlayEntry? _active;

  static bool get isShowing => _active != null;

  static void dismiss() {
    _active?.remove();
    _active = null;
  }

  static void show(
    BuildContext context, {
    required List<CoachStep> steps,
    VoidCallback? onFinish,
    VoidCallback? onSkip,
  }) {
    if (steps.isEmpty) return;
    dismiss();
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _CoachMarkLayer(
        steps: steps,
        onClose: (skipped) {
          if (_active == entry) {
            entry.remove();
            _active = null;
          }
          (skipped ? onSkip : onFinish)?.call();
        },
      ),
    );
    _active = entry;
    overlay.insert(entry);
  }
}

class _CoachMarkLayer extends StatefulWidget {
  const _CoachMarkLayer({required this.steps, required this.onClose});

  final List<CoachStep> steps;
  final void Function(bool skipped) onClose;

  @override
  State<_CoachMarkLayer> createState() => _CoachMarkLayerState();
}

class _CoachMarkLayerState extends State<_CoachMarkLayer>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();
  late final AnimationController _transition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  )..value = 1;

  int _index = 0;
  Rect? _fromRect;
  Rect? _shownRect;
  bool _closed = false;
  bool _advancing = false;

  @override
  void initState() {
    super.initState();
    _index = _firstAvailable(0);
    if (_index < 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _close(false));
    } else {
      _revealTarget();
    }
  }

  void _revealTarget() {
    _step?.onShow?.call();
    final ctx = _step?.target?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.3,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    _transition.dispose();
    super.dispose();
  }

  CoachStep? get _step =>
      _index >= 0 && _index < widget.steps.length ? widget.steps[_index] : null;

  bool _isAvailable(CoachStep step) =>
      step.target == null || _targetRect(step) != null;

  int _firstAvailable(int from) {
    for (var i = from; i < widget.steps.length; i++) {
      if (_isAvailable(widget.steps[i])) return i;
    }
    return -1;
  }

  /// Available now, or expected to appear once an earlier step's
  /// [CoachStep.onAdvance] opens its page.
  bool _isPlanned(CoachStep step) =>
      _isAvailable(step) || step.waitForTarget > Duration.zero;

  bool get _isLast {
    for (var i = _index + 1; i < widget.steps.length; i++) {
      if (_isPlanned(widget.steps[i])) return false;
    }
    return true;
  }

  Future<int> _nextAvailable(int from) async {
    for (var i = from; i < widget.steps.length; i++) {
      final step = widget.steps[i];
      if (_isAvailable(step)) return i;
      if (step.waitForTarget <= Duration.zero) continue;
      final deadline = DateTime.now().add(step.waitForTarget);
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        if (_closed || !mounted) return -1;
        if (_isAvailable(step)) return i;
      }
    }
    return -1;
  }

  /// Target bounds in this layer's local coordinates.
  Rect? _targetRect(CoachStep step) {
    final ctx = step.target?.currentContext;
    final box = ctx?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final layer = context.findRenderObject();
    final topLeft = box.localToGlobal(Offset.zero);
    final local = layer is RenderBox && layer.hasSize
        ? layer.globalToLocal(topLeft)
        : topLeft;
    return (local & box.size).inflate(step.padding);
  }

  Future<void> _next() async {
    if (_closed || _advancing) return;
    setState(() => _advancing = true);
    _step?.onAdvance?.call();
    final next = await _nextAvailable(_index + 1);
    if (_closed || !mounted) return;
    if (next < 0) {
      _close(false);
      return;
    }
    setState(() {
      _advancing = false;
      _fromRect = _shownRect;
      _index = next;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _revealTarget();
    });
    _transition.forward(from: 0);
  }

  void _close(bool skipped) {
    if (_closed) return;
    _closed = true;
    widget.onClose(skipped);
  }

  void _onTapUp(TapUpDetails details, Rect? hole) {
    if (hole != null && hole.contains(details.localPosition)) {
      _next();
    }
  }

  Rect? _currentHole(Size screen) {
    final step = _step;
    if (step == null) return null;
    final live = step.target == null ? null : _targetRect(step);
    if (live == null) return null;
    final t = Curves.easeOutCubic.transform(_transition.value);
    final from = _fromRect ??
        Rect.fromCenter(
          center: live.center,
          width: screen.longestSide * 2,
          height: screen.longestSide * 2,
        );
    return Rect.lerp(from, live, t);
  }

  @override
  Widget build(BuildContext context) {
    final step = _step;
    if (step == null) return const SizedBox.shrink();

    Widget layer = AnimatedBuilder(
      animation: Listenable.merge([_pulse, _transition]),
      builder: (context, _) {
        final screen = MediaQuery.sizeOf(context);
        final hole = _advancing ? null : _currentHole(screen);
        _shownRect = hole;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) => _onTapUp(d, hole),
                child: CustomPaint(
                  painter: _ScrimPainter(
                    hole: hole,
                    pulse: step.requireTap ? _pulse.value : null,
                    ringColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
            if (!_advancing) _positionedCard(context, step, hole, screen),
          ],
        );
      },
    );

    if (kIsWeb) layer = PointerInterceptor(child: layer);
    return Material(type: MaterialType.transparency, child: layer);
  }

  Widget _positionedCard(
    BuildContext context,
    CoachStep step,
    Rect? hole,
    Size screen,
  ) {
    final card = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: _CoachCard(
        step: step,
        stepNumber: _visibleNumber(),
        stepCount: _visibleCount(),
        isLast: _isLast,
        onNext: _next,
        onSkip: () => _close(true),
      ),
    );

    if (hole == null) {
      return Positioned.fill(
        child: Center(
          child: Padding(padding: const EdgeInsets.all(24), child: card),
        ),
      );
    }

    final spaceBelow = screen.height - hole.bottom;
    final spaceAbove = hole.top;
    final alignX =
        ((hole.center.dx / math.max(screen.width, 1)) * 2 - 1).clamp(-1.0, 1.0);
    final aligned = Align(alignment: Alignment(alignX, 0), child: card);

    if (spaceBelow >= spaceAbove) {
      return Positioned(
        left: 16,
        right: 16,
        top: hole.bottom + 16,
        child: aligned,
      );
    }
    return Positioned(
      left: 16,
      right: 16,
      bottom: screen.height - hole.top + 16,
      child: aligned,
    );
  }

  int _visibleCount() =>
      widget.steps.where((s) => s.target != null && _isPlanned(s)).length;

  int _visibleNumber() {
    var n = 0;
    for (var i = 0; i <= _index; i++) {
      final s = widget.steps[i];
      if (s.target != null && _isPlanned(s)) n++;
    }
    return n;
  }
}

class _CoachCard extends StatelessWidget {
  const _CoachCard({
    required this.step,
    required this.stepNumber,
    required this.stepCount,
    required this.isLast,
    required this.onNext,
    required this.onSkip,
  });

  final CoachStep step;
  final int stepNumber;
  final int stepCount;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final isIntro = step.target == null;

    return Material(
      color: theme.colorScheme.surface,
      elevation: 12,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    step.icon ??
                        (step.requireTap
                            ? Icons.touch_app_rounded
                            : Icons.lightbulb_outline_rounded),
                    color: accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    step.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (!isIntro && stepCount > 0)
                  Text(
                    '$stepNumber/$stepCount',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.hintColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              step.body,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.35),
            ),
            if (!isIntro && stepCount > 1) ...[
              const SizedBox(height: 12),
              Row(
                children: List.generate(stepCount, (i) {
                  final active = i == stepNumber - 1;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.only(right: 5),
                    width: active ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: active
                          ? accent
                          : accent.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                if (!isLast)
                  TextButton(
                    onPressed: onSkip,
                    child: Text(isIntro ? 'Skip' : 'Skip tour'),
                  ),
                const Spacer(),
                if (step.requireTap)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.touch_app_rounded, size: 18, color: accent),
                        const SizedBox(width: 6),
                        Text(
                          'Tap the highlighted button',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  FilledButton(
                    onPressed: onNext,
                    child: Text(
                      step.primaryLabel ?? (isLast ? 'Done' : 'Next'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrimPainter extends CustomPainter {
  _ScrimPainter({required this.hole, required this.pulse, required this.ringColor});

  final Rect? hole;
  final double? pulse;
  final Color ringColor;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = Colors.black.withValues(alpha: 0.72);
    final full = Offset.zero & size;
    final h = hole;
    if (h == null) {
      canvas.drawRect(full, scrim);
      return;
    }
    final radius = Radius.circular(math.min(16, h.shortestSide / 2));
    final rrect = RRect.fromRectAndRadius(h, radius);
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(full)
      ..addRRect(rrect);
    canvas.drawPath(path, scrim);

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.9),
    );

    final p = pulse;
    if (p != null) {
      final grow = 14 * p;
      canvas.drawRRect(
        RRect.fromRectAndRadius(h.inflate(grow), radius + Radius.circular(grow)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = ringColor.withValues(alpha: (1 - p) * 0.9),
      );
    }
  }

  @override
  bool shouldRepaint(_ScrimPainter old) =>
      old.hole != hole || old.pulse != pulse || old.ringColor != ringColor;
}
