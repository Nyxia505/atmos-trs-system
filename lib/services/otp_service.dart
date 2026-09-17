import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:atmos_trs_system/services/otp_local_fallback_cache.dart';

/// Firestore collection for pending email OTPs (single-use, [otpExpiryMinutes] TTL).
///
/// Document ID = Firebase Auth UID (one pending OTP per user).
class OtpService {
  OtpService._();

  static const String collectionId = 'email_otps';
  static const int otpExpiryMinutes = 15;

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  static bool get _ready {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Generates a cryptographically random 6-digit numeric string.
  static String generateSixDigitOtp() {
    final r = Random.secure();
    return (100000 + r.nextInt(900000)).toString();
  }

  /// Refreshes the ID token so Firestore rules see [request.auth.uid].
  static Future<void> refreshAuthTokenForUid(String uid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != uid) {
      throw StateError('Not signed in as uid=$uid');
    }
    await user.getIdToken(true);
  }

  /// Persists OTP and expiry; overwrites any previous OTP for this [uid].
  /// Falls back to Cloud Function, then same-device local storage if Firestore rules
  /// are not deployed yet.
  ///
  /// Throws only when cloud + function + local device storage all fail.
  static Future<void> saveOtp({
    required String uid,
    required String email,
    required String otp,
  }) async {
    if (!_ready) throw StateError('Firebase not initialized');
    final now = DateTime.now();
    final expires = now.add(const Duration(minutes: otpExpiryMinutes));

    final payload = <String, dynamic>{
      'email': email,
      'otp': otp,
      'firebaseUid': uid,
      'expiresAt': Timestamp.fromDate(expires),
      'createdAt': FieldValue.serverTimestamp(),
    };

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await refreshAuthTokenForUid(uid);
        await _writeOtpDoc(uid: uid, payload: payload);
        await OtpLocalFallbackCache.clear(uid);
        debugPrint('[OTP] saved to Firestore email_otps/$uid');
        return;
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied' && attempt < 1) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          continue;
        }
        if (e.code != 'permission-denied') rethrow;
        debugPrint('[OTP] client write denied — trying saveEmailOtp Cloud Function');
        break;
      }
    }

    final savedViaFunction = await _saveOtpViaCloudFunction(
      email: email,
      otp: otp,
      expiresAt: expires,
    );
    if (savedViaFunction) {
      await OtpLocalFallbackCache.clear(uid);
      debugPrint('[OTP] saved via saveEmailOtp Cloud Function');
      return;
    }

    try {
      await OtpLocalFallbackCache.save(
        uid: uid,
        email: email,
        otp: otp,
        expiresAt: expires,
      );
      debugPrint(
        '[OTP] saved on this device only — publish firestore.rules or deploy '
        'saveEmailOtp to sync OTP to cloud',
      );
    } catch (e) {
      debugPrint('[OTP] local fallback save failed: $e');
      throw FirebaseException(
        plugin: 'otp',
        code: 'otp-save-failed',
        message:
            'Could not save verification code to cloud or this device. '
            'Publish firestore.rules in Firebase Console, then try again.',
      );
    }
  }

  static Future<void> _writeOtpDoc({
    required String uid,
    required Map<String, dynamic> payload,
  }) async {
    await _db.collection(collectionId).doc(uid).set(
          payload,
          SetOptions(merge: true),
        );
  }

  static Future<bool> _saveOtpViaCloudFunction({
    required String email,
    required String otp,
    required DateTime expiresAt,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await user.getIdToken(true);
    }
    try {
      final callable = _functions.httpsCallable('saveEmailOtp');
      await callable.call<void>({
        'email': email,
        'otp': otp,
        'expiresAtMs': expiresAt.millisecondsSinceEpoch,
      });
      return true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[OTP] saveEmailOtp CF: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[OTP] saveEmailOtp error: $e');
      return false;
    }
  }

  /// Validates [enteredOtp] against Firestore; on success returns true (caller
  /// should delete OTP + set [isVerified] in a batch).
  static Future<OtpVerifyOutcome> verifyOtp({
    required String uid,
    required String enteredOtp,
  }) async {
    if (!_ready) {
      return OtpVerifyOutcome.error('Firebase not initialized');
    }

    try {
      await refreshAuthTokenForUid(uid);
    } catch (e) {
      debugPrint('[OTP] verify token refresh: $e');
    }

    final entered = _digitsOnly(enteredOtp);
    if (entered.length != 6) {
      return OtpVerifyOutcome.invalidCode();
    }

    try {
      final snap = await _db.collection(collectionId).doc(uid).get(
            const GetOptions(source: Source.server),
          );
      if (!snap.exists || snap.data() == null) {
        return _verifyWithFallbacks(uid, entered);
      }

      final data = snap.data()!;
      final storedRaw = data['otp']?.toString() ?? '';
      final expiresAt = data['expiresAt'];
      DateTime? expiry;
      if (expiresAt is Timestamp) {
        expiry = expiresAt.toDate();
      }

      if (expiry != null && DateTime.now().isAfter(expiry)) {
        return OtpVerifyOutcome.expired();
      }

      final stored = _digitsOnly(storedRaw);
      if (stored.isEmpty || stored != entered) {
        return OtpVerifyOutcome.invalidCode();
      }

      return OtpVerifyOutcome.success();
    } on FirebaseException catch (e) {
      debugPrint('[OTP] verify client read: ${e.code} ${e.message}');
      if (e.code == 'permission-denied' ||
          e.code == 'unavailable' ||
          e.code == 'unauthenticated') {
        return _verifyWithFallbacks(uid, entered);
      }
      return OtpVerifyOutcome.error(
        'Could not read verification code [${e.code}]. Check your connection.',
      );
    } catch (e) {
      debugPrint('[OTP] verify error: $e');
      return _verifyWithFallbacks(uid, entered);
    }
  }

  static Future<OtpVerifyOutcome> _verifyWithFallbacks(
    String uid,
    String entered,
  ) async {
    final remote = await _verifyOtpViaCloudFunction(uid, entered);
    if (remote.ok || remote.isInvalidCode || remote.isExpired) {
      return remote;
    }
    return _verifyOtpLocally(uid, entered);
  }

  static Future<OtpVerifyOutcome> _verifyOtpLocally(
    String uid,
    String entered,
  ) async {
    if (!await OtpLocalFallbackCache.hasActive(uid)) {
      return OtpVerifyOutcome.notFound();
    }
    final ok = await OtpLocalFallbackCache.verify(uid: uid, enteredOtp: entered);
    if (ok) {
      debugPrint('[OTP] verified via device-local fallback');
      return OtpVerifyOutcome.success();
    }
    return OtpVerifyOutcome.invalidCode();
  }

  static Future<OtpVerifyOutcome> _verifyOtpViaCloudFunction(
    String uid,
    String entered,
  ) async {
    try {
      final callable = _functions.httpsCallable('verifyEmailOtp');
      final result = await callable.call<Map<String, dynamic>>({
        'otp': entered,
        // Important: verification must be side-effect free.
        // Deletion happens only after we successfully persist the verified user profile.
        'deleteOnSuccess': false,
      });
      final data = result.data;
      if (data['ok'] == true) {
        debugPrint('[OTP] verified via Cloud Function');
        return OtpVerifyOutcome.success();
      }
      final reason = data['reason']?.toString() ?? '';
      switch (reason) {
        case 'expired':
          return OtpVerifyOutcome.expired();
        case 'not_found':
          return OtpVerifyOutcome.notFound();
        case 'invalid':
          return OtpVerifyOutcome.invalidCode();
        default:
          return OtpVerifyOutcome.invalidCode();
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[OTP] verifyEmailOtp CF: ${e.code} ${e.message}');
      if (e.code == 'not-found' || e.code == 'unavailable') {
        return OtpVerifyOutcome.error(
          'Verification service unavailable. Deploy Cloud Functions '
          '(verifyEmailOtp) and try Resend code.',
        );
      }
      return OtpVerifyOutcome.error(
        e.message ?? 'Verification failed. Try Resend code.',
      );
    } catch (e) {
      return OtpVerifyOutcome.error('Verification failed: $e');
    }
  }

  static String _digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// Removes OTP document after successful verification (single-use).
  static Future<void> deleteOtp(String uid) async {
    await OtpLocalFallbackCache.clear(uid);
    if (!_ready) return;
    try {
      await _db.collection(collectionId).doc(uid).delete();
    } catch (e) {
      debugPrint('[OTP] deleteOtp: $e');
    }
  }

  /// True when [uid] has a non-expired OTP document.
  static Future<bool> hasActiveOtp(String uid) async {
    final digits = await fetchActiveOtpDigits(uid);
    return digits != null && digits.length == 6;
  }

  /// Returns the active 6-digit code for [uid], or null if missing/expired.
  /// Used on web when email delivery fails (same data the user would get on mobile).
  static Future<String?> fetchActiveOtpDigits(String uid) async {
    if (!_ready || uid.isEmpty) return null;

    try {
      await refreshAuthTokenForUid(uid);
    } catch (_) {}

    try {
      final snap = await _db.collection(collectionId).doc(uid).get(
            const GetOptions(source: Source.server),
          );
      if (!snap.exists || snap.data() == null) {
        final remote = await _peekOtpViaCloudFunction();
        return remote ?? await OtpLocalFallbackCache.activeOtpDigits(uid);
      }

      final data = snap.data()!;
      final expiresAt = data['expiresAt'];
      if (expiresAt is Timestamp) {
        if (DateTime.now().isAfter(expiresAt.toDate())) return null;
      }

      final digits = _digitsOnly(data['otp']?.toString() ?? '');
      return digits.length == 6 ? digits : null;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        final remote = await _peekOtpViaCloudFunction();
        return remote ?? await OtpLocalFallbackCache.activeOtpDigits(uid);
      }
      return null;
    }
  }

  static Future<String?> _peekOtpViaCloudFunction() async {
    try {
      final callable = _functions.httpsCallable('peekEmailOtp');
      final result = await callable.call<Map<String, dynamic>>();
      final data = result.data;
      if (data['active'] == true) {
        final digits = _digitsOnly(data['otp']?.toString() ?? '');
        return digits.length == 6 ? digits : null;
      }
      return null;
    } catch (e) {
      debugPrint('[OTP] peekEmailOtp: $e');
      return null;
    }
  }
}

