import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/navigation/role_router.dart';
import 'package:atmos_trs_system/navigation/pending_checkin_navigation.dart';
import 'package:atmos_trs_system/services/emailjs_service.dart';
import 'package:atmos_trs_system/services/otp_service.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/utils/email_utils.dart';

/// Email OTP verification (EmailJS) before tourist dashboard access.
class VerifyOtpScreen extends StatefulWidget {
  const VerifyOtpScreen({super.key});

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  final _otpController = TextEditingController();
  bool _submitting = false;
  bool _resending = false;
  int _cooldown = 0;

  static const Color _primaryOrange = Color(0xFFF97316);
  static const Color _background = Color(0xFFFFF7ED);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _redirectIfVerifiedOrStaff());
  }

  /// Verified tourists and non-tourist roles should not stay on this screen.
  Future<void> _redirectIfVerifiedOrStaff() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final profile = await UserDirectoryService.getProfileByUid(
      user.uid,
      preferServer: true,
    );
    if (profile != null && !profile.isTourist) {
      if (!mounted) return;
      final route = await RoleRouter.persistSessionAndGetRoute(
        profile: profile,
        firebaseUid: user.uid,
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, route);
      return;
    }

    final already =
        await UserDirectoryService.touristEmailVerificationComplete(user.uid);
    if (!already) return;
    if (!mounted) return;

    final email = normalizeEmail(user.email ?? '');
    final p = profile ??
        AppUserProfile(
          uid: user.uid,
          email: email,
          roleRaw: 'tourist',
          isVerified: true,
        );
    final withVerified = AppUserProfile(
      uid: p.uid,
      email: p.email,
      roleRaw: p.roleRaw,
      fullName: p.fullName,
      municipality: p.municipality,
      isVerified: true,
    );
    final route = await RoleRouter.persistSessionAndGetRoute(
      profile: withVerified,
      firebaseUid: user.uid,
    );
    if (!mounted) return;
    await navigateToPendingSpotCheckInOrDashboard(
      context,
      defaultRoute: route,
      isTouristDestination: route == '/dashboard',
    );
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  bool get _isWeb => MediaQuery.sizeOf(context).width >= 768;

  Future<void> _submit() async {
    final code = _otpController.text.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      _snack('Enter the 6-digit code.', isError: true);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Session expired. Please log in again.', isError: true);
      return;
    }

    setState(() => _submitting = true);
    try {
      final outcome =
          await OtpService.verifyOtp(uid: user.uid, enteredOtp: code);
      if (!outcome.ok) {
        setState(() => _submitting = false);
        _snack(
          outcome.isExpired
              ? (outcome.message ?? 'Code expired.')
              : (outcome.message ?? 'Invalid code.'),
          isError: true,
        );
        return;
      }

      // Single-use: mark verified + remove OTP (atomic batch).
      final batch = FirebaseFirestore.instance.batch();
      final usersRef =
          FirebaseFirestore.instance.collection('users').doc(user.uid);
      final touristsRef =
          FirebaseFirestore.instance.collection('tourists').doc(user.uid);
      final otpRef =
          FirebaseFirestore.instance.collection(OtpService.collectionId).doc(user.uid);

      batch.set(usersRef, {'isVerified': true}, SetOptions(merge: true));
      final tSnap = await touristsRef.get();
      if (tSnap.exists) {
        batch.set(touristsRef, {'isVerified': true}, SetOptions(merge: true));
      }
      batch.delete(otpRef);
      await batch.commit();
      debugPrint('[OTP] verified + batch committed');

      final email = normalizeEmail(user.email ?? '');
      // Read from server + force verified so routing never loops back to /verify-otp
      // (local cache can still show isVerified: false right after the batch).
      final loaded = await UserDirectoryService.getProfileByUid(
        user.uid,
        preferServer: true,
      );
      final profileForRoute = loaded == null
          ? AppUserProfile(
              uid: user.uid,
              email: email,
              roleRaw: 'tourist',
              isVerified: true,
            )
          : AppUserProfile(
              uid: loaded.uid,
              email: loaded.email,
              roleRaw: loaded.roleRaw,
              fullName: loaded.fullName,
              municipality: loaded.municipality,
              isVerified: true,
            );

      if (loaded == null) {
        await SessionStorage.saveSession(
          user.uid,
          role: UserRole.tourist,
          email: email,
        );
        AuthConfig.currentUserUid = user.uid;
      }

      final route = await RoleRouter.persistSessionAndGetRoute(
        profile: profileForRoute,
        firebaseUid: user.uid,
      );

      if (!mounted) return;
      _snack('Email verified. Welcome!', isError: false);
      await navigateToPendingSpotCheckInOrDashboard(
        context,
        defaultRoute: route,
        isTouristDestination: route == '/dashboard',
      );
    } catch (e) {
      if (mounted) {
        _snack('Verification failed: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _resend() async {
    if (_cooldown > 0) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _snack('Session expired. Please log in again.', isError: true);
      return;
    }

    if (await UserDirectoryService.touristEmailVerificationComplete(user.uid)) {
      await _redirectIfVerifiedOrStaff();
      return;
    }

    final email = normalizeEmail(user.email ?? '');
    if (email.isEmpty) {
      _snack('No email on account.', isError: true);
      return;
    }

    setState(() => _resending = true);
    try {
      // Refresh session so Firestore sees a valid request.auth (avoids stale token on web).
      try {
        await user.reload();
        await user.getIdToken(true);
      } catch (_) {}

      final otp = OtpService.generateSixDigitOtp();
      await OtpService.saveOtp(uid: user.uid, email: email, otp: otp);
      debugPrint('[OTP] resend: saved new code to Firestore for uid=${user.uid}');

      final profile = await UserDirectoryService.getProfileByUid(user.uid);
      final name = profile?.fullName?.trim().isNotEmpty == true
          ? profile!.fullName!.trim()
          : email.split('@').first;

      final err = await EmailjsService.sendOtpEmail(
        toEmail: email,
        toName: name,
        otp: otp,
      );
      if (err != null) {
        if (mounted) _snack(err, isError: true);
        if (kDebugMode) {
          debugPrint(
            '[OTP] EmailJS failed. If 404 Account not found, confirm public key in '
            'lib/config/emailjs_config.dart or run with '
            '--dart-define=EMAILJS_ACCESS_TOKEN=<private key from EmailJS Account>.',
          );
        }
        return;
      }

      if (mounted) {
        _snack('New code sent. Check your inbox (and spam).', isError: false);
        _startCooldown(60);
      }
    } catch (e) {
      if (mounted) {
        _snack('Could not resend code: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  void _startCooldown(int seconds) {
    setState(() => _cooldown = seconds);
    Future.doWhile(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _cooldown = _cooldown - 1);
      return _cooldown > 0;
    });
  }

  void _snack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final emailText = user?.email ?? '';

    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _primaryOrange.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Enter verification code',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We sent a 6-digit code to\n$emailText',
            style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280), height: 1.4),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 28,
              letterSpacing: 8,
              fontWeight: FontWeight.w700,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              counterText: '',
              hintText: '000000',
              filled: true,
              fillColor: const Color(0xFFFFFBEB),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _primaryOrange, width: 2),
              ),
            ),
            onSubmitted: (_) => _submitting ? null : _submit(),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: _primaryOrange,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Verify & continue', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: (_resending || _cooldown > 0) ? null : _resend,
                child: _resending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _cooldown > 0
                            ? 'Resend code in ${_cooldown}s'
                            : 'Resend code',
                        style: const TextStyle(color: _primaryOrange, fontWeight: FontWeight.w600),
                      ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  await SessionStorage.clearSession();
                  if (context.mounted) {
                    Navigator.pushReplacementNamed(context, '/login');
                  }
                },
                child: const Text('Log out', style: TextStyle(color: Color(0xFF6B7280))),
              ),
            ],
          ),
        ],
      ),
    );

    final header = Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: _primaryOrange,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 36),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verify your Gmail',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Use the code from your email. It expires in 5 minutes.',
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
        ],
      ),
    );

    final stack = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        header,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: card,
        ),
      ],
    );

    return Scaffold(
      backgroundColor: _background,
      body: _isWeb
          ? Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: stack,
                    ),
                  ),
                ),
              ),
            )
          : SingleChildScrollView(child: stack),
    );
  }
}
