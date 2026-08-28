import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Primary hero clip on the public landing page.
const String kOnboardingVideoAsset =
    'assets/Onboarding_screen/tourist_destination.mp4';

/// Assets tried in order (onboarding welcome screen may use a different file).
const List<String> kOnboardingVideoAssetCandidates = [
  'assets/Onboarding_screen/wc screen.mp4',
  'assets/Onboarding_screen/wc%20screen.mp4',
  kOnboardingVideoAsset,
];

/// Owns the hero [VideoPlayerController] for onboarding and the public landing page.
class OnboardingHeroVideoData extends ChangeNotifier {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;
  bool _initializing = false;
  DateTime? _lastInitFailureTime;

  /// Set in [rememberPlaybackPositionForLanding]; applied once on landing mount.
  Duration? _resumePositionAfterLanding;

  /// User choice from onboarding/landing mute control. `null` → web starts muted.
  bool? _sessionHeroMuted;

  VideoPlayerController? get controller => _controller;
  bool get isReady => _ready;
  bool get hasFailed => _failed;

  /// True when the landing hero should paint the video layer (replaces the static photo).
  bool get showVideoOnLandingHero =>
      !_failed &&
      _controller != null &&
      _controller!.value.isInitialized;

  /// Whether hero video audio is effectively off (volume near zero).
  bool get isHeroVideoMuted {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return _effectiveHeroMuted;
    return c.value.volume < 0.01;
  }

  /// Saved mute preference for the shared hero player (onboarding → landing).
  void setSessionHeroMuted(bool muted) {
    _sessionHeroMuted = muted;
    notifyListeners();
  }

  bool get _effectiveHeroMuted => _sessionHeroMuted ?? kIsWeb;

  /// User mute/unmute for onboarding and landing hero (tap counts as gesture on web).
  Future<void> setHeroVideoMuted(bool muted) async {
    setSessionHeroMuted(muted);
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    await c.setVolume(muted ? 0.0 : 1.0);
    notifyListeners();
  }

