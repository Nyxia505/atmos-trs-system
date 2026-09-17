import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:atmos_trs_system/config/session_storage.dart';

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
/// Staff roles: `governor`, `provincial_tourism` / `tourism_province`,
/// `tourism_office` (or legacy `tourism`).
class AppUserProfile {
  const AppUserProfile({
    required this.uid,
    required this.email,
    required this.roleRaw,
    this.fullName,
    this.municipality = '',
    this.municipalityId = '',
    this.isVerified = false,
    this.status = '',
  });

  final String uid;
  final String email;
  final String roleRaw;
  final String? fullName;
  final String municipality;

  /// Canonical municipality id (e.g. oroquieta) when stored on the user doc.
  final String municipalityId;

  /// For tourists: EmailJS OTP completed.
  final bool isVerified;

  /// Establishment / LGU approval status (`pending`, `active`, …).
  final String status;

  bool get isGovernor => roleRaw == 'governor';

  /// Provincial Tourism Office (province-wide tourism program ops).
  bool get isProvincialTourism =>
      roleRaw == 'provincial_tourism' || roleRaw == 'tourism_province';

  /// Municipal LGU tourism office dashboard.
  bool get isTourismOffice =>
      !isProvincialTourism &&
      (roleRaw == 'tourism_office' || roleRaw == 'tourism');

  bool get isTourist => roleRaw == 'tourist';

  /// Tourism establishment (hotel, resort, restaurant, attraction, etc.).
  bool get isTourismEstablishment =>
      roleRaw == 'tourism_establishment' ||
      roleRaw == 'tourismestablishment' ||
      roleRaw == 'establishment';

  bool get isAnyStaff =>
      isGovernor || isProvincialTourism || isTourismOffice;

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
      municipalityId: (data['municipalityId'] as String? ?? '').trim(),
      isVerified: data['isVerified'] as bool? ?? false,
      status: (data['status'] as String? ?? '').trim().toLowerCase(),
    );
  }
}

/// Loads role-based profiles from the `users` collection (by UID or email).
class UserDirectoryService {
  UserDirectoryService._();

  static const String collectionId = 'users';

  static String? _preparedStaffUid;
  static DateTime? _preparedStaffAt;
  static const Duration _staffPrepTtl = Duration(minutes: 30);

  static void clearStaffAccessCache() {
    _preparedStaffUid = null;
    _preparedStaffAt = null;
  }

  /// Called after login finalization confirms staff Firestore access.
  static void markStaffFirestoreAccessReady(String uid) {
    if (uid.isEmpty) return;
    _markStaffPrepared(uid);
  }

  static bool _staffPrepIsFresh(String uid) {
    return _preparedStaffUid == uid &&
        _preparedStaffAt != null &&
        DateTime.now().difference(_preparedStaffAt!) < _staffPrepTtl;
  }

  static void _markStaffPrepared(String uid) {
    _preparedStaffUid = uid;
    _preparedStaffAt = DateTime.now();
  }

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

  /// Tourists must complete in-app OTP on [VerifyOtpScreen]; Firebase Auth
  /// `emailVerified` alone does not count (prevents skipping OTP).
  static Future<void> syncVerifiedStatusFromAuthIfNeeded(String uid) async {
    // Intentionally empty — kept for call-site compatibility.
  }

  /// True only after in-app OTP sets `isVerified` on `users` / `tourists`.
  static Future<bool> touristEmailVerificationComplete(String uid) async {
    if (uid.isEmpty) return false;
    if (await SessionStorage.isTouristEmailVerifiedCached(uid)) {
      return true;
    }
    if (!_ready) return false;
    final profile = await getProfileByUid(uid, preferServer: true);
    if (profile != null && profile.isTourist && profile.isVerified) {
      await SessionStorage.setTouristEmailVerified(uid, verified: true);
      return true;
    }
    final touristsVerified = await getTouristIsVerifiedFromTouristsDoc(uid);
    if (touristsVerified == true) {
      await SessionStorage.setTouristEmailVerified(uid, verified: true);
      return true;
    }
    return false;
  }

  /// True when [email] maps to governor or any tourism/LGU staff account.
  static bool isProvincialStaffEmail(String email) {
    final role = SessionStorage.getRoleFromEmail(email);
    return SessionStorage.isStaffRole(role);
  }

  /// True when the signed-in user may run provincial/LGU Firestore list queries.
  static Future<bool> isCurrentUserProvincialStaff({bool preferServer = true}) async {
    final auth = FirebaseAuth.instance.currentUser;
    if (auth == null) return false;
    final email = auth.email?.trim() ?? '';
    if (email.isNotEmpty && isProvincialStaffEmail(email)) return true;
    final storedRole = await SessionStorage.getStoredRole();
    if (SessionStorage.isStaffRole(storedRole)) {
      return true;
    }
    final profile = await getProfileByUid(
      auth.uid,
      preferServer: preferServer,
    );
    if (profile != null && profile.isAnyStaff) {
      return true;
    }
    return false;
  }

  static bool _isAllowedStaffRoleRaw(String role) {
    return role == 'governor' ||
        role == 'tourism' ||
        role == 'tourism_office' ||
        role == 'provincial_tourism' ||
        role == 'tourism_province';
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
    if (!_isAllowedStaffRoleRaw(role)) {
      return false;
    }
    final mun = (municipalityId ?? '').trim();
    try {
      await _db.collection(collectionId).doc(uid).set({
        'firebaseUid': uid,
        'email': email.trim(),
        'role': role,
        if (fullName != null) 'fullName': fullName.trim(),
        // Prefer municipalityId only — do not overwrite display `municipality`.
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
    final storedRole = await SessionStorage.getStoredRole();
    final storedUid = await SessionStorage.getStoredUser();
    final sessionIsStaff = storedUid == uid &&
        SessionStorage.isStaffRole(storedRole);
    final emailIsStaff =
        normalizedEmail.isNotEmpty && isProvincialStaffEmail(normalizedEmail);

    if (!emailIsStaff && !sessionIsStaff) {
      debugPrint(
        'UserDirectoryService.prepareProvincialStaffFirestoreAccess: '
        'skipped — not staff (email=$normalizedEmail, sessionRole=${storedRole.name})',
      );
      return false;
    }

    if (_staffPrepIsFresh(uid)) {
      return true;
    }

    final effectiveRole = storedRole == UserRole.governor
        ? 'governor'
        : storedRole == UserRole.provincialTourism
            ? 'provincial_tourism'
            : (roleRaw.trim().isNotEmpty
                ? roleRaw.trim().toLowerCase()
                : 'tourism');
    var mun = (municipalityId ?? '').trim();
    if (mun.isEmpty) {
      mun = await SessionStorage.getStoredMunicipalityId() ?? '';
    }
    if (mun.isEmpty && normalizedEmail.isNotEmpty) {
      mun = SessionStorage.getMunicipalityIdFromTourismEmail(normalizedEmail) ?? '';
    }

    // Trusted staff session/email: one merge write, skip email lookup + server get.
    // Login already marks prep ready; this covers cold start / cache miss.
    if (sessionIsStaff || emailIsStaff) {
      await ensureStaffUserDoc(
        uid: uid,
        email: normalizedEmail.isNotEmpty ? normalizedEmail : email,
        roleRaw: effectiveRole,
        fullName: fullName,
        municipalityId: mun.isNotEmpty ? mun : null,
      );
      _markStaffPrepared(uid);
      return true;
    }

    return false;
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
