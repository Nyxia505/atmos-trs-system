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
  static const _bg = Color(0xFFFFF7ED);
  static const _card = Colors.white;
  static const _text = Color(0xFF1F2937);
  static const _muted = Color(0xFF6B7280);

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
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppTheme.brandOrange),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(
                          child: AtmosBrandLogo(
                            height: 44,
                            padding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            borderRadius: 12,
                            elevation: 2,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
                          decoration: BoxDecoration(
                            color: _card,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFFFEDD5)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Welcome to ATMOS TRS',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: _text,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _destination == null
                                    ? 'Log in or create an account to continue.'
                                    : 'You scanned ${_destination!.entryLabel}. '
                                        'Log in or create an account to continue.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.4,
                                  color: _muted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (_destination != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFF7ED),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppTheme.brandOrange
                                          .withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        _destination!.name,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                          color: _text,
                                        ),
                                      ),
                                      if (_destination!.municipality
                                          .trim()
                                          .isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          _destination!.municipality,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            color: _muted,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      Text(
                                        _destination!.entryKindLabel,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.brandOrangeDark,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              const Text(
                                'Scanning this code does not check you in.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 22),
                              FilledButton(
                                onPressed: _openLogin,
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppTheme.brandOrange,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Log In',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              OutlinedButton(
                                onPressed: _openCreateAccount,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppTheme.brandOrangeDark,
                                  side: const BorderSide(
                                    color: AppTheme.brandOrange,
                                    width: 1.4,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Create Account',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
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
    );
  }
}
