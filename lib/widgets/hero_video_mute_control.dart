import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:atmos_trs_system/widgets/onboarding_hero_video.dart';

/// Mute / unmute control for the shared hero [VideoPlayer] (onboarding + landing).
class HeroVideoMuteControl extends StatelessWidget {
  const HeroVideoMuteControl({
    super.key,
    this.iconSize = 22,
    this.forAppBar = false,
    this.alignment,
  });

  final double iconSize;

  /// `true` on the landing [AppBar] / onboarding top bar; `false` on the hero overlay.
  final bool forAppBar;

  /// When set, positions the control (e.g. onboarding top-left).
  final AlignmentGeometry? alignment;

  @override
  Widget build(BuildContext context) {
    final data = OnboardingHeroVideo.of(context);
    Widget control = ListenableBuilder(
      listenable: data,
      builder: (context, _) {
        if (data.hasFailed) return const SizedBox.shrink();

        final c = data.controller;
        if (c == null || !c.value.isInitialized) {
          return _shell(
            forAppBar: forAppBar,
            child: IconButton(
              tooltip: 'Background music',
              icon: Icon(
                Icons.volume_up_rounded,
                color: forAppBar
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.55),
                size: iconSize,
              ),
              onPressed: () => unawaited(data.ensureVideoPlaying()),
            ),
          );
        }

        return ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: c,
          builder: (context, value, _) {
            final muted = value.volume < 0.01;
            return _shell(
              forAppBar: forAppBar,
              child: IconButton(
                tooltip: muted ? 'Unmute music' : 'Mute music',
                icon: Icon(
                  muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: Colors.white,
                  size: iconSize,
                ),
                onPressed: () async {
                  final willUnmute = muted;
                  await data.setHeroVideoMuted(!muted);
                  if (willUnmute) {
                    await data.tryUnmuteAfterUserGesture();
                  }
                },
              ),
            );
          },
        );
      },
    );

    if (alignment != null) {
      return Align(alignment: alignment!, child: control);
    }
    return control;
  }

  Widget _shell({required bool forAppBar, required Widget child}) {
    if (forAppBar) {
      return Material(
        color: Colors.white.withValues(alpha: 0.18),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
    }
    return Material(
      color: Colors.black.withValues(alpha: 0.42),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
