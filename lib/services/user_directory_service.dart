import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;

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

  /// If the user verified their email in Firebase Auth (Gmail link), mirror that to
  /// `users` / `tourists` `isVerified` so they are not sent to the in-app OTP screen again.
  static Future<void> syncVerifiedStatusFromAuthIfNeeded(String uid) async {
    if (!_ready || uid.isEmpty) return;
    User? u = FirebaseAuth.instance.currentUser;
    if (u == null || u.uid != uid) return;
    try {
      await u.reload();
      u = FirebaseAuth.instance.currentUser;
    } catch (_) {}
    if (u == null || !u.emailVerified) return;

    try {
      final userDoc = await _db.collection(collectionId).doc(uid).get();
      final touristDoc = await _db.collection('tourists').doc(uid).get();
      final role =
          (userDoc.data()?['role'] as String? ?? '').trim().toLowerCase();
      final looksLikeTourist =
          role == 'tourist' || (!userDoc.exists && touristDoc.exists);
      if (!looksLikeTourist) return;

      final userOk = (userDoc.data()?['isVerified'] as bool?) == true;
      final tourOk = (touristDoc.data()?['isVerified'] as bool?) == true;
      if (userOk && tourOk) return;
      if (userOk && !touristDoc.exists) return;

      final batch = _db.batch();
      var hasOps = false;
      if (userDoc.exists && !userOk) {
        batch.set(
          _db.collection(collectionId).doc(uid),
          {'isVerified': true},
          SetOptions(merge: true),
        );
        hasOps = true;
      }
      if (touristDoc.exists && !tourOk) {
        batch.set(
          _db.collection('tourists').doc(uid),
          {'isVerified': true},
          SetOptions(merge: true),
        );
        hasOps = true;
      }
      if (hasOps) await batch.commit();
    } catch (e) {
      debugPrint('UserDirectoryService.syncVerifiedStatusFromAuthIfNeeded: $e');
    }
  }

  /// True if this tourist completed in-app OTP **or** Firebase Auth email verification.
  static Future<bool> touristEmailVerificationComplete(String uid) async {
    if (!_ready || uid.isEmpty) return false;
    await syncVerifiedStatusFromAuthIfNeeded(uid);
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser != null &&
        authUser.uid == uid &&
        authUser.emailVerified) {
      return true;
    }
    final profile = await getProfileByUid(uid, preferServer: true);
    if (profile != null && profile.isTourist && profile.isVerified) {
      return true;
    }
    final fromTourists = await getTouristIsVerifiedFromTouristsDoc(uid);
    return fromTourists == true;
  }

  /// Creates/updates `users/{uid}` for Governor or tourism staff (required for Firestore rules).
  static Future<bool> ensureStaffUserDoc({
    required String uid,
    required String email,
    required String roleRaw,
    String? fullName,
    String? municipalityId,
  }) async {
    if (!_ready || uid.isEmpty) return false;
    final role = roleRaw.trim().toLowerCase();
    if (role != 'governor' && role != 'tourism' && role != 'tourism_office') {
      return false;
    }
    final mun = (municipalityId ?? '').trim();
    try {
      await _db.collection(collectionId).doc(uid).set({
        'firebaseUid': uid,
        'email': email.trim(),
        'role': role,
        'fullName': fullName?.trim() ?? '',
        'municipality': mun,
        if (mun.isNotEmpty) 'municipalityId': mun,
        'isVerified': true,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('UserDirectoryService.ensureStaffUserDoc: $e');
      return false;
    }
  }

  /// Ensures `users/{uid}` has a staff role before provincial/LGU Firestore list queries.
  static Future<bool> prepareProvincialStaffFirestoreAccess({
    required String uid,
    required String email,
    required String roleRaw,
    String? fullName,
    String? municipalityId,
  }) async {
    if (!_ready || uid.isEmpty) return false;

    final normalizedEmail = email.trim();
    var wrote = await ensureStaffUserDoc(
      uid: uid,
      email: normalizedEmail.isNotEmpty ? normalizedEmail : email,
      roleRaw: roleRaw,
      fullName: fullName,
      municipalityId: municipalityId,
    );

    // Legacy: staff profile stored under a different doc id (email query).
    if (!wrote || normalizedEmail.isNotEmpty) {
      final byEmail = await getProfileByEmail(normalizedEmail);
      if (byEmail != null &&
          byEmail.uid != uid &&
          (byEmail.isGovernor || byEmail.isTourismOffice)) {
        wrote = await ensureStaffUserDoc(
          uid: uid,
          email: byEmail.email,
          roleRaw: byEmail.roleRaw,
          fullName: byEmail.fullName ?? fullName,
          municipalityId: municipalityId,
        );
      }
    }

    try {
      final doc = await _db
          .collection(collectionId)
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      final role =
          (doc.data()?['role'] as String? ?? '').trim().toLowerCase();
      final isStaff = role == 'governor' ||
          role == 'tourism' ||
          role == 'tourism_office';
      if (isStaff) {
        await _syncStaffCustomClaims();
      }
      return isStaff;
    } catch (e) {
      debugPrint('UserDirectoryService.prepareProvincialStaffFirestoreAccess: $e');
      return false;
    }
  }

  /// Sets Auth custom claims via Cloud Function so Firestore rules allow staff list queries.
  static Future<void> _syncStaffCustomClaims() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('ensureStaffAccess');
      await callable.call<Object?>();
      await user.getIdToken(true);
    } catch (e) {
      debugPrint('UserDirectoryService._syncStaffCustomClaims: $e');
    }
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