  /// After landing mounts, apply saved preference (e.g. user unmuted on onboarding).
  Future<void> applySessionAudioToController() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    final muted = _effectiveHeroMuted;
    await c.setVolume(muted ? 0.0 : 1.0);
    if (!muted) {
      await tryUnmuteAfterUserGesture();
    }
    notifyListeners();
  }

  Future<void> toggleHeroVideoMute() async {
    await setHeroVideoMuted(!isHeroVideoMuted);
  }

  Future<void> ensureVideoPlaying() async {
    if (_controller != null && _controller!.value.isInitialized) {
      if (!_controller!.value.isPlaying) {
        await _controller!.play();
      }
      return;
    }
    if (_initializing) return;
    if (_failed) {
      final last = _lastInitFailureTime;
      if (last != null &&
          DateTime.now().difference(last) < const Duration(seconds: 3)) {
        return;
      }
      _failed = false;
      _ready = false;
      notifyListeners();
    }
    _initializing = true;

    final candidates = kOnboardingVideoAssetCandidates;
    VideoPlayerController? initializedController;
    Object? lastError;
    StackTrace? lastStack;

    for (final assetPath in candidates) {
      final c = VideoPlayerController.asset(
        assetPath,
        videoPlayerOptions: VideoPlayerOptions(
          webOptions: const VideoPlayerWebOptions(allowContextMenu: false),
        ),
      );
      try {
        debugPrint('Onboarding hero video: loading $assetPath');
        await c.initialize();
        if (!c.value.isInitialized) {
          throw StateError('Video failed to initialize: $assetPath');
        }
        initializedController = c;
        break;
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        debugPrint('Onboarding video failed for "$assetPath": $e\n$st');
        await c.dispose();
      }
    }

    try {
      if (initializedController == null) {
        throw lastError ?? StateError('No onboarding video asset initialized');
      }
      await initializedController.setLooping(true);
      final muted = _effectiveHeroMuted;
      await initializedController.setVolume(muted ? 0.0 : 1.0);
      _controller = initializedController;
      _ready = true;
      _failed = false;
      _lastInitFailureTime = null;
      notifyListeners();
      await initializedController.play();
    } catch (e, st) {
      debugPrint('Onboarding video failed after retries: $e\n$st');
      if (lastError != null && lastStack != null) {
        debugPrint('Last asset initialization error: $lastError\n$lastStack');
      }
      _lastInitFailureTime = DateTime.now();
      await initializedController?.dispose();
      _controller = null;
      _ready = true;
      _failed = true;
      notifyListeners();
    } finally {
      _initializing = false;
    }
  }

  /// Call from onboarding right before navigating to `/landing` so the same clip
  /// can [seekTo] that timestamp after the landing [VideoPlayer] attaches.
  void rememberPlaybackPositionForLanding() {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    _resumePositionAfterLanding = c.value.position;
    debugPrint('Hero video handoff: resume at $_resumePositionAfterLanding');
  }

  /// Call once after landing builds (e.g. first [postFrameCallback]).
  Future<void> resumeAfterLandingIfRemembered() async {
    final target = _resumePositionAfterLanding;
    _resumePositionAfterLanding = null;
    if (target == null) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    try {
      await c.seekTo(target);
      await c.play();
    } catch (e, st) {
      debugPrint('Hero video handoff seek failed: $e\n$st');
    }
  }

  /// Browsers only allow sound after a user gesture; call from tap/scroll handlers.
  Future<void> tryUnmuteAfterUserGesture() async {
    if (!kIsWeb) return;
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.volume >= 0.99) return;
    await c.setVolume(1.0);
    notifyListeners();
  }

  /// Call when [LandingPage] is popped so the next visit can start a fresh player.
  void releaseLandingHeroVideo() {
    _resumePositionAfterLanding = null;
    _controller?.dispose();
    _controller = null;
    _ready = false;
    _failed = false;
    _initializing = false;
    _lastInitFailureTime = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }
}

class OnboardingHeroVideo extends InheritedNotifier<OnboardingHeroVideoData> {
  const OnboardingHeroVideo({
    super.key,
    required super.notifier,
    required super.child,
  });

  static OnboardingHeroVideoData of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<OnboardingHeroVideo>();
    assert(scope != null, 'OnboardingHeroVideo not found in widget tree');
    return scope!.notifier!;
  }

  /// For [dispose] where [dependOnInheritedWidgetOfExactType] must not be used.
  static OnboardingHeroVideoData? read(BuildContext context) {
    return context.getInheritedWidgetOfExactType<OnboardingHeroVideo>()?.notifier;
  }
}

/// Full-bleed cover layout for [VideoPlayer]; shared by onboarding and landing hero.
class OnboardingVideoBackground extends StatelessWidget {
  const OnboardingVideoBackground({super.key, required this.controller});

  final VideoPlayerController controller;

  static Size _layoutSize(VideoPlayerValue value) {
    var w = value.size.width;
    var h = value.size.height;
    if (w > 0 && h > 0) return Size(w, h);
    final ar = value.aspectRatio;
    if (ar > 0 && ar.isFinite) {
      w = 1920;
      h = w / ar;
      return Size(w, h);
    }
    return const Size(1920, 1080);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final view = MediaQuery.sizeOf(context);
        var cw = constraints.maxWidth;
        var ch = constraints.maxHeight;
        if (!cw.isFinite || cw <= 0) cw = view.width;
        if (!ch.isFinite || ch <= 0) ch = view.height;

        return ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            if (!value.isInitialized) {
              return ColoredBox(
                color: Colors.black,
                child: SizedBox(width: cw, height: ch),
              );
            }
            final s = _layoutSize(value);
            return SizedBox(
              width: cw,
              height: ch,
              child: ClipRect(
                clipBehavior: Clip.hardEdge,
                child: FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: s.width,
                    height: s.height,
                    child: VideoPlayer(controller),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
