import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// Firestore collection for pending email OTPs (single-use, 5-minute TTL).
///
/// Document ID = Firebase Auth UID (one pending OTP per user).
class OtpService {
  OtpService._();

  static const String collectionId = 'email_otps';
  static const int otpExpiryMinutes = 5;

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

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

  /// Persists OTP and expiry; overwrites any previous OTP for this [uid].
  static Future<void> saveOtp({
    required String uid,
    required String email,
    required String otp,
  }) async {
    if (!_ready) throw StateError('Firebase not initialized');
    final now = DateTime.now();
    final expires = now.add(const Duration(minutes: otpExpiryMinutes));

    await _db.collection(collectionId).doc(uid).set({
      'email': email,
      'otp': otp,
      'firebaseUid': uid,
      'expiresAt': Timestamp.fromDate(expires),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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

    final snap = await _db.collection(collectionId).doc(uid).get();
    if (!snap.exists || snap.data() == null) {
      return OtpVerifyOutcome.error('No verification code found. Request a new code.');
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

    // Compare digit-only strings so Firestore int/string, paste spacing, or
    // hidden characters do not break verification.
    final stored = _digitsOnly(storedRaw);
    final entered = _digitsOnly(enteredOtp);
    if (stored.isEmpty || stored != entered) {
      return OtpVerifyOutcome.error('Invalid verification code.');
    }

    return OtpVerifyOutcome.success();
  }

  static String _digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// Removes OTP document after successful verification (single-use).
  static Future<void> deleteOtp(String uid) async {
    if (!_ready) return;
    await _db.collection(collectionId).doc(uid).delete();
  }

  /// Returns the active 6-digit code for [uid], or null if missing/expired.
  /// Used on web when email delivery fails (same data the user would get on mobile).
  static Future<String?> fetchActiveOtpDigits(String uid) async {
    if (!_ready || uid.isEmpty) return null;

    final snap = await _db.collection(collectionId).doc(uid).get();
    if (!snap.exists || snap.data() == null) return null;

    final data = snap.data()!;
    final expiresAt = data['expiresAt'];
    if (expiresAt is Timestamp) {
      if (DateTime.now().isAfter(expiresAt.toDate())) return null;
    }

    final digits = _digitsOnly(data['otp']?.toString() ?? '');
    return digits.length == 6 ? digits : null;
  }
}

/// Result of an OTP comparison (no side effects).
class OtpVerifyOutcome {
  const OtpVerifyOutcome._({
    required this.ok,
    this.isExpired = false,
    this.message,
  });

  final bool ok;
  final bool isExpired;
  final String? message;

  factory OtpVerifyOutcome.success() =>
      const OtpVerifyOutcome._(ok: true);

  factory OtpVerifyOutcome.expired() => const OtpVerifyOutcome._(
        ok: false,
        isExpired: true,
        message: 'This code has expired. Request a new one.',
      );

  factory OtpVerifyOutcome.error(String msg) => OtpVerifyOutcome._(
        ok: false,
        message: msg,
      );
}
