import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/atmos_brand_typography.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/utils/logo_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Welcome shown after a new visitor scans an LGU or spot QR.
/// Primary path: register → verify → landing page (pending check-in kept).
class QrScanWelcomeScreen extends StatefulWidget {
  const QrScanWelcomeScreen({super.key});

  @override
  State<QrScanWelcomeScreen> createState() => _QrScanWelcomeScreenState();
}

class _QrScanWelcomeScreenState extends State<QrScanWelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  String? _headline;
  String? _subtitle;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
    _loadContext();
  }

  Future<void> _loadContext() async {
    if (FirebaseAuth.instance.currentUser != null) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/landing');
      }
      return;
    }

    final spot = await PendingSpotCheckInStorage.peek();
    final lgu = await PendingLguCheckInStorage.peek();

    if (!mounted) return;

    if (spot == null && lgu == null) {
      Navigator.pushReplacementNamed(context, '/landing');
      return;
    }

    String headline;
    String subtitle;
    if (spot != null) {
      final place = spot.spotName?.trim().isNotEmpty == true
          ? spot.spotName!.trim()
          : 'this tourist spot';
      final mun = spot.municipality?.trim().isNotEmpty == true
          ? spot.municipality!.trim()
          : null;
      headline = mun != null ? 'Welcome to $mun!' : 'Welcome, explorer!';
      subtitle =
          'You scanned the QR at $place. Create your free ATMOS-TRS account, '
          'then explore Misamis Occidental on the landing page.';
    } else {
      headline = 'Welcome to ${lgu!.displayName}!';
      subtitle =
          'Maayong pag-abot! You scanned the municipality QR for '
          '${lgu.displayName}. Register to get your tourist ID, then browse '
          'destinations on the landing page.';
    }

    setState(() {
      _headline = headline;
      _subtitle = subtitle;
      _loading = false;
    });
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _goToSignup() {
    Navigator.pushReplacementNamed(context, '/signup');
  }

  void _goToLogin() {
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 600;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF0F172A),
              Color(0xFF1E3A5F),
              Color(0xFF14532D),
            ],
          ),
        ),
        child: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : FadeTransition(
                  opacity: _fadeAnimation,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isWide ? 48 : 24,
                      vertical: 20,
                    ),
                    child: Column(
                      children: [
                        const Spacer(flex: 1),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.waving_hand_rounded,
                            color: Color(0xFFFFEDD5),
                            size: 44,
                          ),
                        ),
                        const SizedBox(height: 20),
                        TransparentLogo(
                          height: isWide ? 72 : 56,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          _headline ?? 'Welcome!',
                          textAlign: TextAlign.center,
                          style: AtmosBrandTypography.heroHeadline(
                            color: Colors.white,
                            fontSize: isWide ? 40 : 32,
                            shadows: const [
                              Shadow(
                                color: Colors.black38,
                                blurRadius: 12,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "Maayong pag-abot — we're glad you're here.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _subtitle ?? '',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.82),
                            fontSize: isWide ? 16 : 15,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.brandOrange.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppTheme.brandOrange.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.qr_code_scanner_rounded,
                                color: AppTheme.brandOrangeLight,
                                size: 28,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Your scan is saved. After you register and sign in, '
                                  'we\'ll take you to the landing page to explore.',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    fontSize: 14,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(flex: 2),
                        SizedBox(
                          width: isWide ? 360 : double.infinity,
                          child: FilledButton(
                            onPressed: _goToSignup,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.brandOrange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'Create free account',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: isWide ? 360 : double.infinity,
                          child: OutlinedButton(
                            onPressed: _goToLogin,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white54),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              'I already have an account — Sign in',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
