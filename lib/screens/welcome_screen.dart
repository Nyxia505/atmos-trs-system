import 'dart:async';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/atmos_brand_typography.dart';
import 'package:atmos_trs_system/navigation/guest_startup_routes.dart';
import 'package:atmos_trs_system/services/mobile_onboarding_storage.dart';
import 'package:atmos_trs_system/utils/logo_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tourism welcome shown to unauthenticated mobile users after splash.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  static const _heroes = <String>[
    'assets/images/oroquieta City plaza.jpeg',
    'assets/images/Cotta Fort & Shrine.jpg',
    'assets/images/Baliangao.png',
  ];

  final PageController _pageController = PageController();
  Timer? _autoPlay;
  int _page = 0;
  bool _precached = false;

  @override
  void initState() {
    super.initState();
    _autoPlay = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pageController.hasClients) return;
      final next = (_page + 1) % _heroes.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_precached) return;
    _precached = true;
    for (final asset in _heroes) {
      precacheImage(AssetImage(asset), context).catchError((_) {});
    }
  }

  @override
  void dispose() {
    _autoPlay?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _getStarted() async {
    final done = await MobileOnboardingStorage.isComplete();
    if (!mounted) return;
    if (done) {
      Navigator.pushNamed(context, GuestStartupRoutes.login);
      return;
    }
    Navigator.pushNamed(context, GuestStartupRoutes.onboarding);
  }

  void _logIn() {
    Navigator.pushNamed(context, GuestStartupRoutes.login);
  }

  void _signUp() {
    Navigator.pushNamed(context, GuestStartupRoutes.signupTourist);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _page = index),
              itemCount: _heroes.length,
              itemBuilder: (context, index) {
                return Image.asset(
                  _heroes[index],
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const ColoredBox(
                    color: Color(0xFF7C2D12),
                  ),
                );
              },
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.28, 0.55, 1.0],
                  colors: [
                    Color(0x66000000),
                    Color(0x14000000),
                    Color(0x99000000),
                    Color(0xE6000000),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(22, 8, 22, 16 + bottomInset * 0.15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const TransparentLogo(height: 28),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Discover Misamis Occidental',
                      style: AtmosBrandTypography.displayTitle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Explore beautiful destinations, experience local culture, and enjoy smarter tourism with ATMOS TRS.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 15.5,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: List.generate(_heroes.length, (index) {
                        final active = index == _page;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          margin: const EdgeInsets.only(right: 6),
                          width: active ? 22 : 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: active
                                ? AppTheme.brandOrange
                                : Colors.white.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: _getStarted,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.brandOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      child: const Text('Get Started'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _logIn,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white, width: 1.4),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      child: const Text('Log In'),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: _signUp,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                        ),
                      ),
                      child: const Text('Sign Up'),
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
}
