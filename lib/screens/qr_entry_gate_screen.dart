import 'dart:math' as math;

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/navigation/guest_startup_routes.dart';
import 'package:atmos_trs_system/navigation/login_route_args.dart';
import 'package:atmos_trs_system/services/qr_welcome_destination_context.dart';
import 'package:atmos_trs_system/widgets/atmos_brand_logo.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Minimal QR-triggered registration entry: Log In or Create Account.
///
/// Opening this page does **not** create a visit/check-in — it only preserves
/// the pending entry-point context from the scanned attraction / LGU QR.
class QrEntryGateScreen extends StatefulWidget {
  const QrEntryGateScreen({super.key});

  @override
  State<QrEntryGateScreen> createState() => _QrEntryGateScreenState();
}

class _QrEntryGateScreenState extends State<QrEntryGateScreen> {
  static const _cream = Color(0xFFFFF7ED);
  static const _text = Color(0xFF1F2937);
  static const _muted = Color(0xFF6B7280);
  static const _logoOverlap = 36.0;

  QrWelcomeDestinationContext? _destination;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = AuthConfig.currentUserUid ?? user?.uid;
    if (uid != null && uid.isNotEmpty && user != null) {
      final role = await SessionStorage.getStoredRole();
      if (!mounted) return;
      if (role == UserRole.tourist) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          GuestStartupRoutes.qrResume,
          (r) => false,
        );
        return;
      }
    }

    final ctx = await QrWelcomeDestinationResolver.resolveFromPendingScan();
    if (!mounted) return;
    setState(() {
      _destination = ctx;
      _loading = false;
    });
  }

  void _openLogin() {
    final place = _destination?.name;
    Navigator.pushNamed(
      context,
      GuestStartupRoutes.login,
      arguments: LoginRouteArgs.forFeature(
        returnFeature: LoginRouteArgs.featureQr,
        municipalityName: place,
      ),
    );
  }

  void _openCreateAccount() {
    Navigator.pushNamed(context, GuestStartupRoutes.signupTouristQr);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: _cream,
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(child: _QrEntryTourismBackdrop()),
          SafeArea(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppTheme.brandOrange,
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        padding: EdgeInsets.fromLTRB(
                          20,
                          12,
                          20,
                          math.max(20, safeBottom) + 72 + bottomInset,
                        ),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: constraints.maxWidth,
                            minHeight: math.max(
                              0,
                              constraints.maxHeight - 24,
                            ),
                          ),
                          child: Align(
                            alignment: const Alignment(0, -0.35),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: _buildWelcomeCard(),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: _logoOverlap),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.brandOrange.withValues(alpha: 0.12),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 52, 22, 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Welcome to',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: _muted,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        fontStyle: FontStyle.italic,
                        height: 1.15,
                        letterSpacing: -0.3,
                      ),
                      children: const [
                        TextSpan(
                          text: 'ATMOS ',
                          style: TextStyle(color: _text),
                        ),
                        TextSpan(
                          text: 'TRS',
                          style: TextStyle(color: AppTheme.brandOrange),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: CustomPaint(
                      size: const Size(72, 8),
                      painter: _BrandSwooshPainter(
                        color: AppTheme.brandOrange.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _destination == null
                        ? 'Log in or create an account to continue.'
                        : 'You scanned ${_destination!.entryLabel}. '
                            'Log in or create an account to continue.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: _muted,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (_destination != null) ...[
                    const SizedBox(height: 18),
                    _MunicipalityInfoCard(destination: _destination!),
                  ],
                  const SizedBox(height: 12),
                  const _QrEntryNoticeBanner(),
                  const SizedBox(height: 20),
                  _LoginButton(onPressed: _openLogin),
                  const SizedBox(height: 12),
                  _CreateAccountButton(onPressed: _openCreateAccount),
                ],
              ),
            ),
          ),
        ),
        const Positioned(
          top: 0,
          child: AtmosBrandLogo(
            height: 72,
            padding: EdgeInsets.all(8),
            borderRadius: 18,
            elevation: 3,
            border: Border.fromBorderSide(
              BorderSide(color: Color(0xFFFFEDD5), width: 1),
            ),
          ),
        ),
      ],
    );
  }
}

class _MunicipalityInfoCard extends StatelessWidget {
  const _MunicipalityInfoCard({required this.destination});

  final QrWelcomeDestinationContext destination;