/// Result of an OTP comparison (no side effects).
class OtpVerifyOutcome {
  const OtpVerifyOutcome._({
    required this.ok,
    this.isExpired = false,
    this.isNotFound = false,
    this.isInvalidCode = false,
    this.message,
  });

  final bool ok;
  final bool isExpired;
  final bool isNotFound;
  final bool isInvalidCode;
  final String? message;

  factory OtpVerifyOutcome.success() =>
      const OtpVerifyOutcome._(ok: true);

  factory OtpVerifyOutcome.expired() => const OtpVerifyOutcome._(
        ok: false,
        isExpired: true,
        message:
            'This code has expired (valid for ${OtpService.otpExpiryMinutes} minutes). '
            'Tap Resend code.',
      );

  factory OtpVerifyOutcome.notFound() => const OtpVerifyOutcome._(
        ok: false,
        isNotFound: true,
        message:
            'No active verification code. We can send a new one — tap Resend code.',
      );

  factory OtpVerifyOutcome.invalidCode() => const OtpVerifyOutcome._(
        ok: false,
        isInvalidCode: true,
        message:
            'That code does not match. Check for typos or request a new code.',
      );

  factory OtpVerifyOutcome.error(String msg) => OtpVerifyOutcome._(
        ok: false,
        message: msg,
      );
}
