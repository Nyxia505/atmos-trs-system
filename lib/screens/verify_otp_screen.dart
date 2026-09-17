import 'dart:ui' show ImageFilter;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/navigation/role_router.dart';
import 'package:atmos_trs_system/navigation/pending_checkin_navigation.dart';
import 'package:atmos_trs_system/services/landing_intent_service.dart';
import 'package:atmos_trs_system/services/otp_delivery_service.dart';
import 'package:atmos_trs_system/services/announcement_notification_sync.dart';
import 'package:atmos_trs_system/services/tourist_activity_firestore_sync.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';
import 'package:atmos_trs_system/services/push_notification_service.dart';
import 'package:atmos_trs_system/services/otp_service.dart';
import 'package:atmos_trs_system/services/pending_registration_cache.dart';
import 'package:atmos_trs_system/services/pending_establishment_registration_cache.dart';
import 'package:atmos_trs_system/services/pending_lgu_registration_cache.dart';
import 'package:atmos_trs_system/services/establishment_registration_service.dart';
import 'package:atmos_trs_system/services/lgu_registration_service.dart';
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
  final List<TextEditingController> _digitControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _digitFocusNodes = [];
  bool _submitting = false;
  bool _resending = false;
  bool _autoResendAttempted = false;
  bool _forceResendOnEntry = false;
  String? _statusBanner;
  int _cooldown = 0;
  String? _contactEmail;

  static const Color _verifyOrange = Color(0xFFFF6B00);
  static const Color _textDark = Color(0xFF1C1917);
  static const Color _textMuted = Color(0xFF78716C);

  String _deliveryEmailFor(User? user) {
    final pending =
        user != null ? PendingRegistrationCache.forUid(user.uid) : null;
    if (pending != null && pending.contactEmail.isNotEmpty) {
      return pending.contactEmail;
    }
    final estPending = user != null
        ? PendingEstablishmentRegistrationCache.forUid(user.uid)
        : null;
    if (estPending != null && estPending.contactEmail.isNotEmpty) {
      return estPending.contactEmail;
    }
    final lguPending =
        user != null ? PendingLguRegistrationCache.forUid(user.uid) : null;
    if (lguPending != null && lguPending.contactEmail.isNotEmpty) {
      return lguPending.contactEmail;
    }
    if (_contactEmail != null && _contactEmail!.isNotEmpty) {
      return _contactEmail!;
    }
    return normalizeEmail(user?.email ?? '');
  }

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 6; i++) {
      final index = i;
      _digitFocusNodes.add(
        FocusNode(
          onKeyEvent: (node, event) => _onDigitKey(index, event),
        ),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map) {
        final email = args['contactEmail']?.toString().trim();
        if (email != null && email.isNotEmpty) {
          _contactEmail = normalizeEmail(email);
        }
        if (args['forceResend'] == true) {
          _forceResendOnEntry = true;
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await PendingRegistrationCache.hydrate();
      await PendingEstablishmentRegistrationCache.hydrate();
      await PendingLguRegistrationCache.hydrate();
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
      if (mounted && _digitFocusNodes.isNotEmpty) {
        _digitFocusNodes.first.requestFocus();
      }
    });
  }

  /// After login, send a fresh code if signup OTP expired or was never saved.
  Future<void> _ensureActiveOtpOnEntry() async {
    if (_autoResendAttempted) return;
    _autoResendAttempted = true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final routeArgs = ModalRoute.of(context)?.settings.arguments;
    final forceResend = _forceResendOnEntry ||
        (routeArgs is Map && routeArgs['forceResend'] == true);
    _forceResendOnEntry = false;

    if (await UserDirectoryService.touristEmailVerificationComplete(user.uid)) {
      return;
    }

    final hasActive = forceResend
        ? false
        : await OtpService.hasActiveOtp(user.uid);
    if (!mounted) return;
    if (hasActive) {
      final inbox = _deliveryEmailFor(user);
      setState(() {
        _statusBanner = 'Email is not verified. Enter the code sent to your inbox.';
      });
      _startCooldown(60);
      debugPrint('[OTP] active code exists for $inbox');
      return;
    }

    final email = _deliveryEmailFor(user);
    if (email.isEmpty) return;

    setState(() {
      _statusBanner = forceResend
          ? 'Sending a new verification code…'
          : 'Email is not verified. Sending a verification code…';
    });

    final deliveryOk = await _resend(
      isAuto: true,
      showDeliverySnack: false,
    );

    if (!mounted) return;
    setState(() {
      _statusBanner = deliveryOk
          ? 'Email is not verified. Enter the 6-digit code below.'
          : 'Could not send email. Tap Resend when available.';
    });
    if (deliveryOk) {
      _startCooldown(60);
    }
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
      // Unverified establishment / LGU self-signup must stay on OTP.
      if (!profile.isVerified &&
          (profile.isTourismEstablishment || profile.isTourismOffice)) {
        return;
      }
      if (!mounted) return;
      final route = await RoleRouter.persistSessionAndGetRoute(
        profile: profile,
        firebaseUid: user.uid,
      );
      if (!mounted) return;
      if (route == '/verify-otp') return;
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
      municipalityId: p.municipalityId,
      isVerified: true,
      status: p.status,
    );
    final route = await RoleRouter.persistSessionAndGetRoute(
      profile: withVerified,
      firebaseUid: user.uid,
    );
    if (!mounted) return;
    await _navigateAfterTouristVerification(route);
  }

  Future<void> _navigateAfterTouristVerification(String route) async {
    // After signup/OTP on the installed app: go straight to dashboard.
    // Clear VR / Trip Planner landing intent so it does not open instead.
    await LandingIntentService.clear();

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
    for (final c in _digitControllers) {
      c.dispose();
    }
    for (final f in _digitFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String _maskedEmail(String email) {
    final normalized = normalizeEmail(email);
    final at = normalized.indexOf('@');
    if (at <= 0) return normalized.isEmpty ? 'your email' : normalized;
    final local = normalized.substring(0, at);
    final domain = normalized.substring(at);
    if (local.length <= 2) {
      return '${local[0]}********$domain';
    }
    return '${local.substring(0, 2)}********$domain';
  }

  String _formatCooldown(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _applyOtpToDigits(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    for (var i = 0; i < 6; i++) {
      final next = i < digits.length ? digits[i] : '';
      if (_digitControllers[i].text != next) {
        _digitControllers[i].value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    }
    _otpController.text = digits.length > 6 ? digits.substring(0, 6) : digits;
  }

  void _syncOtpFromDigits() {
    final code = _digitControllers.map((c) => c.text).join();
    if (_otpController.text != code) {
      _otpController.text = code;
    }
  }

  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      // Paste of full/partial code into one box.
      final digits = value.replaceAll(RegExp(r'\D'), '');
      if (digits.isEmpty) {
        _digitControllers[index].clear();
        _syncOtpFromDigits();
        setState(() {});
        return;
      }
      _applyOtpToDigits(
        _digitControllers.take(index).map((c) => c.text).join() + digits,
      );
      final filled = _otpController.text.length;
      final focusIndex = filled >= 6 ? 5 : filled;
      _digitFocusNodes[focusIndex].requestFocus();
      setState(() {});
      if (_otpController.text.length == 6 && !_submitting) {
        _submit();
      }
      return;
    }

    if (value.isNotEmpty) {
      if (index < 5) {
        _digitFocusNodes[index + 1].requestFocus();
      } else {
        _digitFocusNodes[index].unfocus();
      }
    }
    _syncOtpFromDigits();
    setState(() {});
    if (_otpController.text.length == 6 && !_submitting) {
      _submit();
    }
  }

  KeyEventResult _onDigitKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    if (_digitControllers[index].text.isEmpty && index > 0) {
      _digitControllers[index - 1].clear();
      _digitFocusNodes[index - 1].requestFocus();
      _syncOtpFromDigits();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

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
      final estPending =
          PendingEstablishmentRegistrationCache.forUid(user.uid);
      final lguPending = PendingLguRegistrationCache.forUid(user.uid);

      if (lguPending != null) {
        try {
          await LguRegistrationService.completeAfterOtp(
            uid: user.uid,
            pending: lguPending,
          );
          debugPrint('[OTP] verified + LGU profile saved');
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
      } else if (estPending != null) {
        try {
          await EstablishmentRegistrationService.completeAfterOtp(
            uid: user.uid,
            pending: estPending,
          );
          debugPrint('[OTP] verified + establishment profile saved');
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
      } else if (pending != null) {
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
          final usersDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();
          final roleRaw =
              (usersDoc.data()?['role'] as String? ?? '').trim().toLowerCase();
          final isEstablishment = roleRaw == 'tourism_establishment' ||
              roleRaw == 'establishment';
          final isLgu = roleRaw == 'tourism' || roleRaw == 'tourism_office';
          final touristExists = await FirebaseFirestore.instance
              .collection('tourists')
              .doc(user.uid)
              .get()
              .then((d) => d.exists);
          if (!touristExists &&
              !isEstablishment &&
              !isLgu &&
              !usersDoc.exists) {
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
          if (isEstablishment ||
              isLgu ||
              (usersDoc.exists && !touristExists)) {
            await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
              {
                'isVerified': true,
                'firebaseUid': user.uid,
                if (email.isNotEmpty) 'email': email,
              },
              SetOptions(merge: true),
            );
            try {
              await OtpService.deleteOtp(user.uid);
            } catch (_) {}
            debugPrint('[OTP] verified staff/establishment (existing users doc)');
          } else {
            final authEmail = normalizeEmail(user.email ?? '');
            await _commitVerifiedState(user: user, email: authEmail);
            try {
              await OtpService.deleteOtp(user.uid);
            } catch (_) {}
            debugPrint('[OTP] verified + batch committed');
          }
        } else {
          final authEmail = normalizeEmail(user.email ?? '');
          await _commitVerifiedState(user: user, email: authEmail);
          try {
            await OtpService.deleteOtp(user.uid);
          } catch (_) {}
          debugPrint('[OTP] verified + batch committed');
        }
      }

      // Read from server + force verified so routing never loops back to /verify-otp
      // (local cache can still show isVerified: false right after the batch).
      final loaded = await UserDirectoryService.getProfileByUid(
        user.uid,
        preferServer: true,
      );
      final defaultRole = lguPending != null
          ? 'tourism'
          : estPending != null
              ? 'tourism_establishment'
              : 'tourist';
      final profileForRoute = loaded == null
          ? AppUserProfile(
              uid: user.uid,
              email: email,
              roleRaw: defaultRole,
              isVerified: true,
              status: (lguPending != null || estPending != null)
                  ? 'pending'
                  : '',
            )
          : AppUserProfile(
              uid: loaded.uid,
              email: loaded.email,
              roleRaw: loaded.roleRaw,
              fullName: loaded.fullName,
              municipality: loaded.municipality,
              municipalityId: loaded.municipalityId,
              isVerified: true,
              status: loaded.status,
            );

      if (loaded == null) {
        await SessionStorage.saveSession(
          user.uid,
          role: profileForRoute.isTourismOffice
              ? UserRole.tourism
              : profileForRoute.isTourismEstablishment
                  ? UserRole.tourismEstablishment
                  : UserRole.tourist,
          email: email,
          municipalityId: profileForRoute.municipalityId.isNotEmpty
              ? profileForRoute.municipalityId
              : null,
        );
        AuthConfig.currentUserUid = user.uid;
      }

      if (profileForRoute.isTourist) {
        await UserActivityService.bindToUser(user.uid);
        TouristActivityFirestoreSync.resetMergeCache();
      }

      final route = await RoleRouter.persistSessionAndGetRoute(
        profile: profileForRoute,
        firebaseUid: user.uid,
      );

      if (!mounted) return;
      _snack('Email verified. Welcome!', isError: false);
      if (profileForRoute.isTourismEstablishment ||
          route == '/establishment-dashboard') {
        Navigator.pushReplacementNamed(context, '/establishment-dashboard');
      } else if (profileForRoute.isTourismOffice ||
          route == '/lgu-dashboard') {
        Navigator.pushReplacementNamed(context, '/lgu-dashboard');
      } else {
        await _navigateAfterTouristVerification(route);
      }
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
    await SessionStorage.setTouristEmailVerified(user.uid, verified: true);
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
        if (!deliveryOk &&
            delivery.otpForDisplay != null &&
            delivery.otpForDisplay!.length == 6) {
          _applyOtpToDigits(delivery.otpForDisplay!);
          setState(() {
            _statusBanner =
                'Email not delivered. Code filled below — tap Verify.';
          });
        }
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
      // OTP is saved even when email fails — allow UI to treat resend as usable.
      return delivery.canCompleteRegistration;
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
    final masked = _maskedEmail(emailText);
    final hasPendingSignup =
        user != null && PendingRegistrationCache.hasPendingFor(user.uid);
    final width = MediaQuery.sizeOf(context).width;
    final cardMaxWidth = width >= 900 ? 440.0 : (width >= 600 ? 420.0 : 400.0);

    return PopScope(
      canPop: !hasPendingSignup,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !hasPendingSignup) return;
        await _onCancelRegistration();
      },
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(child: _OtpGradientBackdrop()),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: width < 400 ? 16 : 24,
                    vertical: 28,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: cardMaxWidth),
                    child: _OtpGlassCard(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildEnvelopeBadge(),
                          const SizedBox(height: 28),
                          Text(
                            'Verify your Email',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: width < 380 ? 24 : 28,
                              fontWeight: FontWeight.w800,
                              color: _textDark,
                              letterSpacing: -0.4,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Enter the 6-digit code sent to',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              color: _textMuted,
                              height: 1.4,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            masked,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _verifyOrange,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Code expires in ${OtpService.otpExpiryMinutes} minutes.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: _textMuted.withValues(alpha: 0.95),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (_statusBanner != null) ...[
                            const SizedBox(height: 14),
                            Text(
                              _statusBanner!,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.35,
                                color: _statusBanner!
                                        .toLowerCase()
                                        .contains('could not')
                                    ? Colors.red.shade700
                                    : _verifyOrange,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (_resending) ...[
                            const SizedBox(height: 12),
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: _verifyOrange,
                              ),
                            ),
                          ],
                          const SizedBox(height: 28),
                          _buildOtpBoxes(width),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton(
                              onPressed: _submitting ||
                                      _otpController.text.length != 6
                                  ? null
                                  : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: _verifyOrange,
                                disabledBackgroundColor:
                                    _verifyOrange.withValues(alpha: 0.45),
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: _submitting
                                    ? const SizedBox(
                                        key: ValueKey('loading'),
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        key: ValueKey('label'),
                                        'Verify',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          _buildResendRow(),
                          const SizedBox(height: 8),
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
                                Navigator.pushReplacementNamed(
                                  context,
                                  '/login',
                                );
                              }
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: _textMuted,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            child: Text(
                              hasPendingSignup ? 'Cancel signup' : 'Log out',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnvelopeBadge() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.92, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _verifyOrange.withValues(alpha: 0.18),
              const Color(0xFFFFEDD5),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: _verifyOrange.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: const Icon(
          Icons.mark_email_unread_rounded,
          size: 42,
          color: _verifyOrange,
        ),
      ),
    );
  }

  Widget _buildOtpBoxes(double screenWidth) {
    final gap = screenWidth < 360 ? 6.0 : 10.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxW =
            ((constraints.maxWidth - gap * 5) / 6).clamp(40.0, 56.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(6, (index) {
                return Padding(
              padding: EdgeInsets.only(left: index == 0 ? 0 : gap),
              child: SizedBox(
                width: boxW,
                height: boxW + 4,
                child: AnimatedBuilder(
                  animation: _digitFocusNodes[index],
                  builder: (context, _) {
                    final focused = _digitFocusNodes[index].hasFocus;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: focused
                            ? [
                                BoxShadow(
                                  color:
                                      _verifyOrange.withValues(alpha: 0.22),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: TextField(
                        controller: _digitControllers[index],
                        focusNode: _digitFocusNodes[index],
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        textAlignVertical: TextAlignVertical.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: _textDark,
                          height: 1.1,
                        ),
                        maxLength: 6,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          counterText: '',
                          filled: true,
                          fillColor: const Color(0xFFFFFBF7),
                          contentPadding: EdgeInsets.zero,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: Colors.black.withValues(alpha: 0.08),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: _verifyOrange,
                              width: 2,
                            ),
                          ),
                        ),
                        onChanged: (v) => _onDigitChanged(index, v),
                        onTap: () {
                          _digitControllers[index].selection =
                              TextSelection(
                            baseOffset: 0,
                            extentOffset:
                                _digitControllers[index].text.length,
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildResendRow() {
    final canResend = !_resending && _cooldown <= 0;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          "Didn't receive the code? ",
          style: TextStyle(
            fontSize: 14,
            color: _textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (_cooldown > 0)
          Text(
            'Resend in ${_formatCooldown(_cooldown)}',
            style: TextStyle(
              fontSize: 14,
              color: _textMuted.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
            ),
          )
        else
          TextButton(
            onPressed: canResend ? () => _resend() : null,
            style: TextButton.styleFrom(
              foregroundColor: _verifyOrange,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              _resending ? 'Sending…' : 'Resend Code',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }
}

class _OtpGradientBackdrop extends StatelessWidget {
  const _OtpGradientBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFFF7ED),
            Color(0xFFFFE7CC),
            Color(0xFFFFF4E6),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: _BlurOrb(
              size: 220,
              color: const Color(0xFFFF6B00).withValues(alpha: 0.14),
            ),
          ),
          Positioned(
            bottom: -40,
            left: -50,
            child: _BlurOrb(
              size: 200,
              color: const Color(0xFFFDBA74).withValues(alpha: 0.22),
            ),
          ),
          Positioned(
            top: MediaQuery.sizeOf(context).height * 0.35,
            right: 40,
            child: _BlurOrb(
              size: 120,
              color: const Color(0xFFFED7AA).withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _BlurOrb extends StatelessWidget {
  const _BlurOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}

class _OtpGlassCard extends StatelessWidget {
  const _OtpGlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(28, 36, 28, 24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.7),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 32,
                offset: const Offset(0, 16),
              ),
              BoxShadow(
                color: const Color(0xFFFF6B00).withValues(alpha: 0.06),
                blurRadius: 40,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
