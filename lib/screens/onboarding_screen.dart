import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:atmos_trs_system/widgets/hero_video_mute_control.dart';
import 'package:atmos_trs_system/widgets/onboarding_hero_video.dart';

/// First-launch screen: hero video + welcome branding + Explore CTA.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

/// Responsive metrics for onboarding (mobile, tablet, desktop/web).
class _OnboardingLayout {
  _OnboardingLayout(BuildContext context)
      : width = MediaQuery.sizeOf(context).width,
        height = MediaQuery.sizeOf(context).height,
        padding = MediaQuery.paddingOf(context),
        isMobile = MediaQuery.sizeOf(context).width < 600,
        isTablet = MediaQuery.sizeOf(context).width >= 600 &&
            MediaQuery.sizeOf(context).width < 1100,
        isDesktop = MediaQuery.sizeOf(context).width >= 1100,
        stackLogoBelow = MediaQuery.sizeOf(context).width < 400;

  final double width;
  final double height;
  final EdgeInsets padding;
  final bool isMobile;
  final bool isTablet;
  final bool isDesktop;
  final bool stackLogoBelow;

  double get horizontalPad {
    if (isMobile) return 20;
    if (isTablet) return 40;
    return 56;
  }

  double get bottomSafePad => padding.bottom + (isMobile ? 12 : 20);

  double get welcomeFontSize {
    if (isMobile) return width < 360 ? 52 : 58;
    if (isTablet) return 68;
    return 76;
  }

  double get sublineFontSize {
    if (isMobile) return 18;
    if (isTablet) return 22;
    return 24;
  }

  double get logoHeight {
    if (isMobile) return stackLogoBelow ? 52 : 46;
    if (isTablet) return 58;
    return (width * 0.12).clamp(64.0, 96.0);
  }

  double get logoWidth => (width * 0.72).clamp(220.0, 520.0);

  double get exploreFontSize {
    if (isMobile) return 20;
    if (isTablet) return 22;
    return 24;
  }

  EdgeInsets get exploreButtonPadding => EdgeInsets.symmetric(
        horizontal: isMobile ? 36 : 48,
        vertical: isMobile ? 14 : 18,
      );

  double? get maxCtaWidth {
    if (isDesktop) return 400;
    if (isTablet) return 360;
    return null;
  }

  double get muteIconSize => isMobile ? 22 : 24;
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const String _asensoLogo =
      'assets/Onboarding_screen/asenso_logo.png';
  static const String _asensoLogoWithSpace =
      'assets/Onboarding_screen/asenso logo.png';
  static const String _asensoLogoFallback =
      'assets/images/asenso_misamis_occidental_wordmark.png';

