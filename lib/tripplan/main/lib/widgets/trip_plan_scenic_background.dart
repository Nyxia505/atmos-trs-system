import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../data.dart';

/// Optional shared hero player passed from ATMOS landing when opening TripPlan.
class TripPlanSharedHeroVideo extends InheritedWidget {
  const TripPlanSharedHeroVideo({
    super.key,
    required this.controller,
    required super.child,
  });

  final VideoPlayerController? controller;

  static VideoPlayerController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<TripPlanSharedHeroVideo>()
        ?.controller;
  }

  static VideoPlayerController? read(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<TripPlanSharedHeroVideo>()
        ?.controller;
  }

  @override
  bool updateShouldNotify(TripPlanSharedHeroVideo oldWidget) {
    return oldWidget.controller != controller;
  }
}

/// Scenic backdrop for TripPlan login / loading (shared video or branded image).
class TripPlanScenicBackground extends StatelessWidget {
  const TripPlanScenicBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final shared = TripPlanSharedHeroVideo.maybeOf(context);
    if (shared != null && shared.value.isInitialized) {
      return SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: shared.value.size.width,
            height: shared.value.size.height,
            child: VideoPlayer(shared),
          ),
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1F2937), Color(0xFF111827)],
        ),
      ),
      child: Center(
        child: Opacity(
          opacity: 0.35,
          child: TripPlanAssets.logoImage(height: 120),
        ),
      ),
    );
  }
}
