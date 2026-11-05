import 'package:flutter/material.dart';

/// Official TripPlan mark from `assets/images/app_icon.png`.
///
/// The file is owned by package `trip_plan`. ATMOS also bundles a copy at the
/// same relative path so Login/Home still render when the host web asset
/// server 404s `packages/trip_plan/...` (debug) or after a stale deploy.
class TripPlanAppIcon extends StatelessWidget {
  const TripPlanAppIcon({
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  final double? width;
  final double? height;
  final BoxFit fit;

  static const String assetPath = 'assets/images/app_icon.png';

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      package: 'trip_plan',
      width: width,
      height: height,
      fit: fit,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        return Image.asset(
          assetPath,
          width: width,
          height: height,
          fit: fit,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        );
      },
    );
  }
}
