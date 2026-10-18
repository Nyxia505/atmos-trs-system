import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Brand orange used for the light hover glow on tables and stat boxes.
const Color kAtmosTableGlow = Color(0xFFF97316);
const Color kAtmosTableGrid = Color(0xFFE2E8F0);
const Color kAtmosTableHeader = Color(0xFFFFF7ED);
const Color kAtmosTableText = Color(0xFF1F2937);
const Color kAtmosTableMuted = Color(0xFF6B7280);

/// Lifts and warms a box while the pointer is over it, then settles back.
///
/// The glow stays low so labels inside the box stay readable.
class AtmosHoverLift extends StatefulWidget {
  const AtmosHoverLift({
    super.key,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(12)),
    this.restColor = const Color(0xFFFFFFFF),
    this.restBorderColor = kAtmosTableGrid,
    this.borderWidth = 1,
    this.lift = 3,
    this.enabled = true,
  });

  final Widget child;
  final BorderRadius radius;
  final Color restColor;
  final Color restBorderColor;
  final double borderWidth;
  final double lift;
  final bool enabled;

  @override
  State<AtmosHoverLift> createState() => _AtmosHoverLiftState();
}

class _AtmosHoverLiftState extends State<AtmosHoverLift> {
  bool _on = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: widget.enabled ? (_) => setState(() => _on = true) : null,
      onExit: widget.enabled ? (_) => setState(() => _on = false) : null,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: _on ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) {
          return Transform.translate(
            offset: Offset(0, -widget.lift * t),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: widget.radius,
                boxShadow: [
                  BoxShadow(
                    color: kAtmosTableGlow.withValues(alpha: 0.16 * t),
                    blurRadius: 14,
                    offset: Offset(0, 6 * t),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color.alphaBlend(
                        kAtmosTableGlow.withValues(alpha: 0.06 * t),
                        widget.restColor,
                      ),
                      borderRadius: widget.radius,
                      border: Border.all(
                        color: widget.restBorderColor,
                        width: widget.borderWidth,
                      ),
                    ),
                    child: child,
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: widget.radius,
                          border: Border.all(
                            color: kAtmosTableGlow.withValues(alpha: 0.34 * t),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

class AtmosTableColumn {
  const AtmosTableColumn(
    this.label, {
    this.flex = 1,
    this.minWidth = 96,
    this.align = Alignment.centerLeft,
  });

  final String label;
  final int flex;
  final double minWidth;
  final Alignment align;
}

/// Full-width grid table. Columns share leftover space and scroll sideways
/// only when their minimum widths no longer fit, so cells never overlap.
class AtmosResponsiveTable extends StatelessWidget {
  const AtmosResponsiveTable({
    super.key,
    required this.columns,
    required this.rows,
    this.footer,
    this.empty,
  });

  final List<AtmosTableColumn> columns;
  final List<List<Widget>> rows;
  final List<Widget>? footer;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final minSum = columns.fold<double>(0, (s, c) => s + c.minWidth);
        final viewport = constraints.maxWidth;
        final width = viewport.isFinite ? math.max(viewport, minSum) : minSum;
        final flexSum = columns.fold<int>(0, (s, c) => s + math.max(1, c.flex));
        final extra = math.max(0.0, width - minSum);
        final widths = [
          for (final c in columns) c.minWidth + extra * (math.max(1, c.flex) / flexSum),
        ];

        Widget line(List<Widget> cells, {required bool hover, Color? rest}) {
          final row = Row(
            children: [
              for (var i = 0; i < columns.length; i++)
                _cell(
                  widths[i],
                  columns[i].align,
                  i == columns.length - 1,
                  i < cells.length ? cells[i] : const SizedBox.shrink(),
                ),
            ],
          );
          if (!hover) {
            return DecoratedBox(
              decoration: BoxDecoration(
                color: rest ?? kAtmosTableHeader,
                border: const Border(top: BorderSide(color: kAtmosTableGrid)),
              ),
              child: row,
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: AtmosHoverLift(
              radius: BorderRadius.circular(10),
              restColor: rest ?? Colors.white,
              child: row,
            ),
          );
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: kAtmosTableHeader,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: kAtmosTableGlow.withValues(alpha: 0.22)),
                    ),
                    child: Row(
                      children: [
                        for (var i = 0; i < columns.length; i++)
                          _cell(
                            widths[i],
                            columns[i].align,
                            i == columns.length - 1,
                            Text(
                              columns[i].label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: _textAlign(columns[i].align),
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: kAtmosTableMuted,
                                letterSpacing: 0.2,
                              ),
                            ),
                            header: true,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (rows.isEmpty)
                    empty ??
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 18),
                          child: Text(
                            'No rows',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: kAtmosTableMuted, fontSize: 13),
                          ),
                        )
                  else
                    for (var r = 0; r < rows.length; r++)
                      line(
                        rows[r],
                        hover: true,
                        rest: r.isOdd ? const Color(0xFFF8FAFC) : Colors.white,
                      ),
                  if (footer != null) line(footer!, hover: false, rest: const Color(0xFFFFF7ED)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static TextAlign _textAlign(Alignment align) {
    if (align == Alignment.center) return TextAlign.center;
    if (align.x > 0.5) return TextAlign.right;
    return TextAlign.left;
  }

  Widget _cell(double width, Alignment align, bool last, Widget child, {bool header = false}) {
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            right: last ? BorderSide.none : const BorderSide(color: kAtmosTableGrid),
          ),
        ),
        child: ClipRect(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: header ? 11 : 10),
            child: Align(alignment: align, child: child),
          ),
        ),
      ),
    );
  }
}
