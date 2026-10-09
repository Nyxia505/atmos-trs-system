import 'package:flutter/material.dart';

/// Shared width breakpoints for TripPlan layouts.
abstract final class TourismBreakpoints {
  static const double phone = 400;
  static const double tablet = 640;
  static const double desktop = 900;
  static const double wide = 1100;
  static const double adminDrawer = 840;
}

/// Grid columns by available width (1 on phones, up to [maxColumns] on wide screens).
int tourismGridCrossAxisCount(
  double width, {
  int maxColumns = 4,
}) {
  final max = maxColumns.clamp(1, 4);
  if (width >= TourismBreakpoints.wide) return max;
  if (width >= 800) return (max - 1).clamp(1, 3);
  if (width >= TourismBreakpoints.tablet) return 2;
  return 1;
}

/// Tourist spot cards: two columns on phones (matches home / municipality grids).
int tourismSpotGridCrossAxisCount(
  double width, {
  int maxColumns = 4,
}) {
  final max = maxColumns.clamp(2, 4);
  if (width >= TourismBreakpoints.wide) return max;
  if (width >= 800) return (max - 1).clamp(2, 3);
  return 2;
}

double tourismContentMaxWidth(double width) {
  if (width >= TourismBreakpoints.wide) return 1100;
  if (width >= TourismBreakpoints.desktop) return 960;
  return width;
}

double tourismPagePadding(double width) {
  if (width < TourismBreakpoints.phone) return 12;
  if (width < TourismBreakpoints.tablet) return 14;
  return 16;
}

bool tourismIsCompactWidth(double width) => width < TourismBreakpoints.tablet;

bool tourismIsPhoneWidth(double width) => width < TourismBreakpoints.phone;

/// Centers content and applies a max width suitable for the current screen.
class TourismResponsiveBody extends StatelessWidget {
  const TourismResponsiveBody({
    super.key,
    required this.child,
    this.maxWidth,
    this.padding,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final double? maxWidth;
  final EdgeInsetsGeometry? padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cap = maxWidth ?? tourismContentMaxWidth(w);
        final hPad = tourismPagePadding(w);
        return Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: cap),
            child: Padding(
              padding: padding ?? EdgeInsets.symmetric(horizontal: hPad),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