  @override
  Widget build(BuildContext context) {
    final mun = destination.municipality.trim();
    final showMunLine =
        mun.isNotEmpty && mun.toLowerCase() != destination.name.toLowerCase();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.brandOrange.withValues(alpha: 0.45),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.brandOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  color: AppTheme.brandOrange,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      destination.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: _QrEntryGateScreenState._text,
                        height: 1.25,
                      ),
                    ),
                    if (showMunLine) ...[
                      const SizedBox(height: 2),
                      Text(
                        mun,
                        style: const TextStyle(
                          fontSize: 13,
                          color: _QrEntryGateScreenState._muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ] else if (mun.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        mun,
                        style: const TextStyle(
                          fontSize: 13,
                          color: _QrEntryGateScreenState._muted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppTheme.brandOrange,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              destination.entryKindLabel,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QrEntryNoticeBanner extends StatelessWidget {
  const _QrEntryNoticeBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.brandOrange.withValues(alpha: 0.28),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppTheme.brandOrange,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Scanning this code does not check you in.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: _QrEntryGateScreenState._text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                AppTheme.brandOrange,
                AppTheme.brandOrangeLight,
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.brandOrange.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.person_outline_rounded, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Log In',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
                Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateAccountButton extends StatelessWidget {
  const _CreateAccountButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.brandOrangeDark,
          backgroundColor: Colors.white,
          side: const BorderSide(color: AppTheme.brandOrange, width: 1.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_add_alt_1_rounded, size: 22),
            SizedBox(width: 10),
            Text(
              'Create Account',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Soft cream gradient + light orange waves + bottom tourism silhouette.
class _QrEntryTourismBackdrop extends StatelessWidget {
  const _QrEntryTourismBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFFFBF5),
            Color(0xFFFFF7ED),
            Color(0xFFFFF1E0),
          ],
        ),
      ),
      child: CustomPaint(
        painter: _TourismBackdropPainter(),
        child: SizedBox.expand(),
      ),
    );
  }
}

class _TourismBackdropPainter extends CustomPainter {
  const _TourismBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Top-left soft wave.
    final topWave = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.55, 0)
      ..quadraticBezierTo(w * 0.28, h * 0.08, 0, h * 0.22)
      ..close();
    canvas.drawPath(
      topWave,
      Paint()..color = AppTheme.brandOrange.withValues(alpha: 0.10),
    );

    // Top-right accent arc.
    final topRight = Path()
      ..moveTo(w, 0)
      ..lineTo(w, h * 0.16)
      ..quadraticBezierTo(w * 0.78, h * 0.04, w * 0.62, 0)
      ..close();
    canvas.drawPath(
      topRight,
      Paint()..color = AppTheme.brandOrange.withValues(alpha: 0.07),
    );

    // Bottom landscape silhouette (mountains + palms) — decorative only.
    final groundY = h * 0.82;
    final land = Path()
      ..moveTo(0, h)
      ..lineTo(0, groundY + 28)
      ..quadraticBezierTo(w * 0.12, groundY - 8, w * 0.22, groundY + 10)
      ..quadraticBezierTo(w * 0.34, groundY + 36, w * 0.48, groundY + 6)
      ..quadraticBezierTo(w * 0.62, groundY - 18, w * 0.74, groundY + 12)
      ..quadraticBezierTo(w * 0.88, groundY + 34, w, groundY + 8)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(
      land,
      Paint()..color = AppTheme.brandOrange.withValues(alpha: 0.16),
    );

    final farHills = Path()
      ..moveTo(0, h)
      ..lineTo(0, groundY + 48)
      ..quadraticBezierTo(w * 0.25, groundY + 20, w * 0.5, groundY + 42)
      ..quadraticBezierTo(w * 0.75, groundY + 58, w, groundY + 28)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(
      farHills,
      Paint()..color = AppTheme.brandOrange.withValues(alpha: 0.10),
    );

    final palmPaint = Paint()
      ..color = AppTheme.brandOrange.withValues(alpha: 0.22)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    void drawPalm(double x, double baseY, double scale) {
      final trunk = Path()
        ..moveTo(x, baseY)
        ..quadraticBezierTo(x + 4 * scale, baseY - 18 * scale, x, baseY - 36 * scale);
      canvas.drawPath(trunk, palmPaint);
      final crownY = baseY - 36 * scale;
      for (final dx in [-14.0, -6.0, 6.0, 14.0]) {
        final leaf = Path()
          ..moveTo(x, crownY)
          ..quadraticBezierTo(
            x + dx * scale * 0.5,
            crownY - 10 * scale,
            x + dx * scale,
            crownY + 2 * scale,
          );
        canvas.drawPath(leaf, palmPaint);
      }
    }

    drawPalm(w * 0.14, h * 0.92, 1.0);
    drawPalm(w * 0.86, h * 0.91, 1.15);
    drawPalm(w * 0.78, h * 0.94, 0.75);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BrandSwooshPainter extends CustomPainter {
  const _BrandSwooshPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * 0.65)
      ..quadraticBezierTo(
        size.width * 0.5,
        -size.height * 0.2,
        size.width,
        size.height * 0.55,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _BrandSwooshPainter oldDelegate) =>
      oldDelegate.color != color;
}
