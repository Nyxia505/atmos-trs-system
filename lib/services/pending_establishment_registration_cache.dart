import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Holds tourism-establishment signup payloads until OTP verification succeeds.
class PendingEstablishmentRegistration {
  const PendingEstablishmentRegistration({
    required this.uid,
    required this.contactEmail,
    required this.authEmail,
    required this.userData,
    required this.establishmentData,
  });

  final String uid;
  final String contactEmail;
  final String authEmail;
  final Map<String, dynamic> userData;
  final Map<String, dynamic> establishmentData;

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'contactEmail': contactEmail,
        'authEmail': authEmail,
        'userData': userData,
        'establishmentData': establishmentData,
      };

  static PendingEstablishmentRegistration? fromJson(Map<String, dynamic> json) {
    final uid = json['uid']?.toString() ?? '';
    if (uid.isEmpty) return null;
    final user = json['userData'];
    final est = json['establishmentData'];
    if (user is! Map || est is! Map) return null;
    return PendingEstablishmentRegistration(
      uid: uid,
      contactEmail: json['contactEmail']?.toString() ?? '',
      authEmail: json['authEmail']?.toString() ?? '',
      userData: Map<String, dynamic>.from(user),
      establishmentData: Map<String, dynamic>.from(est),
    );
  }
}

class PendingEstablishmentRegistrationCache {
  PendingEstablishmentRegistrationCache._();

  static const _prefsKey = 'pending_establishment_registration_v1';
  static PendingEstablishmentRegistration? _memory;

  static PendingEstablishmentRegistration? get current => _memory;

  static PendingEstablishmentRegistration? forUid(String uid) {
    final p = _memory;
    if (p == null || p.uid != uid) return null;
    return p;
  }

  static Future<void> hydrate() async {
    if (_memory != null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _memory = PendingEstablishmentRegistration.fromJson(decoded);
      } else if (decoded is Map) {
        _memory = PendingEstablishmentRegistration.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (_) {}
  }

  static Future<void> save(PendingEstablishmentRegistration pending) async {
    _memory = pending;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(pending.toJson()));
  }

  static Future<void> clear() async {
    _memory = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  static Map<String, dynamic> jsonSafeMap(Map<String, dynamic> input) {
    final out = <String, dynamic>{};
    input.forEach((key, value) {
      if (value == null) return;
      if (value is num || value is bool || value is String) {
        out[key] = value;
      } else if (value is List) {
        out[key] = value.map((e) => e?.toString() ?? '').toList();
      } else {
        out[key] = value.toString();
      }
    });
    return out;
  }
}
