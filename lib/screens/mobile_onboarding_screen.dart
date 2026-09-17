import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/atmos_brand_typography.dart';
import 'package:atmos_trs_system/services/mobile_onboarding_storage.dart';
import 'package:atmos_trs_system/utils/logo_utils.dart';
import 'package:flutter/material.dart';

/// Three-screen intro shown on first mobile app launch before sign-in.
class MobileOnboardingScreen extends StatefulWidget {
  const MobileOnboardingScreen({super.key});

  @override
  State<MobileOnboardingScreen> createState() => _MobileOnboardingScreenState();
}

class _MobileOnboardingScreenState extends State<MobileOnboardingScreen> {
  static const Color _pageBg = Color(0xFFF8FAFC);
  static const Color _bodyText = Color(0xFF475569);
  static const Color _titleText = Color(0xFF0F172A);

  final PageController _pageController = PageController();
  int _pageIndex = 0;

  static const _pages = <_OnboardingPageData>[
    _OnboardingPageData(
      icon: Icons.travel_explore_rounded,
      iconBg: Color(0xFFFFF7ED),
      title: 'Welcome to ATMOS TRS',
      body:
          'Asenso Tourismo Misamis Occidental Smart Tourist Registration System '
          'helps you discover the province\'s destinations, plan visits, and '
          'travel smarter.',
    ),
    _OnboardingPageData(
      icon: Icons.qr_code_scanner_rounded,
      iconBg: Color(0xFFFFF7ED),
      title: 'QR Check-ins & Digital Tourist ID',
      body:
          'Scan destination QR codes for faster check-ins and receive your unique '
          'Digital Tourist ID — your key to a smoother travel experience.',
    ),
    _OnboardingPageData(
      icon: Icons.landscape_rounded,
      iconBg: Color(0xFFFFF7ED),
      title: 'Explore Misamis Occidental',
      body:
          'Browse destinations, view photos and VR tours, save your travel history, '
          'and get tourism announcements tailored to your journey.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish({required String route}) async {
    await MobileOnboardingStorage.markComplete();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, route);
  }

  void _next() {
    if (_pageIndex < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _finish(route: '/login');
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _pageIndex == _pages.length - 1;

    return Scaffold(
      backgroundColor: _pageBg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  if (!isLast)
                    TextButton(
                      onPressed: () => _finish(route: '/login'),
                      child: const Text(
                        'Skip',
                        style: TextStyle(
                          color: _bodyText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 8),
                  const Spacer(),
                  TransparentLogo(height: 36, fit: BoxFit.contain),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _pageIndex = index),
                itemBuilder: (context, index) {
                  final page = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: page.iconBg,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.brandOrange.withValues(alpha: 0.12),
                                blurRadius: 24,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Icon(
                            page.icon,
                            size: 56,
                            color: AppTheme.brandOrange,
                          ),
                        ),
                        const SizedBox(height: 36),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: AtmosBrandTypography.displayTitle(
                            color: _titleText,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          page.body,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _bodyText,
                            fontSize: 16,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (index) {
                final active = index == _pageIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active
                        ? AppTheme.brandOrange
                        : AppTheme.brandOrange.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brandOrange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    isLast ? 'Get Started' : 'Next',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
            if (isLast) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _finish(route: '/signup'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.brandOrange,
                      side: const BorderSide(color: AppTheme.brandOrange),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Create Free Account',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _finish(route: '/login'),
                child: const Text(
                  'Already have an account? Sign In',
                  style: TextStyle(
                    color: _bodyText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ] else
              const SizedBox(height: 48),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPageData {
  const _OnboardingPageData({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color iconBg;
  final String title;
  final String body;
}
