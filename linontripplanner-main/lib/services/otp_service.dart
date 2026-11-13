import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'otp_local_fallback_cache.dart';

/// Email OTP helpers — same Cloud Functions as ATMOS TRS (`asia-southeast1`).
class OtpService {
  OtpService._();

  static const String collectionId = 'email_otps';
  static const int otpExpiryMinutes = 5;

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

  static String generateSixDigitOtp() {
    final r = Random.secure();
    return (100000 + r.nextInt(900000)).toString();
  }

  static String _digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// Device-local OTP before Firebase Auth exists (deferred signup).
  static Future<void> saveOtpPreAuth({
    required String pendingId,
    required String email,
    required String otp,
  }) async {
    if (pendingId.isEmpty) {
      throw StateError('pendingId is required for pre-auth OTP');
    }
    final expires =
        DateTime.now().add(const Duration(minutes: otpExpiryMinutes));
    await OtpLocalFallbackCache.save(
      uid: pendingId,
      email: email,
      otp: otp,
      expiresAt: expires,
    );
    debugPrint('[OTP] saved pre-auth local OTP for pendingId=$pendingId');
  }

  static Future<OtpVerifyOutcome> verifyOtpPreAuth({
    required String pendingId,
    required String enteredOtp,
  }) async {
    final entered = _digitsOnly(enteredOtp);
    if (entered.length != 6) {
      return OtpVerifyOutcome.invalidCode();
    }
    if (!await OtpLocalFallbackCache.hasActive(pendingId)) {
      return OtpVerifyOutcome.notFound();
    }
    final ok = await OtpLocalFallbackCache.verify(
      uid: pendingId,
      enteredOtp: entered,
    );
    if (ok) {
      debugPrint('[OTP] verified pre-auth local OTP');
      return OtpVerifyOutcome.success();
    }
    return OtpVerifyOutcome.invalidCode();
  }

  static Future<void> deleteOtp(String uid) async {
    await OtpLocalFallbackCache.clear(uid);
    if (!_ready) return;
    try {
      await _db.collection(collectionId).doc(uid).delete();
    } catch (e) {
      debugPrint('[OTP] deleteOtp: $e');
    }
  }

  /// Persists OTP for a signed-in user (resend after Auth exists).
  static Future<void> saveOtp({
    required String uid,
    required String email,
    required String otp,
  }) async {
    if (!_ready) throw StateError('Firebase not initialized');
    final expires =
        DateTime.now().add(const Duration(minutes: otpExpiryMinutes));
    final payload = <String, dynamic>{
      'email': email,
      'otp': otp,
      'firebaseUid': uid,
      'expiresAt': Timestamp.fromDate(expires),
      'createdAt': FieldValue.serverTimestamp(),
    };

    final signedIn = FirebaseAuth.instance.currentUser?.uid == uid;
    if (!signedIn) {
      await OtpLocalFallbackCache.save(
        uid: uid,
        email: email,
        otp: otp,
        expiresAt: expires,
      );
      return;
    }

    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      await _db.collection(collectionId).doc(uid).set(
            payload,
            SetOptions(merge: true),
          );
      await OtpLocalFallbackCache.clear(uid);
      return;
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      debugPrint('[OTP] client write denied — trying saveEmailOtp');
    }

    try {
      final callable = _functions.httpsCallable('saveEmailOtp');
      await callable.call<void>({
        'email': email,
        'otp': otp,
        'expiresAtMs': expires.millisecondsSinceEpoch,
      });
      await OtpLocalFallbackCache.clear(uid);
    } catch (e) {
      debugPrint('[OTP] saveEmailOtp failed: $e — local fallback');
      await OtpLocalFallbackCache.save(
        uid: uid,
        email: email,
        otp: otp,
        expiresAt: expires,
      );
    }
  }

  static Future<OtpVerifyOutcome> verifyOtp({
    required String uid,
    required String enteredOtp,
  }) async {
    final entered = _digitsOnly(enteredOtp);
    if (entered.length != 6) {
      return OtpVerifyOutcome.invalidCode();
    }

    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      final snap = await _db.collection(collectionId).doc(uid).get(
            const GetOptions(source: Source.server),
          );
      if (snap.exists && snap.data() != null) {
        final data = snap.data()!;
        final expiresAt = data['expiresAt'];
        if (expiresAt is Timestamp &&
            DateTime.now().isAfter(expiresAt.toDate())) {
          return OtpVerifyOutcome.expired();
        }
        final stored = _digitsOnly(data['otp']?.toString() ?? '');
        if (stored.length == 6 && stored == entered) {
          return OtpVerifyOutcome.success();
        }
        return OtpVerifyOutcome.invalidCode();
      }
    } on FirebaseException catch (e) {
      debugPrint('[OTP] verify client read: ${e.code}');
    }

    try {
      final callable = _functions.httpsCallable('verifyEmailOtp');
      final result = await callable.call<Map<String, dynamic>>({
        'otp': entered,
        'deleteOnSuccess': false,
      });
      final data = result.data;
      if (data['ok'] == true) return OtpVerifyOutcome.success();
      switch (data['reason']?.toString()) {
        case 'expired':
          return OtpVerifyOutcome.expired();
        case 'not_found':
          return OtpVerifyOutcome.notFound();
        default:
          return OtpVerifyOutcome.invalidCode();
      }
    } catch (e) {
      debugPrint('[OTP] verifyEmailOtp CF: $e');
    }

    if (await OtpLocalFallbackCache.verify(uid: uid, enteredOtp: entered)) {
      return OtpVerifyOutcome.success();
    }
    if (!await OtpLocalFallbackCache.hasActive(uid)) {
      return OtpVerifyOutcome.notFound();
    }
    return OtpVerifyOutcome.invalidCode();
  }
}

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

  factory OtpVerifyOutcome.success() => const OtpVerifyOutcome._(ok: true);

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
        message: 'No active verification code. Tap Resend code.',
      );

  factory OtpVerifyOutcome.invalidCode() => const OtpVerifyOutcome._(
        ok: false,
        isInvalidCode: true,
        message: 'Incorrect code. Check your email and try again.',
      );

  factory OtpVerifyOutcome.error(String message) => OtpVerifyOutcome._(
        ok: false,
        message: message,
      );
}
