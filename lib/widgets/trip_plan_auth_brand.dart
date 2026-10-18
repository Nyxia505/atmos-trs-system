import 'package:flutter/material.dart';

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/tripplan.png',
          package: 'trip_plan',
          width: compact ? 72 : logoSize,
          height: compact ? 72 : logoSize,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
        SizedBox(height: compact ? 6 : 8),
        Text(
          'TripPlan',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'HolidayCalling',
            color: titleColor,
            fontSize: compact ? 32 : titleSize,
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
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
