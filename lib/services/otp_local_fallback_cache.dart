import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Device-local backup for signup OTP when Firestore rules / Cloud Functions
/// are unavailable. Same browser or phone can verify via "Show code on device".
class OtpLocalFallbackCache {
  OtpLocalFallbackCache._();

  static String _key(String uid) => 'atmos_email_otp_$uid';

  static String _digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

  static Future<void> save({
    required String uid,
    required String email,
    required String otp,
    required DateTime expiresAt,
  }) async {
    if (uid.isEmpty) {
      throw StateError('OTP local cache requires a non-empty uid');
    }
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode({
      'email': email.trim().toLowerCase(),
      'otp': _digitsOnly(otp),
      'expiresAtMs': expiresAt.millisecondsSinceEpoch,
      'savedAtMs': DateTime.now().millisecondsSinceEpoch,
    });
    await prefs.setString(_key(uid), payload);
  }

  static Future<void> clear(String uid) async {
    if (uid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(uid));
  }

  static Future<Map<String, dynamic>?> _read(String uid) async {
    if (uid.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(uid));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> hasActive(String uid) async {
    final digits = await activeOtpDigits(uid);
    return digits != null && digits.length == 6;
  }

  static Future<String?> activeOtpDigits(String uid) async {
    final data = await _read(uid);
    if (data == null) return null;

    final expiresMs = data['expiresAtMs'];
    if (expiresMs is int &&
        DateTime.now().millisecondsSinceEpoch > expiresMs) {
      await clear(uid);
      return null;
    }

    final digits = _digitsOnly(data['otp']?.toString() ?? '');
    return digits.length == 6 ? digits : null;
  }

  static Future<bool> verify({
    required String uid,
    required String enteredOtp,
  }) async {
    final stored = await activeOtpDigits(uid);
    if (stored == null) return false;
    return stored == _digitsOnly(enteredOtp);
  }
}
