import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// Canonical user profile in Firestore `users` collection (all roles).
///
/// **Document ID** = Firebase Auth UID.
///
/// Example fields:
/// ```json
/// {
///   "firebaseUid": "<uid>",
///   "email": "user@example.com",
///   "fullName": "Juan Dela Cruz",
///   "role": "tourist",
///   "municipality": "",
///   "isVerified": false,
///   "createdAt": <Timestamp>
/// }
/// ```
///
/// Staff roles: `governor`, `tourism_office` (or legacy `tourism`).
class AppUserProfile {
  const AppUserProfile({
    required this.uid,
    required this.email,
    required this.roleRaw,
    this.fullName,
    this.municipality = '',
    this.isVerified = false,
  });

  final String uid;
  final String email;
  final String roleRaw;
  final String? fullName;
  final String municipality;

  /// For tourists: EmailJS OTP completed.
  final bool isVerified;

  bool get isGovernor => roleRaw == 'governor';

  /// Municipal / provincial tourism office dashboard.
  bool get isTourismOffice =>
      roleRaw == 'tourism_office' ||
      roleRaw == 'tourism';

  bool get isTourist => roleRaw == 'tourist';

  static AppUserProfile? fromMap(String uid, Map<String, dynamic> data) {
    final email = data['email'] as String?;
    if (email == null || email.isEmpty) return null;
    final role = (data['role'] as String? ?? '').trim().toLowerCase();
    if (role.isEmpty) return null;

    return AppUserProfile(
      uid: uid,
      email: email.trim(),
      roleRaw: role,
      fullName: data['fullName'] as String?,
      municipality: (data['municipality'] as String? ?? '').trim(),
      isVerified: data['isVerified'] as bool? ?? false,
    );
  }
}

/// Loads role-based profiles from the `users` collection (by UID or email).
class UserDirectoryService {
  UserDirectoryService._();

  static const String collectionId = 'users';

  static bool get _ready {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Primary lookup: document id == Auth UID.
  ///
  /// Use [preferServer] after writes (e.g. OTP verified) so Firestore cache
  /// does not return stale [isVerified]: false.
  static Future<AppUserProfile?> getProfileByUid(
    String uid, {
    bool preferServer = false,
  }) async {
    if (!_ready || uid.isEmpty) return null;
    try {
      final doc = preferServer
          ? await _db
              .collection(collectionId)
              .doc(uid)
              .get(const GetOptions(source: Source.server))
          : await _db.collection(collectionId).doc(uid).get();
      if (!doc.exists || doc.data() == null) return null;
      return AppUserProfile.fromMap(uid, doc.data()!);
    } catch (_) {
      return null;
    }
  }

  /// True if this tourist completed EmailJS OTP (`users.isVerified` and/or `tourists.isVerified`).
  static Future<bool> touristEmailVerificationComplete(String uid) async {
    if (!_ready || uid.isEmpty) return false;
    final profile = await getProfileByUid(uid, preferServer: true);
    if (profile != null && profile.isTourist && profile.isVerified) {
      return true;
    }
    final fromTourists = await getTouristIsVerifiedFromTouristsDoc(uid);
    return fromTourists == true;
  }

  /// Fallback: query by email (case variants).
  static Future<AppUserProfile?> getProfileByEmail(String email) async {
    if (!_ready || email.trim().isEmpty) return null;
    final trimmed = email.trim();
    final lower = trimmed.toLowerCase();

    for (final candidate in <String>{lower, trimmed}) {
      if (candidate.isEmpty) continue;
      try {
        final snap = await _db
            .collection(collectionId)
            .where('email', isEqualTo: candidate)
            .limit(1)
            .get();
        if (snap.docs.isEmpty) continue;
        final d = snap.docs.first;
        return AppUserProfile.fromMap(d.id, d.data());
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// Tourist migration: [tourists] collection may exist without [users].
  /// Returns verification flag from `tourists/{uid}` if present.
  static Future<bool?> getTouristIsVerifiedFromTouristsDoc(String uid) async {
    if (!_ready || uid.isEmpty) return null;
    try {
      final doc = await _db.collection('tourists').doc(uid).get();
      if (!doc.exists || doc.data() == null) return null;
      return doc.data()!['isVerified'] as bool?;
    } catch (_) {
      return null;
    }
  }
}
