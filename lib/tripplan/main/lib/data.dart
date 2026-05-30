import 'package:flutter/material.dart';

/// TripPlan brand colors.
class AppColors {
  static const Color primary = Color(0xFF7851A9);
  static const Color background = Color(0xFFF5F0EB);
}

/// Package-scoped assets (required when embedded in ATMOS TRS).
class TripPlanAssets {
  static const String logoPath = 'assets/images/tripplan.png';

  static Image logoImage({double? height, double? width}) {
    return Image.asset(
      logoPath,
      package: 'trip_plan',
      height: height,
      width: width,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(
        Icons.map_rounded,
        size: height ?? 48,
        color: AppColors.primary,
      ),
    );
  }
}
