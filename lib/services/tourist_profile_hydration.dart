import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:atmos_trs_system/utils/email_utils.dart';

/// Loads tourist profile from Firestore into [UserProfileStorage] when local cache
/// is missing (e.g. after password reset, new browser, or cleared preferences).
class TouristProfileHydration {
  TouristProfileHydration._();

  static Future<UserProfile?> hydrateFromFirestore({
    String? uid,
    String? email,
  }) async {
    if (Firebase.apps.isEmpty) return null;

    final authUser = FirebaseAuth.instance.currentUser;
    final resolvedUid = uid ?? authUser?.uid;
    final resolvedEmail = normalizeEmail(
      email ?? authUser?.email ?? '',
    );

    if (resolvedUid == null || resolvedUid.isEmpty) return null;

    try {
      final data = await _fetchTouristData(
        uid: resolvedUid,
        email: resolvedEmail,
      );
      if (data == null) return null;

      final touristId = data['touristId']?.toString().trim();
      await UserProfileStorage.saveUserProfile(
        firstName: data['firstName']?.toString() ?? '',
        middleName: data['middleName']?.toString(),
        lastName: data['lastName']?.toString() ?? '',
        suffix: data['suffix']?.toString(),
        sex: data['sex']?.toString(),
        civilStatus: data['civilStatus']?.toString(),
        nationality: data['nationality']?.toString(),
        dateOfBirth: data['dateOfBirth']?.toString(),
        mobile: data['mobile']?.toString() ?? '',
        email: data['email']?.toString() ?? resolvedEmail,
        country: data['country']?.toString(),
        province: data['province']?.toString(),
        city: data['city']?.toString(),
        street: data['street']?.toString(),
        barangay: data['barangay']?.toString(),
        touristId: (touristId != null && touristId.isNotEmpty)
            ? touristId
            : resolvedUid,
        profileImageBase64: data['profileImageBase64']?.toString(),
        profilePhotoUrl: data['profilePhotoUrl']?.toString(),
      );
      debugPrint('[TouristProfile] hydrated from Firestore for uid=$resolvedUid');
      return UserProfileStorage.getUserProfile();
    } catch (e, st) {
      debugPrint('[TouristProfile] hydrate failed: $e\n$st');
      return null;
    }
  }

  /// Local cache first; if empty, pull full profile from Firestore.
  /// Falls back to Auth displayName / email local-part so UI never flashes
  /// "Guest" for a signed-in tourist while Firestore is slow or incomplete.
  static Future<UserProfile?> loadProfile({
    String? uid,
    String? email,
  }) async {
    var profile = await UserProfileStorage.getUserProfile();
    if (profile != null && profile.firstName.trim().isNotEmpty) {
      return profile;
    }

    final hydrated = await hydrateFromFirestore(uid: uid, email: email);
    if (hydrated != null && hydrated.firstName.trim().isNotEmpty) {
      return hydrated;
    }

    return _seedFromAuthIfNeeded(
      existing: hydrated ?? profile,
      uid: uid,
      email: email,
    );
  }

  /// When Firestore/cache lack a first name, seed from Firebase Auth so the
  /// Profile tab and Home greeting stay stable across hot restart.
  static Future<UserProfile?> _seedFromAuthIfNeeded({
    UserProfile? existing,
    String? uid,
    String? email,
  }) async {
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser == null) return existing;

    final display = authUser.displayName?.trim() ?? '';
    String first = '';
    String last = '';
    if (display.isNotEmpty) {
      final parts = display.split(RegExp(r'\s+'));
      first = parts.first;
      if (parts.length > 1) {
        last = parts.sublist(1).join(' ');
      }
    } else {
      final mail = normalizeEmail(email ?? authUser.email ?? '');
      if (mail.contains('@')) {
        final local = mail.split('@').first;
        if (local.isNotEmpty) {
          first = local[0].toUpperCase() + local.substring(1);
        }
      }
    }

    if (first.isEmpty) return existing;

    final resolvedUid = uid ?? authUser.uid;
    final resolvedEmail = normalizeEmail(
      email ?? existing?.email ?? authUser.email ?? '',
    );

    await UserProfileStorage.saveUserProfile(
      firstName: first,
      middleName: existing?.middleName,
      lastName: last.isNotEmpty ? last : (existing?.lastName ?? ''),
      suffix: existing?.suffix,
      sex: existing?.sex,
      civilStatus: existing?.civilStatus,
      nationality: existing?.nationality,
      dateOfBirth: existing?.dateOfBirth,
      mobile: existing?.mobile ?? '',
      email: resolvedEmail,
      country: existing?.country,
      province: existing?.province,
      city: existing?.city,
      street: existing?.street,
      barangay: existing?.barangay,
      touristId: (existing?.touristId.trim().isNotEmpty == true)
          ? existing!.touristId
          : resolvedUid,
      profileImageBase64: existing?.profileImageBase64,
      profilePhotoUrl: existing?.profilePhotoUrl,
    );
    debugPrint(
      '[TouristProfile] seeded name from Auth displayName/email for uid=$resolvedUid',
    );
    return UserProfileStorage.getUserProfile();
  }

  static Future<Map<String, dynamic>?> _fetchTouristData({
    required String uid,
    required String email,
  }) async {
    final firestore = FirebaseFirestore.instance;

    // Document id == Auth UID (signup path). Avoid collection queries — rules
    // block list for tourists except own firebaseUid / staff.
    final byDocId = await firestore.collection('tourists').doc(uid).get();
    if (byDocId.exists && byDocId.data() != null) {
      return byDocId.data();
    }

    return null;
  }
}
