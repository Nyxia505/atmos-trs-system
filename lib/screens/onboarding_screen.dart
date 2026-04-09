import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// First-launch screen: full-screen looping video, hero copy, [Explore] → landing.
const String kOnboardingVideoAsset =
    'assets/Onboarding_screen/Top-Tourist-Destinations-in-Misamis-Occidental.mp4';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _failed = false;

  /// Web browsers block autoplay with sound; we start muted, then user enables audio.
  bool _webSoundOff = false;

  void _onControllerTick() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    final c = VideoPlayerController.asset(
      kOnboardingVideoAsset,
      videoPlayerOptions: VideoPlayerOptions(
        webOptions: const VideoPlayerWebOptions(allowContextMenu: false),
      ),
    );
    try {
      await c.initialize();
      if (!c.value.isInitialized) {
        throw StateError('Video failed to initialize');
      }
      c.addListener(_onControllerTick);
      await c.setLooping(true);
      // Web: must be muted for programmatic play() (autoplay policy). Mobile/desktop: full volume.
      if (kIsWeb) {
        await c.setVolume(0);
      } else {
        await c.setVolume(1.0);
      }
      if (!mounted) return;
      setState(() {
        _controller = c;
        _ready = true;
        _failed = false;
        _webSoundOff = kIsWeb;
      });
      await c.play();
    } catch (e, st) {
      debugPrint('Onboarding video failed: $e\n$st');
      try {
        c.removeListener(_onControllerTick);
      } catch (_) {}
      await c.dispose();
      if (!mounted) return;
      setState(() {
        _failed = true;
        _ready = true;
      });
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerTick);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _enableWebSoundIfNeeded() async {
    if (!kIsWeb || !_webSoundOff || _controller == null) return;
    await _controller!.setVolume(1.0);
    if (mounted) setState(() => _webSoundOff = false);
  }

  Future<void> _goToLanding() async {
    await _enableWebSoundIfNeeded();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed('/landing');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_ready && !_failed && _controller != null)
            Positioned.fill(child: _VideoBackground(controller: _controller!))
          else if (_failed || (_ready && _controller == null))
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.orange.shade900.withValues(alpha: 0.85),
                      Colors.black,
                    ],
                  ),
                ),
              ),
            )
          else
            const Positioned.fill(child: ColoredBox(color: Colors.black)),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.18),
                      Colors.black.withValues(alpha: 0.42),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: double.infinity,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                    Text(
                      'MABUHAY!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Sacrifice',
                        fontSize: _headlineSize(context),
                        height: 1.05,
                        color: Colors.white,
                        letterSpacing: 1,
                        shadows: const [
                          Shadow(
                            offset: Offset(0, 2),
                            blurRadius: 8,
                            color: Color(0x99000000),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'EXPLORE THE MISAMIS OCCIDENTAL',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Sansita',
                        fontSize: _subheadSize(context),
                        height: 1.15,
                        color: Colors.white,
                        letterSpacing: 0.8,
                        shadows: const [
                          Shadow(
                            offset: Offset(0, 2),
                            blurRadius: 6,
                            color: Color(0x99000000),
                          ),
                        ],
                      ),
                    ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (kIsWeb && _webSoundOff && _ready && !_failed)
            Positioned(
              left: 20,
              right: 20,
              bottom: 100,
              child: SafeArea(
                top: false,
                child: Center(
                  child: FilledButton.tonal(
                    onPressed: _enableWebSoundIfNeeded,
                    style: FilledButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.22),
                    ),
                    child: const Text('Tap for sound'),
                  ),
                ),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              minimum: const EdgeInsets.only(bottom: 24),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: OutlinedButton(
                  onPressed: _goToLanding,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white, width: 1.8),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 44,
                      vertical: 16,
                    ),
                  ),
                  child: const Text(
                    'Explore',
                    style: TextStyle(
                      fontFamily: 'Ananda Black',
                      fontSize: 20,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!_ready)
            const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            ),
        ],
      ),
    );
  }

  double _headlineSize(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 360) return 42;
    if (w < 420) return 52;
    return 58;
  }

  double _subheadSize(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 360) return 18;
    if (w < 420) return 20;
    return 22;
  }
}

class _VideoBackground extends StatelessWidget {
  const _VideoBackground({required this.controller});

  final VideoPlayerController controller;

  /// Layout size for [VideoPlayer]. Many decoders report 0×0 until the first frame;
  /// we must still give the player non-zero bounds or it never paints.
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
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        if (!value.isInitialized) {
          return const ColoredBox(color: Colors.black);
        }
        final s = _layoutSize(value);
        return ClipRect(
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
        );
      },
    );
  }
}
