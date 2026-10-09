import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

/// OTP verification before tourist dashboard: code is emailed to the user
/// (open Inbox; Spam only if missing). No on-device OTP popup during signup.
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
  bool _otpAlreadySentFromSignup = false;
  bool _emailDeliveryFailed = false;
  String? _statusBanner;
  int _cooldown = 0;
  /// Seconds remaining until the active OTP expires (null = unknown / none).
  int? _expirySecondsLeft;
  Timer? _expiryTicker;
  String? _contactEmail;
  /// Set after a successful code check; the "Verified!" view runs it on
  /// "Go to Dashboard".
  Future<void> Function()? _goToDashboard;
  bool _openingDashboard = false;
  String? _verifiedName;
  String _verifiedEmail = '';
  bool _verifiedIsStaff = false;
  bool _verifiedAwaitingApproval = false;

  static const Color _verifyOrange = Color(0xFFFF6B00);
  static const Color _textDark = Color(0xFF1C1917);
  static const Color _textMuted = Color(0xFF78716C);

  String _deliveryEmailFor(User? user) {
    final deferred = PendingRegistrationCache.current;
    if (deferred != null &&
        deferred.authDeferred &&
        deferred.contactEmail.isNotEmpty) {
      return deferred.contactEmail;
    }
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

  /// Unfinished tourist signup (including Auth-deferred).
  PendingRegistration? _pendingTourist() {
    final deferred = PendingRegistrationCache.current;
    if (deferred != null && deferred.authDeferred) return deferred;
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) return PendingRegistrationCache.forUid(user.uid);
    if (_contactEmail != null) {
      return PendingRegistrationCache.forContactEmail(_contactEmail!);
    }
    return PendingRegistrationCache.current;
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
        if (args['otpAlreadySent'] == true || args['fromSignup'] == true) {
          _otpAlreadySentFromSignup = true;
        }
        if (args['emailDeliveryFailed'] == true) {
          _emailDeliveryFailed = true;
        }
      }
      unawaited(_bootstrapVerifyScreen());
    });
  }

  Future<void> _bootstrapVerifyScreen() async {
    await PendingRegistrationCache.hydrate();
    await PendingEstablishmentRegistrationCache.hydrate();
    await PendingLguRegistrationCache.hydrate();
    final pendingTourist = _pendingTourist();
    final u = FirebaseAuth.instance.currentUser;

    // Deferred Auth: no Firebase user yet — stay on OTP with local pending.
    if (u == null && pendingTourist != null && pendingTourist.authDeferred) {
      await ensureEmailOtpNotificationSupport();
      if (!mounted) return;
      await _ensureActiveOtpOnEntry();
      if (mounted && _digitFocusNodes.isNotEmpty) {
        _digitFocusNodes.first.requestFocus();
      }
      return;
    }

    if (u != null) {
      // Preserve signup OTP ASAP — do not wait on announcement sync first.
      if (_otpAlreadySentFromSignup) {
        await ensureEmailOtpNotificationSupport();
        if (!mounted) return;
        await _redirectIfVerifiedOrStaff();
        if (!mounted) return;
        await _ensureActiveOtpOnEntry();
        if (mounted && _digitFocusNodes.isNotEmpty) {
          _digitFocusNodes.first.requestFocus();
        }
        // No FCM sync until verified — prevents stub users/{uid} before OTP.
        return;
      }
      await ensureEmailOtpNotificationSupport();
      // Defer FCM token write until after OTP (see RegistrationCompletionService).
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
  }

  /// After login, send a fresh code if signup OTP expired or was never saved.
  /// When coming from signup with [otpAlreadySent], keep the existing code —
  /// do not generate a new OTP that would invalidate the notification/email.
  Future<void> _ensureActiveOtpOnEntry() async {
    if (_autoResendAttempted) return;
    _autoResendAttempted = true;

    final deferred = _pendingTourist();
    final user = FirebaseAuth.instance.currentUser;

    final routeArgs = ModalRoute.of(context)?.settings.arguments;
    final forceResend = _forceResendOnEntry ||
        (routeArgs is Map && routeArgs['forceResend'] == true);
    _forceResendOnEntry = false;

    final otpAlreadySent = _otpAlreadySentFromSignup ||
        (routeArgs is Map &&
            (routeArgs['otpAlreadySent'] == true ||
                routeArgs['fromSignup'] == true));

    // --- Deferred Auth path (no Firebase user yet) ---
    if (user == null && deferred != null && deferred.authDeferred) {
      final otpKey = deferred.otpKey;
      var hasActive = forceResend
          ? false
          : await OtpService.hasActiveOtp(otpKey);
      if (!hasActive && !forceResend && otpAlreadySent) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (!mounted) return;
        hasActive = await OtpService.hasActiveOtp(otpKey);
      }
      if (!mounted) return;
      final inbox = deferred.contactEmail;
      if (hasActive) {
        setState(() {
          _statusBanner = _emailDeliveryFailed
              ? OtpDeliveryResult.deliveryUnconfirmedMessage(inbox)
              : OtpDeliveryResult.deliveryPendingMessage(inbox);
        });
        await _syncExpiryFromStore(otpKey);
        return;
      }
      final deliveryOk = await _resend(
        isAuto: true,
        showDeliverySnack: false,
      );
      if (!mounted) return;
      setState(() {
        _emailDeliveryFailed = !deliveryOk;
        _statusBanner = deliveryOk
            ? OtpDeliveryResult.deliveryPendingMessage(inbox)
            : OtpDeliveryResult.deliveryUnconfirmedMessage(inbox);
      });
      return;
    }

    if (user == null) return;

    if (await UserDirectoryService.touristEmailVerificationComplete(user.uid)) {
      return;
    }

    var hasActive = forceResend
        ? false
        : await OtpService.hasActiveOtp(user.uid);
    // Brief retry — Firestore may lag right after signup save.
    if (!hasActive && !forceResend && otpAlreadySent) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      hasActive = await OtpService.hasActiveOtp(user.uid);
    }
    if (!mounted) return;
    if (hasActive) {
      final inbox = _deliveryEmailFor(user);
      setState(() {
        // Active OTP means signup already stored a code — never scare with
        // "email does not exist" even if delivery confirmation timed out.
        _statusBanner = _emailDeliveryFailed
            ? OtpDeliveryResult.deliveryUnconfirmedMessage(inbox)
            : 'Open your email Inbox for the 6-digit code, then enter it below '
                '(check Spam only if it is missing).';
      });
      await _syncExpiryFromStore(user.uid);
      debugPrint('[OTP] active code exists for $inbox (preserved)');
      return;
    }

    // From signup but no active OTP found — recover with one resend only.
    final email = _deliveryEmailFor(user);
    if (email.isEmpty) return;

    setState(() {
      _statusBanner = forceResend
          ? 'Sending a new verification code to your email…'
          : otpAlreadySent
              ? 'Refreshing your verification email…'
              : 'Sending your verification code to email…';
    });

    final deliveryOk = await _resend(
      isAuto: true,
      showDeliverySnack: false,
    );

    if (!mounted) return;
    setState(() {
      _emailDeliveryFailed = !deliveryOk;
      _statusBanner = deliveryOk
          ? 'Check your email Inbox for the 6-digit code '
              '(Spam only if missing), then enter it below.'
          : OtpDeliveryResult.deliveryUnconfirmedMessage(email);
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

  void _showVerified(
    Future<void> Function() goToDashboard, {
    required AppUserProfile profile,
    required String email,
  }) {
    _expiryTicker?.cancel();
    _expiryTicker = null;
    FocusManager.instance.primaryFocus?.unfocus();
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    final isStaff = profile.isTourismEstablishment || profile.isTourismOffice;
    setState(() {
      _goToDashboard = goToDashboard;
      _submitting = false;
      _verifiedName = profile.fullName?.trim().split(RegExp(r'\s+')).first;
      _verifiedEmail = email;
      _verifiedIsStaff = isStaff;
      _verifiedAwaitingApproval =
          isStaff && profile.status.trim().toLowerCase() == 'pending';
    });
  }

  Future<void> _onGoToDashboard() async {
    final go = _goToDashboard;
    if (go == null || _openingDashboard) return;
    setState(() => _openingDashboard = true);
    try {
      await go();
    } finally {
      if (mounted) setState(() => _openingDashboard = false);
    }
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
    _expiryTicker?.cancel();
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

  void _startExpiryCountdown(DateTime? expiresAt) {
    _expiryTicker?.cancel();
    if (expiresAt == null) {
      if (mounted) setState(() => _expirySecondsLeft = null);
      return;
    }
    void tick() {
      if (!mounted) return;
      final left = expiresAt.difference(DateTime.now()).inSeconds;
      setState(() => _expirySecondsLeft = left > 0 ? left : 0);
      if (left <= 0) {
        _expiryTicker?.cancel();
        _expiryTicker = null;
      }
    }

    tick();
    _expiryTicker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  Future<void> _syncExpiryFromStore(String uid) async {
    final expiresAt = await OtpService.fetchActiveOtpExpiresAt(uid);
    if (!mounted) return;
    if (expiresAt != null) {
      _startExpiryCountdown(expiresAt);
    } else {
      // Fresh save may not be readable yet — fall back to local TTL.
      _startExpiryCountdown(
        DateTime.now().add(
          const Duration(minutes: OtpService.otpExpiryMinutes),
        ),
      );
    }
  }

  String _expiryLabel() {
    final left = _expirySecondsLeft;
    if (left == null) {
      return 'Code expires in ${OtpService.otpExpiryMinutes} minutes.';
    }
    if (left <= 0) {
      return 'Code expired — tap Resend Code.';
    }
    return 'Code expires in ${_formatCooldown(left)}';
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

    final deferredPending = _pendingTourist();
    final user = FirebaseAuth.instance.currentUser;

    // --- Deferred Auth: verify local OTP, then create Firebase Auth + profile ---
    if (user == null &&
        deferredPending != null &&
        deferredPending.authDeferred) {
      setState(() => _submitting = true);
      try {
        final outcome = await OtpService.verifyOtpPreAuth(
          pendingId: deferredPending.otpKey,
          enteredOtp: code,
        );
        if (!outcome.ok) {
          setState(() => _submitting = false);
          _snack(outcome.message ?? 'Verification failed.', isError: true);
          return;
        }

        final createdUser =
            await RegistrationCompletionService.createAuthAndCompleteAfterOtp(
          pending: deferredPending,
        );
        debugPrint('[OTP] verified + Auth created uid=${createdUser.uid}');

        final email = deferredPending.contactEmail;
        final loaded = await UserDirectoryService.getProfileByUid(
          createdUser.uid,
          preferServer: true,
        );
        final profileForRoute = loaded == null
            ? AppUserProfile(
                uid: createdUser.uid,
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
                municipalityId: loaded.municipalityId,
                isVerified: true,
                status: loaded.status,
              );

        AuthConfig.currentUserUid = createdUser.uid;
        await SessionStorage.saveSession(
          createdUser.uid,
          role: UserRole.tourist,
          email: deferredPending.authEmail,
        );

        final route = await RoleRouter.persistSessionAndGetRoute(
          profile: profileForRoute,
          firebaseUid: createdUser.uid,
        );
        if (!mounted) return;
        _showVerified(
          () => _navigateAfterTouristVerification(route),
          profile: profileForRoute.fullName?.trim().isNotEmpty == true
              ? profileForRoute
              : AppUserProfile(
                  uid: profileForRoute.uid,
                  email: profileForRoute.email,
                  roleRaw: profileForRoute.roleRaw,
                  fullName:
                      deferredPending.touristData['fullName']?.toString(),
                  isVerified: true,
                  status: profileForRoute.status,
                ),
          email: email,
        );
      } catch (e) {
        debugPrint('[OTP] deferred Auth complete failed: $e');
        if (mounted) {
          setState(() => _submitting = false);
          _snack(
            e is StateError ? e.message : 'Could not finish signup: $e',
            isError: true,
          );
        }
      }
      return;
    }

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
              .then((d) {
            if (!d.exists || d.data() == null) return false;
            final data = d.data()!;
            final email = data['email']?.toString().trim() ?? '';
            final touristId = data['touristId']?.toString().trim() ?? '';
            return email.isNotEmpty || touristId.isNotEmpty;
          });
          // FCM-only stubs (users doc without role) do not count as registration.
          final usersIsStubOnly = usersDoc.exists && roleRaw.isEmpty;
          if (!touristExists &&
              !isEstablishment &&
              !isLgu &&
              (!usersDoc.exists || usersIsStubOnly)) {
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
      _showVerified(() async {
        if (profileForRoute.isTourismEstablishment ||
            route == '/establishment-dashboard') {
          Navigator.pushReplacementNamed(context, '/establishment-dashboard');
        } else if (profileForRoute.isTourismOffice ||
            route == '/lgu-dashboard') {
          Navigator.pushReplacementNamed(context, '/lgu-dashboard');
        } else {
          await _navigateAfterTouristVerification(route);
        }
      }, profile: profileForRoute, email: email);
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

    final deferred = _pendingTourist();
    final user = FirebaseAuth.instance.currentUser;

    // Deferred Auth: local OTP + EmailJS only (no Cloud Function Auth).
    if (user == null && deferred != null && deferred.authDeferred) {
      final email = deferred.contactEmail;
      if (email.isEmpty) {
        if (showDeliverySnack) {
          _snack('No email on pending signup.', isError: true);
        }
        return false;
      }
      if (mounted) setState(() => _resending = true);
      try {
        final otp = OtpService.generateSixDigitOtp();
        await OtpService.saveOtpPreAuth(
          pendingId: deferred.otpKey,
          email: email,
          otp: otp,
        );
        final name =
            deferred.touristData['fullName']?.toString().trim().isNotEmpty ==
                    true
                ? deferred.touristData['fullName'].toString().trim()
                : email.split('@').first;
        final mobile = deferred.touristData['mobile']?.toString().trim() ?? '';
        final delivery = await OtpDeliveryService.deliverVerificationCode(
          uid: deferred.otpKey,
          email: email,
          displayName: name,
          otp: otp,
          mobile: mobile,
          notifyOnThisDevice: false,
          trySms: false,
          otpAlreadyInFirestore: true,
        );
        if (mounted) {
          final ok = delivery.canCompleteRegistration;
          setState(() {
            _emailDeliveryFailed =
                !delivery.emailSent && !delivery.emailDeliveryPending;
            _statusBanner = delivery.emailSent || delivery.emailDeliveryPending
                ? OtpDeliveryResult.deliveryPendingMessage(email)
                : (ok
                    ? OtpDeliveryResult.deliveryUnconfirmedMessage(email)
                    : OtpDeliveryResult.emailDoesNotExistMessage(email));
          });
          if (showDeliverySnack) {
            _snack(
              delivery.messageForUser(email),
              isError: !ok,
            );
          }
          if (!isAuto) _startCooldown(60);
          await _syncExpiryFromStore(deferred.otpKey);
        }
        return delivery.canCompleteRegistration;
      } catch (e) {
        if (mounted && showDeliverySnack) {
          _snack('Could not resend code: $e', isError: true);
        }
        return false;
      } finally {
        if (mounted) setState(() => _resending = false);
      }
    }

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
        notifyOnThisDevice: false,
        trySms: false,
        otpAlreadyInFirestore: true,
      );
      final deliveryOk = delivery.canCompleteRegistration;
      if (!delivery.emailSent) {
        debugPrint('[OTP] resend email failed: ${delivery.emailError}');
      }

      if (mounted) {
        if (delivery.emailDeliveryPending || delivery.emailSent) {
          setState(() {
            _emailDeliveryFailed = false;
            _statusBanner =
                'Check your email Inbox for the 6-digit code, then enter it below.';
          });
        } else if (!delivery.emailSent && deliveryOk) {
          setState(() {
            _emailDeliveryFailed = true;
            _statusBanner =
                OtpDeliveryResult.deliveryUnconfirmedMessage(email);
          });
        } else if (!deliveryOk) {
          setState(() {
            _emailDeliveryFailed = true;
            _statusBanner =
                OtpDeliveryResult.emailDoesNotExistMessage(email);
          });
        } else {
          setState(() {
            _emailDeliveryFailed = false;
            _statusBanner =
                'Check your email Inbox for the 6-digit code, then enter it below.';
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
        await _syncExpiryFromStore(user.uid);
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

  Future<void> _onEditSignupDetails() async {
    await PendingRegistrationCache.hydrate();
    final pending = _pendingTourist();
    if (pending == null) {
      if (mounted) {
        _snack('No unfinished signup to edit.', isError: true);
      }
      return;
    }
    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      '/signup',
      arguments: <String, dynamic>{'editPending': true},
    );
  }

  Future<bool> _onCancelRegistration() async {
    await PendingRegistrationCache.hydrate();
    final pending = _pendingTourist();
    if (pending == null) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel registration?'),
        content: const Text(
          'Your unfinished signup will be discarded. You can sign up again anytime.\n\n'
          'If you only mistyped your email, use “Edit details” instead.',
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

    if (pending.authDeferred) {
      try {
        await OtpService.deleteOtp(pending.otpKey);
      } catch (_) {}
      await PendingRegistrationCache.clear();
    } else {
      await RegistrationRollbackService.rollback(pending.uid);
    }
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
    final pendingTourist = _pendingTourist();
    final hasPendingSignup = pendingTourist != null;
    final width = MediaQuery.sizeOf(context).width;
    final cardMaxWidth = width >= 900 ? 440.0 : (width >= 600 ? 420.0 : 400.0);

    final verified = _goToDashboard != null;

    return PopScope(
      canPop: !hasPendingSignup && !verified,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || verified || !hasPendingSignup) return;
        // System back → review/edit filled signup (not cancel).
        await _onEditSignupDetails();
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
                      child: verified
                          ? _buildVerifiedView(width)
                          : Column(
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
                            'Open your email Inbox for the 6-digit code, '
                            'then enter it below (Spam only if missing).',
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
                            _expiryLabel(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: (_expirySecondsLeft != null &&
                                      _expirySecondsLeft! <= 0)
                                  ? Colors.red.shade700
                                  : _textMuted.withValues(alpha: 0.95),
                              fontWeight: FontWeight.w600,
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
                                color: _isDeliveryFailureBanner(_statusBanner!)
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
                          if (hasPendingSignup) ...[
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: _onEditSignupDetails,
                              style: TextButton.styleFrom(
                                foregroundColor: _verifyOrange,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              child: const Text(
                                'Wrong email? Edit details',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
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

  static const Color _successGreen = Color(0xFF16A34A);

  Widget _buildVerifiedView(double width) {
    final name = _verifiedName;
    final greeting = name != null && name.isNotEmpty
        ? 'Welcome to ATMOS-TRS, $name!'
        : 'Welcome to ATMOS-TRS!';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _VerifiedSuccessBadge(),
        const SizedBox(height: 18),
        _FadeSlideIn(
          delay: const Duration(milliseconds: 350),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: _successGreen.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _successGreen.withValues(alpha: 0.25),
              ),
            ),
            child: const Text(
              'ACCOUNT VERIFIED',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: _successGreen,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _FadeSlideIn(
          delay: const Duration(milliseconds: 450),
          child: Text(
            'Verified!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: width < 380 ? 28 : 32,
              fontWeight: FontWeight.w800,
              color: _textDark,
              letterSpacing: -0.6,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _FadeSlideIn(
          delay: const Duration(milliseconds: 550),
          child: Text(
            '$greeting\nYou have successfully verified your account.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              color: _textMuted,
              height: 1.45,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        if (_verifiedEmail.isNotEmpty) ...[
          const SizedBox(height: 16),
          _FadeSlideIn(
            delay: const Duration(milliseconds: 650),
            child: _buildVerifiedEmailChip(),
          ),
        ],
        const SizedBox(height: 22),
        _FadeSlideIn(
          delay: const Duration(milliseconds: 750),
          child: _buildWhatsNextPanel(),
        ),
        const SizedBox(height: 24),
        _FadeSlideIn(
          delay: const Duration(milliseconds: 850),
          child: _buildGoToDashboardButton(),
        ),
        const SizedBox(height: 12),
        _FadeSlideIn(
          delay: const Duration(milliseconds: 900),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 14,
                color: _textMuted.withValues(alpha: 0.8),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Use this email and your password next time you log in.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: _textMuted.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVerifiedEmailChip() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_rounded, size: 18, color: _successGreen),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _verifiedEmail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: _textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWhatsNextPanel() {
    final List<(IconData, String, String)> items;
    if (_verifiedAwaitingApproval) {
      items = const [
        (
          Icons.mark_email_read_rounded,
          'Email confirmed',
          'Your sign-in email is now verified.',
        ),
        (
          Icons.hourglass_top_rounded,
          'Waiting for approval',
          'Some features stay locked until your registration is approved.',
        ),
        (
          Icons.notifications_active_rounded,
          'We will notify you',
          'Check your dashboard for your approval status.',
        ),
      ];
    } else if (_verifiedIsStaff) {
      items = const [
        (
          Icons.mark_email_read_rounded,
          'Email confirmed',
          'Your sign-in email is now verified.',
        ),
        (
          Icons.dashboard_customize_rounded,
          'Open your dashboard',
          'Manage check-ins, records and reports in one place.',
        ),
      ];
    } else {
      items = const [
        (
          Icons.qr_code_scanner_rounded,
          'Check in with QR',
          'Scan the QR code at attractions and tourism desks.',
        ),
        (
          Icons.hotel_rounded,
          'Confirm your stays',
          'Scan your accommodation QR so staff can confirm your stay.',
        ),
        (
          Icons.explore_rounded,
          'Explore Misamis Occidental',
          'Discover destinations across all 17 LGUs.',
        ),
      ];
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _verifyOrange.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "WHAT'S NEXT",
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
              color: _verifyOrange.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 10),
          for (final (icon, title, subtitle) in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: _verifyOrange.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(icon, size: 20, color: _verifyOrange),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: _textMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGoToDashboardButton() {
    final enabled = !_openingDashboard;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.7,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFFFF8A3D), _verifyOrange],
          ),
          boxShadow: [
            BoxShadow(
              color: _verifyOrange.withValues(alpha: 0.32),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? _onGoToDashboard : null,
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: Center(
                child: _openingDashboard
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Go to Dashboard',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                        ],
                      ),
              ),
            ),
          ),
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

  bool _isDeliveryFailureBanner(String text) {
    final t = text.toLowerCase();
    return t.contains('sorry') ||
        t.contains('does not exist') ||
        t.contains("couldn't confirm") ||
        t.contains('could not') ||
        t.contains('not delivered');
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

/// Fades + slides [child] up once, starting after [delay].
class _FadeSlideIn extends StatelessWidget {
  const _FadeSlideIn({required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  static const Duration _animDuration = Duration(milliseconds: 420);

  @override
  Widget build(BuildContext context) {
    final total = delay + _animDuration;
    final start = delay.inMilliseconds / total.inMilliseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 14),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// Success badge: pop-in circle, self-drawing check, confetti burst and
/// soft pulsing rings.
class _VerifiedSuccessBadge extends StatefulWidget {
  const _VerifiedSuccessBadge();

  @override
  State<_VerifiedSuccessBadge> createState() => _VerifiedSuccessBadgeState();
}

class _VerifiedSuccessBadgeState extends State<_VerifiedSuccessBadge>
    with TickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  static const double _size = 150;
  static const double _core = 92;
  static const Color _orange = Color(0xFFFF6B00);

  @override
  void initState() {
    super.initState();
    _intro.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) _pulse.repeat();
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size,
      height: _size,
      child: AnimatedBuilder(
        animation: Listenable.merge([_intro, _pulse]),
        builder: (context, _) {
          final pop = Curves.elasticOut.transform(
            const Interval(0, 0.6).transform(_intro.value),
          );
          final check = Curves.easeOutCubic.transform(
            const Interval(0.35, 0.75).transform(_intro.value),
          );
          final burst = Curves.easeOutCubic.transform(
            const Interval(0.4, 1).transform(_intro.value),
          );
          return Stack(
            alignment: Alignment.center,
            children: [
              for (final offset in const [0.0, 0.5])
                _buildPulseRing((_pulse.value + offset) % 1),
              CustomPaint(
                size: const Size.square(_size),
                painter: _ConfettiBurstPainter(progress: burst),
              ),
              Transform.scale(
                scale: pop,
                child: Container(
                  width: _core,
                  height: _core,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFFA05C), _orange],
                    ),
                    border: Border.all(color: Colors.white, width: 4),
                    boxShadow: [
                      BoxShadow(
                        color: _orange.withValues(alpha: 0.35),
                        blurRadius: 26,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: CustomPaint(
                    painter: _CheckMarkPainter(progress: check),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPulseRing(double t) {
    if (!_pulse.isAnimating) return const SizedBox.shrink();
    final scale = 1 + t * 0.6;
    return Opacity(
      opacity: (1 - t) * 0.45,
      child: Container(
        width: _core * scale,
        height: _core * scale,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _orange.withValues(alpha: 0.6), width: 2),
        ),
      ),
    );
  }
}

class _CheckMarkPainter extends CustomPainter {
  _CheckMarkPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final path = Path()
      ..moveTo(size.width * 0.29, size.height * 0.52)
      ..lineTo(size.width * 0.44, size.height * 0.66)
      ..lineTo(size.width * 0.72, size.height * 0.37);
    final metric = path.computeMetrics().first;
    final partial = metric.extractPath(0, metric.length * progress);
    canvas.drawPath(
      partial,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.09
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckMarkPainter old) => old.progress != progress;
}

class _ConfettiBurstPainter extends CustomPainter {
  _ConfettiBurstPainter({required this.progress});

  final double progress;

  static const List<Color> _colors = [
    Color(0xFFFF6B00),
    Color(0xFFFDBA74),
    Color(0xFF16A34A),
    Color(0xFFFACC15),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    final center = size.center(Offset.zero);
    final opacity = (1 - progress).clamp(0.0, 1.0);
    const count = 12;
    for (var i = 0; i < count; i++) {
      final angle = (i / count) * 2 * math.pi - math.pi / 2;
      final reach = size.width * (i.isEven ? 0.46 : 0.38);
      final distance = size.width * 0.3 + (reach - size.width * 0.3) * progress;
      final pos = center + Offset(math.cos(angle), math.sin(angle)) * distance;
      final paint = Paint()
        ..color = _colors[i % _colors.length].withValues(alpha: opacity);
      final r = (i.isEven ? 4.0 : 3.0) * (1 - progress * 0.4);
      if (i % 3 == 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: pos, width: r * 2.2, height: r * 1.2),
            const Radius.circular(1.5),
          ),
          paint,
        );
      } else {
        canvas.drawCircle(pos, r, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_ConfettiBurstPainter old) => old.progress != progress;
}
