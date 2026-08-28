import 'package:flutter/material.dart';
import 'package:trip_plan/data.dart';
import 'package:video_player/video_player.dart';

class TripPlanScenicBackground extends StatelessWidget {
  const TripPlanScenicBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0D2818),
            Color(0xFF1B4332),
            Color(0xFF2D6A4F),
          ],
        ),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Icon(
          Icons.landscape_rounded,
          size: 120,
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
    );
  }
}

/// Wraps TripPlan UI with an optional shared hero video from ATMOS landing.
class TripPlanSharedHeroVideo extends StatelessWidget {
  const TripPlanSharedHeroVideo({
    super.key,
    required this.child,
    this.controller,
  });

  final Widget child;
  final VideoPlayerController? controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c != null && c.value.isInitialized) {
      return Stack(
        fit: StackFit.expand,
        children: [
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: c.value.size.width,
              height: c.value.size.height,
              child: VideoPlayer(c),
            ),
          ),
          Container(color: Colors.black.withValues(alpha: 0.45)),
          child,
        ],
      );
    }
    return child;
  }
}

/// Loading indicator color helper for TripPlan splash.
Color get tripPlanAccentColor => AppColors.primary;
