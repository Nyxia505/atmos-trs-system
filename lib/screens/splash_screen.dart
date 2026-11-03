import 'dart:async' show unawaited;

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/app_theme_controller.dart';
import 'package:atmos_trs_system/config/atmos_brand_typography.dart';
import 'package:atmos_trs_system/config/atmos_font_preloader.dart';
import 'package:atmos_trs_system/navigation/guest_startup_routes.dart';
import 'package:atmos_trs_system/navigation/root_navigator.dart';
import 'package:atmos_trs_system/services/startup_route_resolver.dart';
import 'package:atmos_trs_system/utils/logo_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Branded opening screen shown while session restore actually runs.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _intro,
    curve: Curves.easeOut,
  );
  late final Animation<double> _scale = Tween<double>(begin: 0.92, end: 1).animate(
    CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic),
  );

  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _intro.forward();
    unawaited(_continueStartup());
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  Future<void> _continueStartup() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Future.wait<void>([
        AppThemeController.instance.load(),
        preloadAtmosBrandFonts(),
      ]);
      var route = await StartupRouteResolver.resolveQuickInitialRoute();
      if (route == GuestStartupRoutes.splash) {
        route = GuestStartupRoutes.welcome;
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(route);
      unawaited(
        StartupRouteResolver.refineAndNavigateIfNeeded(
          route,
          navigatorKey: rootNavigatorKey,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not finish starting the app. Check your connection and retry.';
      });
    }
  }

  void _continueToWelcome() {
    Navigator.of(context).pushReplacementNamed(GuestStartupRoutes.welcome);
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: const Color(0xFFFFF8F1),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 3),
                FadeTransition(
                  opacity: _fade,
                  child: ScaleTransition(
                    scale: _scale,
                    child: Column(
                      children: [
                        const TransparentLogo(height: 128, fit: BoxFit.contain),
                        const SizedBox(height: 20),
                        Text(
                          'ATMOS TRS',
                          textAlign: TextAlign.center,
                          style: AtmosBrandTypography.authAppMark(
                            color: AppTheme.brandOrangeDark,
                            fontSize: 28,
                            letterSpacing: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Asenso Turismo Misamis Occidental Smart Tourist Registration System',
                          textAlign: TextAlign.center,
                          style: AtmosBrandTypography.meaningTagline(
                            color: const Color(0xFF7C2D12),
                            fontSize: 13,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(flex: 2),
                SizedBox(
                  height: 88,
                  child: _error != null
                      ? _ErrorActions(
                          message: _error!,
                          onRetry: _continueStartup,
                          onContinue: _continueToWelcome,
                        )
                      : _busy
                          ? const Column(
                              children: [
                                SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: AppTheme.brandOrange,
                                  ),
                                ),
                                SizedBox(height: 10),
                                Text(
                                  'Preparing your session',
                                  style: TextStyle(
                                    color: Color(0xFF9A3412),
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorActions extends StatelessWidget {
  const _ErrorActions({
    required this.message,
    required this.onRetry,
    required this.onContinue,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF9A3412),
            fontSize: 13,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(onPressed: onContinue, child: const Text('Continue')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandOrange,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ],
    );
  }
}
