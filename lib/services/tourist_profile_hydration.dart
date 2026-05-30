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
  static Future<UserProfile?> loadProfile({
    String? uid,
    String? email,
  }) async {
    var profile = await UserProfileStorage.getUserProfile();
    if (profile != null && profile.firstName.trim().isNotEmpty) {
      return profile;
    }
    return hydrateFromFirestore(uid: uid, email: email);
  }

  static Future<Map<String, dynamic>?> _fetchTouristData({
    required String uid,
    required String email,
  }) async {
    final firestore = FirebaseFirestore.instance;

    final byDocId = await firestore.collection('tourists').doc(uid).get();
    if (byDocId.exists && byDocId.data() != null) {
      return byDocId.data();
    }

    final byFirebaseUid = await firestore
        .collection('tourists')
        .where('firebaseUid', isEqualTo: uid)
        .limit(1)
        .get();
    if (byFirebaseUid.docs.isNotEmpty) {
      return byFirebaseUid.docs.first.data();
    }

    if (email.isNotEmpty) {
      final byEmail = await firestore
          .collection('tourists')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (byEmail.docs.isNotEmpty) {
        return byEmail.docs.first.data();
      }
    }

    return null;
  }
}
