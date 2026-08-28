import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/navigation/role_router.dart';
import 'package:atmos_trs_system/navigation/pending_checkin_navigation.dart';
import 'package:atmos_trs_system/services/otp_delivery_service.dart';
import 'package:atmos_trs_system/services/announcement_notification_sync.dart';
import 'package:atmos_trs_system/services/tourist_activity_firestore_sync.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';
import 'package:atmos_trs_system/services/push_notification_service.dart';
import 'package:atmos_trs_system/services/otp_service.dart';
import 'package:atmos_trs_system/services/pending_registration_cache.dart';
import 'package:atmos_trs_system/services/registration_completion_service.dart';
import 'package:atmos_trs_system/services/registration_rollback_service.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/utils/email_utils.dart';

/// OTP verification before tourist dashboard: code in Firestore + on-device notification
/// (EmailJS email is optional backup).
class VerifyOtpScreen extends StatefulWidget {
  const VerifyOtpScreen({super.key});

  @override
  State<VerifyOtpScreen> createState() => _VerifyOtpScreenState();
}

class _VerifyOtpScreenState extends State<VerifyOtpScreen> {
  final _otpController = TextEditingController();
  bool _submitting = false;
  bool _resending = false;
  bool _autoResendAttempted = false;
  String? _statusBanner;
  int _cooldown = 0;
  String? _contactEmail;

  static const Color _background = Color(0xFFFFF7ED);

