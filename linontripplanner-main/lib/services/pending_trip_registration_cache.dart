import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// Holds Trip Planner signup payload until email OTP succeeds (deferred Auth).
class PendingTripRegistration {
  const PendingTripRegistration({
    required this.pendingId,
    required this.email,
    required this.password,
    required this.fullName,
    required this.phone,
    required this.registration,
    this.facePhotoBytes,
  });

  final String pendingId;
  final String email;
  final String password;
  final String fullName;
  final String? phone;
  final Map<String, dynamic> registration;
  final Uint8List? facePhotoBytes;

  String get otpKey => pendingId;

  Map<String, dynamic> toJson() => {
        'pendingId': pendingId,
        'email': email,
        'password': password,
        'fullName': fullName,
        'phone': phone,
        'registration': registration,
      };

  static PendingTripRegistration? fromJson(
    Map<String, dynamic> json, {
    Uint8List? facePhotoBytes,
  }) {
    final pendingId = json['pendingId']?.toString() ?? '';
    final email = json['email']?.toString() ?? '';
    final password = json['password']?.toString() ?? '';
    if (pendingId.isEmpty || email.isEmpty || password.isEmpty) return null;
    final reg = json['registration'];
    if (reg is! Map) return null;
    return PendingTripRegistration(
      pendingId: pendingId,
      email: email,
      password: password,
      fullName: json['fullName']?.toString() ?? email,
      phone: json['phone']?.toString(),
      registration: Map<String, dynamic>.from(reg),
      facePhotoBytes: facePhotoBytes,
    );
  }
}

class PendingTripRegistrationCache {
  PendingTripRegistrationCache._();

  static const _prefsKey = 'tripplan_pending_registration_v1';
  static PendingTripRegistration? _memory;
  static Uint8List? _facePhotoBytes;

  static PendingTripRegistration? get current => _memory;

  static Future<void> save(PendingTripRegistration pending) async {
    _memory = pending;
    _facePhotoBytes = pending.facePhotoBytes;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(pending.toJson()));
  }

  static Future<PendingTripRegistration?> hydrate() async {
    if (_memory != null) return _memory;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      _memory = PendingTripRegistration.fromJson(
        Map<String, dynamic>.from(decoded),
        facePhotoBytes: _facePhotoBytes,
      );
      return _memory;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    _memory = null;
    _facePhotoBytes = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