  static const List<Shadow> _textOutline = [
    Shadow(
      color: Color(0xE6000000),
      offset: Offset(-1.5, -1.5),
      blurRadius: 0,
    ),
    Shadow(
      color: Color(0xE6000000),
      offset: Offset(1.5, -1.5),
      blurRadius: 0,
    ),
    Shadow(
      color: Color(0xE6000000),
      offset: Offset(-1.5, 1.5),
      blurRadius: 0,
    ),
    Shadow(
      color: Color(0xE6000000),
      offset: Offset(1.5, 1.5),
      blurRadius: 0,
    ),
    Shadow(
      color: Color(0x99000000),
      offset: Offset(0, 2),
      blurRadius: 6,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        final hero = OnboardingHeroVideo.of(context);
        await hero.ensureVideoPlaying();
        await hero.applySessionAudioToController();
      } catch (e, st) {
        debugPrint('Onboarding hero video: $e\n$st');
      }
    });
  }

  Future<void> _goToLanding() async {
    if (!mounted) return;
    final hero = OnboardingHeroVideo.of(context);
    final c = hero.controller;
    if (c != null && c.value.isInitialized && !c.value.isPlaying) {
      await c.play();
    }
    hero.rememberPlaybackPositionForLanding();
    if (kIsWeb) {
      await hero.ensureVideoPlaying();
      if (!hero.isHeroVideoMuted) {
        await hero.tryUnmuteAfterUserGesture();
      }
    }
    if (!mounted) return;
    final nextRoute = kIsWeb ? '/landing' : '/login';
    Navigator.of(context).pushNamedAndRemoveUntil(nextRoute, (route) => false);
  }

  Widget _buildVideoLayer(OnboardingHeroVideoData hero) {
    final c = hero.controller;
    if (hero.hasFailed || c == null || !c.value.isInitialized) {
      return Positioned.fill(
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
      );
    }
    return Positioned.fill(
      child: OnboardingVideoBackground(controller: c),
    );
  }

  Widget _asensoLogoImage({required double height, required double width}) {
    Widget load(String asset, {required Widget Function() orElse}) {
      return Image.asset(
        asset,
        height: height,
        width: width,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => orElse(),
      );
    }

    return SizedBox(
      width: width,
      height: height,
      child: load(
        _asensoLogo,
        orElse: () => load(
          _asensoLogoWithSpace,
          orElse: () => load(
            _asensoLogoFallback,
            orElse: () => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandingLines(_OnboardingLayout layout) {
    final welcomeStyle = TextStyle(
      fontFamily: 'Ananda Black',
      color: Colors.white,
      fontSize: layout.welcomeFontSize,
      fontWeight: FontWeight.bold,
      height: 1.05,
      letterSpacing: 0.4,
      shadows: _textOutline,
    );

    final sublineStyle = TextStyle(
      color: Colors.white,
      fontSize: layout.sublineFontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.2,
      height: 1.1,
      shadows: _textOutline,
    );

    final sublineText = Text('to the HOME of', style: sublineStyle);
    final logo = _asensoLogoImage(
      height: layout.logoHeight,
      width: layout.logoWidth,
    );

    final secondLine = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        sublineText,
        const SizedBox(height: 10),
        logo,
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('Welcome!', textAlign: TextAlign.center, style: welcomeStyle),
        SizedBox(height: layout.isMobile ? 10 : 16),
        secondLine,
      ],
    );
  }

  /// Branding centered in the upper area; Explore pinned to the bottom (web-safe).
  Widget _buildOnboardingOverlay(_OnboardingLayout layout) {
    return Positioned.fill(
      child: Padding(
        padding: EdgeInsets.only(top: layout.padding.top),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: layout.horizontalPad),
                child: Center(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: _buildBrandingLines(layout),
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
              minimum: EdgeInsets.only(bottom: layout.bottomSafePad),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  layout.horizontalPad,
                  12,
                  layout.horizontalPad,
                  8,
                ),
                child: _buildExploreButtonContent(layout),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomScrim(_OnboardingLayout layout) {
    final scrimHeight = layout.isMobile
        ? layout.height * 0.32
        : layout.isDesktop
            ? 240.0
            : 220.0;
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: scrimHeight.clamp(150.0, layout.height * 0.45),
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.25),
                Colors.black.withValues(alpha: 0.75),
              ],
              stops: const [0.0, 0.4, 1.0],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMuteControl(_OnboardingLayout layout) {
    return Positioned(
      left: layout.isDesktop ? 24 : 12,
      top: layout.padding.top + 8,
      child: SafeArea(
        bottom: false,
        right: false,
        child: HeroVideoMuteControl(iconSize: layout.muteIconSize),
      ),
    );
  }

  Widget _buildExploreButton(_OnboardingLayout layout, {required bool fullWidth}) {
    return OutlinedButton(
      onPressed: _goToLanding,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Colors.white, width: 2),
        shape: const StadiumBorder(),
        padding: layout.exploreButtonPadding,
        minimumSize: Size(fullWidth ? double.infinity : 0, fullWidth ? 52 : 56),
      ),
      child: Text(
        'Explore',
        style: TextStyle(
          fontFamily: 'Ananda Black',
          fontSize: layout.exploreFontSize,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildExploreButtonContent(_OnboardingLayout layout) {
    final button = _buildExploreButton(layout, fullWidth: true);
    final maxW = layout.maxCtaWidth;
    if (maxW != null) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW),
          child: SizedBox(width: double.infinity, child: button),
        ),
      );
    }
    return SizedBox(width: double.infinity, child: button);
  }

  @override
  Widget build(BuildContext context) {
    final hero = OnboardingHeroVideo.of(context);
    final ready = hero.isReady;
    final showMute =
        ready && !hero.hasFailed && hero.controller != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = _OnboardingLayout(context);

        return Scaffold(
          backgroundColor: Colors.black,
          body: ListenableBuilder(
            listenable: hero,
            builder: (context, _) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  _buildVideoLayer(hero),
                  _buildBottomScrim(layout),
                  if (ready) ...[
                    _buildOnboardingOverlay(layout),
                    if (showMute) _buildMuteControl(layout),
                  ],
                  if (!ready)
                    const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