  String _deliveryEmailFor(User? user) {
    final pending =
        user != null ? PendingRegistrationCache.forUid(user.uid) : null;
    if (pending != null && pending.contactEmail.isNotEmpty) {
      return pending.contactEmail;
    }
    if (_contactEmail != null && _contactEmail!.isNotEmpty) {
      return _contactEmail!;
    }
    return normalizeEmail(user?.email ?? '');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        final email = args['contactEmail']?.toString().trim();
        if (email != null && email.isNotEmpty) {
          _contactEmail = normalizeEmail(email);
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await PendingRegistrationCache.hydrate();
      final u = FirebaseAuth.instance.currentUser;
      if (u != null) {
        await ensureEmailOtpNotificationSupport();
        await syncFcmTokenToUserDoc(u.uid);
        await AnnouncementNotificationSync.syncPublishedAnnouncementsToLocal(
          userId: u.uid,
        );
      }
      if (!mounted) return;
      await _redirectIfVerifiedOrStaff();
      if (!mounted) return;
      await _ensureActiveOtpOnEntry();
    });
  }

  /// After login, send a fresh code if signup OTP expired or was never saved.
  Future<void> _ensureActiveOtpOnEntry() async {
    if (_autoResendAttempted) return;
    _autoResendAttempted = true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (await UserDirectoryService.touristEmailVerificationComplete(user.uid)) {
      return;
    }

    final hasActive = await OtpService.hasActiveOtp(user.uid);
    if (!mounted) return;
    if (hasActive) {
      final inbox = _deliveryEmailFor(user);
      setState(() {
        _statusBanner = inbox.isNotEmpty
            ? 'Enter the 6-digit code sent to $inbox. On this phone, check your '
                'notification shade first, then your email inbox (not Spam). '
                'Valid for ${OtpService.otpExpiryMinutes} minutes.'
            : 'Enter the 6-digit code sent to your email. Check your notification '
                'shade first, then your inbox (not Spam). Valid for '
                '${OtpService.otpExpiryMinutes} minutes.';
      });
      return;
    }

    final email = _deliveryEmailFor(user);
    if (email.isEmpty) return;

    setState(() {
      _statusBanner = 'Sending a new verification code to $email…';
    });

    final deliveryOk = await _resend(
      isAuto: true,
      showDeliverySnack: false,
    );

    if (!mounted) return;
    setState(() {
      if (deliveryOk) {
        _statusBanner = 'We sent a new code to $email. Check your phone notification '
            'first, then your email inbox (not Spam).';
      } else {
        _statusBanner =
            'Could not send the verification email. Please try Resend code again.';
      }
    });
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
      preferLandingAfterPendingCheckIn: true,
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
      try {
        await user.reload();
        await user.getIdToken(true);
      } catch (_) {}

      final outcome =
          await OtpService.verifyOtp(uid: user.uid, enteredOtp: code);
      if (!outcome.ok) {
        setState(() {
          _submitting = false;
        });
        _snack(outcome.message ?? 'Verification failed.', isError: true);
        return;
      }

      final email = _deliveryEmailFor(user);
      final pending = PendingRegistrationCache.forUid(user.uid);

      if (pending != null) {
        try {
          await RegistrationCompletionService.completeAfterOtp(
            uid: user.uid,
            pending: pending,
          );
          debugPrint('[OTP] verified + deferred signup profile saved');
        } on FirebaseException catch (e) {
          if (mounted) {
            _snack(_formatFirestoreFailure(e), isError: true);
          }
          return;
        } catch (e) {
          if (mounted) {
            _snack('Could not save your account: $e', isError: true);
          }
          return;
        }
      } else {
        if (Firebase.apps.isNotEmpty) {
          final touristExists = await FirebaseFirestore.instance
              .collection('tourists')
              .doc(user.uid)
              .get()
              .then((d) => d.exists);
          if (!touristExists) {
            if (mounted) {
              _snack(
                'Registration data is missing. Please sign up again.',
                isError: true,
              );
            }
            await RegistrationRollbackService.rollback(user.uid);
            if (mounted) {
              Navigator.pushReplacementNamed(context, '/signup');
            }
            return;
          }
        }
        final authEmail = normalizeEmail(user.email ?? '');
        await _commitVerifiedState(user: user, email: authEmail);
        try {
          await OtpService.deleteOtp(user.uid);
        } catch (_) {}
        debugPrint('[OTP] verified + batch committed');
      }

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

      await UserActivityService.bindToUser(user.uid);
      TouristActivityFirestoreSync.resetMergeCache();

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
        preferLandingAfterPendingCheckIn: true,
      );
    } on FirebaseException catch (e) {
      if (mounted) {
        final msg = _formatFirestoreFailure(e);
        _snack(msg, isError: true);
      }
    } catch (e) {
      if (mounted) {
        _snack('Verification failed: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _formatFirestoreFailure(FirebaseException e) {
    final code = e.code;
    final detail = e.message?.trim();
    if (code == 'permission-denied') {
      return 'Could not save verification (permission denied). '
          'Log out, sign in again, then tap Resend code.';
    }
    if (code == 'unavailable' || code == 'deadline-exceeded') {
      return 'Network error saving verification. Check connection and try again.';
    }
    if (detail != null && detail.isNotEmpty) {
      return 'Could not save verification [$code]: $detail';
    }
    return 'Could not save verification [$code]. Try again or contact support.';
  }

  /// Marks tourist verified in Firestore and removes the OTP doc (single-use).
  Future<void> _commitVerifiedState({
    required User user,
    required String email,
  }) async {
    final batch = FirebaseFirestore.instance.batch();
    final usersRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);
    final touristsRef =
        FirebaseFirestore.instance.collection('tourists').doc(user.uid);
    final otpRef =
        FirebaseFirestore.instance.collection(OtpService.collectionId).doc(user.uid);

    batch.set(
      usersRef,
      {
        'isVerified': true,
        'firebaseUid': user.uid,
        if (email.isNotEmpty) 'email': email,
        'role': 'tourist',
      },
      SetOptions(merge: true),
    );
    batch.set(
      touristsRef,
      {'isVerified': true, if (email.isNotEmpty) 'email': email},
      SetOptions(merge: true),
    );
    batch.delete(otpRef);
    await batch.commit();
  }

  /// Sends a new OTP. Returns true if email or SMS delivery succeeded.
  Future<bool> _resend({
    bool isAuto = false,
    bool showDeliverySnack = true,
  }) async {
    if (!isAuto && _cooldown > 0) return false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (showDeliverySnack) {
        _snack('Session expired. Please log in again.', isError: true);
      }
      return false;
    }

    if (await UserDirectoryService.touristEmailVerificationComplete(user.uid)) {
      await _redirectIfVerifiedOrStaff();
      return true;
    }

    final email = _deliveryEmailFor(user);
    if (email.isEmpty) {
      if (showDeliverySnack) {
        _snack('No email on account.', isError: true);
      }
      return false;
    }

    if (mounted) {
      setState(() => _resending = true);
    }
    try {
      // Refresh session so Firestore sees a valid request.auth (avoids stale token on web).
      try {
        await user.reload();
        await user.getIdToken(true);
      } catch (_) {}

      final otp = OtpService.generateSixDigitOtp();
      await OtpService.saveOtp(uid: user.uid, email: email, otp: otp);
      debugPrint('[OTP] resend: saved new code to Firestore for uid=${user.uid}');

      final pending = PendingRegistrationCache.forUid(user.uid);
      final profile = await UserDirectoryService.getProfileByUid(user.uid);
      final name = pending?.touristData['fullName']?.toString().trim() ??
          (profile?.fullName?.trim().isNotEmpty == true
              ? profile!.fullName!.trim()
              : email.split('@').first);

      var mobile = pending?.touristData['mobile']?.toString().trim() ?? '';
      if (mobile.isEmpty && Firebase.apps.isNotEmpty) {
        try {
          final tourist = await FirebaseFirestore.instance
              .collection('tourists')
              .doc(user.uid)
              .get();
          mobile = tourist.data()?['mobile']?.toString().trim() ?? '';
        } catch (_) {}
      }

      final delivery = await OtpDeliveryService.deliverVerificationCode(
        uid: user.uid,
        email: email,
        displayName: name,
        otp: otp,
        mobile: mobile,
        notifyOnThisDevice: !kIsWeb,
        trySms: false,
        otpAlreadyInFirestore: true,
      );
      final deliveryOk = delivery.emailSent;
      if (!delivery.emailSent) {
        debugPrint('[OTP] resend email failed: ${delivery.emailError}');
      }

      if (mounted) {
        if (showDeliverySnack) {
          _snack(
            delivery.messageForUser(email),
            isError: !deliveryOk,
          );
        }
        if (!isAuto) {
          _startCooldown(60);
        }
      }
      return deliveryOk;
    } on FirebaseException catch (e) {
      if (mounted) {
        final msg = _formatFirestoreFailure(e);
        if (showDeliverySnack) {
          _snack(msg, isError: true);
        }
        setState(() {
          if (isAuto && _statusBanner != null) {
            _statusBanner = msg;
          }
        });
      }
      return false;
    } catch (e) {
      if (mounted && showDeliverySnack) {
        _snack('Could not resend code: $e', isError: true);
      }
      return false;
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

  Future<bool> _onCancelRegistration() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return true;
    final pending = PendingRegistrationCache.forUid(user.uid);
    if (pending == null) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel registration?'),
        content: const Text(
          'Your account will not be saved. You can sign up again anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Cancel signup',
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;

    await RegistrationRollbackService.rollback(user.uid);
    await SessionStorage.clearSession();
    AuthConfig.currentUserUid = null;
  if (mounted) {
      Navigator.pushReplacementNamed(context, '/signup');
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final emailText = _deliveryEmailFor(user);
    final hasPendingSignup =
        user != null && PendingRegistrationCache.hasPendingFor(user.uid);

    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.brandOrange.withValues(alpha: 0.12)),
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
            kIsWeb
                ? 'We sent a 6-digit code to your email:\n$emailText'
                : 'Check SMS on the mobile number you registered, or open your '
                    'email ($emailText) on your own phone.',
            style: const TextStyle(fontSize: 14, color: Color(0xFF6B7280), height: 1.4),
          ),
          if (_statusBanner != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.brandOrange.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: AppTheme.brandOrange,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _statusBanner!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF374151),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_resending && _autoResendAttempted) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(minHeight: 2),
          ],
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
                borderSide: BorderSide(color: AppTheme.brandOrange, width: 2),
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
                backgroundColor: AppTheme.brandOrange,
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
                        style: TextStyle(color: AppTheme.brandOrange, fontWeight: FontWeight.w600),
                      ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () async {
                  if (hasPendingSignup) {
                    await _onCancelRegistration();
                    return;
                  }
                  await FirebaseAuth.instance.signOut();
                  await SessionStorage.clearSession();
                  AuthConfig.currentUserUid = null;
                  if (context.mounted) {
                    Navigator.pushReplacementNamed(context, '/login');
                  }
                },
                child: Text(
                  hasPendingSignup ? 'Cancel signup' : 'Log out',
                  style: const TextStyle(color: Color(0xFF6B7280)),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final header = Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppTheme.brandOrange,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kIsWeb ? 'Verify your Gmail' : 'Verify your account',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            kIsWeb
                ? 'Use the code from your email inbox (not Spam). '
                    'It expires in ${OtpService.otpExpiryMinutes} minutes.'
                : 'Check your phone notification first, then your email inbox '
                    '(not Spam). Expires in ${OtpService.otpExpiryMinutes} minutes.',
            style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
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

    return PopScope(
      canPop: !hasPendingSignup,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !hasPendingSignup) return;
        await _onCancelRegistration();
      },
      child: Scaffold(
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
    ),
    );
  }
}
