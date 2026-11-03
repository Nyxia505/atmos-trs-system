import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/atmos_brand_typography.dart';
import 'package:atmos_trs_system/navigation/guest_startup_routes.dart';
import 'package:atmos_trs_system/services/mobile_onboarding_storage.dart';
import 'package:atmos_trs_system/utils/logo_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Photo-driven welcome shown on first mobile app launch before sign-in.
class MobileOnboardingScreen extends StatefulWidget {
  const MobileOnboardingScreen({super.key});

  @override
  State<MobileOnboardingScreen> createState() => _MobileOnboardingScreenState();
}

class _MobileOnboardingScreenState extends State<MobileOnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  late final AnimationController _zoom = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..forward();
  int _pageIndex = 0;
  bool _precached = false;

  static const _pages = <_OnboardingPageData>[
    _OnboardingPageData(
      image: 'assets/images/oroquieta City plaza.jpeg',
      chipIcon: Icons.explore_rounded,
      chipLabel: 'Destinations',
      title: 'Explore Misamis Occidental',
      body: 'Discover tourist attractions, cultural landmarks, and beautiful '
          'destinations across the province.',
    ),
    _OnboardingPageData(
      image: 'assets/mockup/vr tour.png',
      chipIcon: Icons.travel_explore_rounded,
      chipLabel: 'Virtual Tour',
      title: 'Experience Virtual Tours',
      body: 'Preview featured destinations and discover what makes each place '
          'worth visiting.',
    ),
    _OnboardingPageData(
      image: 'assets/images/ae_qr_scan_phone.png',
      chipIcon: Icons.qr_code_scanner_rounded,
      chipLabel: 'QR Check-in',
      title: 'Scan, Check In, and Explore',
      body: 'Use your tourist QR code to check in at participating destinations '
          'with GPS verification.',
    ),
  ];

  bool get _isLast => _pageIndex == _pages.length - 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    for (final page in _pages) {
      precacheImage(AssetImage(page.image), context).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _zoom.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await MobileOnboardingStorage.markComplete();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(
      GuestStartupRoutes.welcome,
      (route) => false,
    );
  }

  void _back() {
    if (_pageIndex > 0) {
      _goTo(_pageIndex - 1);
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _goTo(int index) {
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_pageIndex];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: _pages.length,
              onPageChanged: (index) => setState(() => _pageIndex = index),
              itemBuilder: (context, index) =>
                  _PhotoBackground(image: _pages[index].image, zoom: _zoom),
            ),
            const IgnorePointer(child: _ScrimGradient()),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTopBar(),
                    const Spacer(),
                    IgnorePointer(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        transitionBuilder: (child, animation) {
                          final slide = Tween<Offset>(
                            begin: const Offset(0, 0.12),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: slide,
                              child: child,
                            ),
                          );
                        },
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.bottomLeft,
                          children: [
                            ...previous,
                            if (current != null) current,
                          ],
                        ),
                        child: _PageText(
                          key: ValueKey(_pageIndex),
                          page: page,
                        ),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _buildDots(),
                    const SizedBox(height: 22),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.bottomCenter,
                      child: _isLast ? _buildGetStarted() : _buildNext(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: TransparentLogo(height: 28, fit: BoxFit.contain),
        ),
        const Spacer(),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _isLast ? 0 : 1,
          child: IgnorePointer(
            ignoring: _isLast,
            child: TextButton(
              onPressed: _finish,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.black.withValues(alpha: 0.25),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: const StadiumBorder(),
              ),
              child: const Text(
                'Skip',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDots() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Step ${_pageIndex + 1} of ${_pages.length}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.86),
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: List.generate(_pages.length, (index) {
            final active = index == _pageIndex;
            return GestureDetector(
              onTap: () => _goTo(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.only(right: 8),
                width: active ? 28 : 10,
                height: 8,
                decoration: BoxDecoration(
                  color: active
                      ? AppTheme.brandOrange
                      : Colors.white.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  ButtonStyle get _primaryStyle => FilledButton.styleFrom(
        backgroundColor: AppTheme.brandOrange,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      );

  Widget _buildNext() {
    return Row(
      children: [
        if (_pageIndex > 0 || Navigator.of(context).canPop()) ...[
          Expanded(child: _buildBackButton()),
          const SizedBox(width: 10),
        ],
        Expanded(
          flex: _pageIndex > 0 ? 2 : 1,
          child: FilledButton(
            onPressed: () => _goTo(_pageIndex + 1),
            style: _primaryStyle,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Next'),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBackButton() {
    return OutlinedButton(
      onPressed: _back,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.85)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
      child: const Text('Back'),
    );
  }

  Widget _buildGetStarted() {
    return Row(
      children: [
        Expanded(child: _buildBackButton()),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: FilledButton(
            onPressed: _finish,
            style: _primaryStyle,
            child: const Text('Get Started'),
          ),
        ),
      ],
    );
  }
}

class _PhotoBackground extends StatelessWidget {
  const _PhotoBackground({required this.image, required this.zoom});

  final String image;
  final Animation<double> zoom;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedBuilder(
        animation: zoom,
        builder: (context, child) {
          final t = Curves.easeOut.transform(zoom.value);
          return Transform.scale(scale: 1.0 + 0.06 * t, child: child);
        },
        child: Image.asset(
          image,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.brandOrange,
                  AppTheme.gradientDarkBlue,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScrimGradient extends StatelessWidget {
  const _ScrimGradient();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.2, 0.45, 0.75, 1.0],
          colors: [
            Colors.black.withValues(alpha: 0.45),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.72),
            Colors.black.withValues(alpha: 0.92),
          ],
        ),
      ),
    );
  }
}

class _PageText extends StatelessWidget {
  const _PageText({super.key, required this.page});

  final _OnboardingPageData page;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.brandOrange,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(page.chipIcon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                page.chipLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          page.title,
          style: AtmosBrandTypography.displayTitle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          page.body,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.88),
            fontSize: 15.5,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.image,
    required this.chipIcon,
    required this.chipLabel,
    required this.title,
    required this.body,
  });

  final String image;
  final IconData chipIcon;
  final String chipLabel;
  final String title;
  final String body;
}
