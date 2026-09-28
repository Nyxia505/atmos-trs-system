import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Holds tourist signup payloads until OTP verification succeeds.
///
/// When [authDeferred] is true, Firebase Auth has **not** been created yet —
/// [uid] is a local pending id used only for OTP cache keys. Auth + Firestore
/// profiles are created after successful email OTP verification.
class PendingRegistration {
  const PendingRegistration({
    required this.uid,
    required this.contactEmail,
    required this.authEmail,
    required this.touristData,
    required this.userData,
    this.localProfile,
    this.usedPhotoFirestoreFallback = false,
    this.authDeferred = false,
    this.password,
  });

  /// Firebase Auth uid after create, or a local pending id when [authDeferred].
  final String uid;
  final String contactEmail;
  final String authEmail;

  /// JSON-safe map (no [FieldValue]).
  final Map<String, dynamic> touristData;
  final Map<String, dynamic> userData;
  final PendingLocalProfile? localProfile;
  final bool usedPhotoFirestoreFallback;

  /// True until email OTP succeeds and [createUserWithEmailAndPassword] runs.
  final bool authDeferred;

  /// Temporary password for deferred Auth create (cleared after verify).
  final String? password;

  /// Key used for local OTP storage (same as [uid] while deferred).
  String get otpKey => uid;

  PendingRegistration copyWith({
    String? uid,
    String? contactEmail,
    String? authEmail,
    Map<String, dynamic>? touristData,
    Map<String, dynamic>? userData,
    PendingLocalProfile? localProfile,
    bool? usedPhotoFirestoreFallback,
    bool? authDeferred,
    String? password,
    bool clearPassword = false,
  }) {
    return PendingRegistration(
      uid: uid ?? this.uid,
      contactEmail: contactEmail ?? this.contactEmail,
      authEmail: authEmail ?? this.authEmail,
      touristData: touristData ?? this.touristData,
      userData: userData ?? this.userData,
      localProfile: localProfile ?? this.localProfile,
      usedPhotoFirestoreFallback:
          usedPhotoFirestoreFallback ?? this.usedPhotoFirestoreFallback,
      authDeferred: authDeferred ?? this.authDeferred,
      password: clearPassword ? null : (password ?? this.password),
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'contactEmail': contactEmail,
        'authEmail': authEmail,
        'touristData': touristData,
        'userData': userData,
        'usedPhotoFirestoreFallback': usedPhotoFirestoreFallback,
        'authDeferred': authDeferred,
        if (password != null && password!.isNotEmpty) 'password': password,
        if (localProfile != null) 'localProfile': localProfile!.toJson(),
      };

  static PendingRegistration? fromJson(Map<String, dynamic> json) {
    final uid = json['uid']?.toString() ?? '';
    if (uid.isEmpty) return null;
    final tourist = json['touristData'];
    final user = json['userData'];
    if (tourist is! Map || user is! Map) return null;
    PendingLocalProfile? local;
    final localRaw = json['localProfile'];
    if (localRaw is Map) {
      local = PendingLocalProfile.fromJson(Map<String, dynamic>.from(localRaw));
    }
    return PendingRegistration(
      uid: uid,
      contactEmail: json['contactEmail']?.toString() ?? '',
      authEmail: json['authEmail']?.toString() ?? '',
      touristData: Map<String, dynamic>.from(tourist),
      userData: Map<String, dynamic>.from(user),
      localProfile: local,
      usedPhotoFirestoreFallback: json['usedPhotoFirestoreFallback'] == true,
      authDeferred: json['authDeferred'] == true,
      password: json['password']?.toString(),
    );
  }
}

/// Local-only profile fields applied after Firestore save on verify.
class PendingLocalProfile {
  const PendingLocalProfile({
    required this.firstName,
    required this.middleName,
    required this.lastName,
    this.suffix,
    this.sex,
    this.nationality,
    this.dateOfBirth,
    required this.mobile,
    required this.email,
    required this.country,
    required this.province,
    required this.city,
    required this.street,
    required this.barangay,
    required this.touristId,
    this.profileImageBase64,
    this.profilePhotoUrl,
  });

  final String firstName;
  final String middleName;
  final String lastName;
  final String? suffix;
  final String? sex;
  final String? nationality;
  final String? dateOfBirth;
  final String mobile;
  final String email;
  final String country;
  final String province;
  final String city;
  final String street;
  final String barangay;
  final String touristId;
  final String? profileImageBase64;
  final String? profilePhotoUrl;

  Map<String, dynamic> toJson() => {
        'firstName': firstName,
        'middleName': middleName,
        'lastName': lastName,
        'suffix': suffix,
        'sex': sex,
        'nationality': nationality,
        'dateOfBirth': dateOfBirth,
        'mobile': mobile,
        'email': email,
        'country': country,
        'province': province,
        'city': city,
        'street': street,
        'barangay': barangay,
        'touristId': touristId,
        'profileImageBase64': profileImageBase64,
        'profilePhotoUrl': profilePhotoUrl,
      };

  static PendingLocalProfile? fromJson(Map<String, dynamic> json) {
    final touristId = json['touristId']?.toString() ?? '';
    if (touristId.isEmpty) return null;
    return PendingLocalProfile(
      firstName: json['firstName']?.toString() ?? '',
      middleName: json['middleName']?.toString() ?? '',
      lastName: json['lastName']?.toString() ?? '',
      suffix: json['suffix'] as String?,
      sex: json['sex'] as String?,
      nationality: json['nationality'] as String?,
      dateOfBirth: json['dateOfBirth'] as String?,
      mobile: json['mobile']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      country: json['country']?.toString() ?? '',
      province: json['province']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      street: json['street']?.toString() ?? '',
      barangay: json['barangay']?.toString() ?? '',
      touristId: touristId,
      profileImageBase64: json['profileImageBase64'] as String?,
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
    );
  }
}

class PendingRegistrationCache {
  PendingRegistrationCache._();

  static const _prefsKey = 'atmos_pending_registration_v1';

  static PendingRegistration? _pending;

  static Future<void> save(PendingRegistration registration) async {
    _pending = registration;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(registration.toJson()));
  }

  static Future<void> hydrate() async {
    if (_pending != null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _pending = PendingRegistration.fromJson(decoded);
      } else if (decoded is Map) {
        _pending = PendingRegistration.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } catch (_) {
      await prefs.remove(_prefsKey);
    }
  }

  /// Current unfinished tourist signup, if any.
  static PendingRegistration? get current => _pending;

  static PendingRegistration? forUid(String uid) {
    if (_pending != null && _pending!.uid == uid) return _pending;
    return null;
  }

  static PendingRegistration? forContactEmail(String email) {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty || _pending == null) return null;
    if (_pending!.contactEmail.trim().toLowerCase() == normalized) {
      return _pending;
    }
    return null;
  }

  static bool hasPendingFor(String uid) =>
      _pending != null && _pending!.uid == uid;

  static Future<void> clear() async {
    _pending = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }
}
