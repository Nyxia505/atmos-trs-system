import 'package:flutter/material.dart';
import 'package:trip_plan/widgets/trip_plan_app_icon.dart';

/// Trip Planner mark used on login and tourist signup opened from Itinerary.
class TripPlanAuthBrand extends StatelessWidget {
  const TripPlanAuthBrand({
    super.key,
    this.logoSize = 96,
    this.titleSize = 40,
    this.onDark = true,
    this.compact = false,
  });

  final double logoSize;
  final double titleSize;
  final bool onDark;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final titleColor = onDark ? Colors.white : const Color(0xFF1C1C1C);
    final subColor = onDark
        ? Colors.white.withValues(alpha: 0.92)
        : const Color(0xFF666666);
    final icon = compact ? 72.0 : logoSize;
    final title = compact ? 32.0 : titleSize;
    final sub = compact ? 12.0 : 13.0;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TripPlanAppIcon(
          width: icon,
          height: icon,
        ),
        SizedBox(height: compact ? 6 : 8),
        Text(
          'Trip Plan',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'HolidayCalling',
            color: titleColor,
            fontSize: title,
            fontWeight: FontWeight.w400,
            height: 0.95,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Misamis Occidental Tourism Trip Planner',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: subColor,
            fontSize: sub,
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final boundedH = constraints.hasBoundedHeight &&
            constraints.maxHeight.isFinite &&
            constraints.maxHeight < double.infinity;
        final boundedW = constraints.hasBoundedWidth &&
            constraints.maxWidth.isFinite &&
            constraints.maxWidth < double.infinity;

        if (!boundedH && !boundedW) return content;

        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: boundedW ? constraints.maxWidth : 360,
            ),
            child: content,
          ),
        );
      },
    );
  }
}
