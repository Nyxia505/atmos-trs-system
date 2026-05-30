import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:atmos_trs_system/config/user_profile_storage.dart';

/// Merges `tourists/{uid}.profilePhotoUrl` from Firestore into local [UserProfile]
/// and caches the URL in SharedPreferences so [Image.network] can display it.
class ProfilePhotoHydration {
  ProfilePhotoHydration._();

  static Future<UserProfile?> mergeFirestorePhotoUrl(UserProfile? local) async {
    if (local == null) return null;
    if (local.firstName.trim().isEmpty) return local;
    try {
      if (Firebase.apps.isEmpty) return local;
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return local;

      final snap =
          await FirebaseFirestore.instance.collection('tourists').doc(u.uid).get();
      final data = snap.data();
      if (data == null) return local;

      final url = data['profilePhotoUrl']?.toString().trim();
      if (url != null && url.isNotEmpty) {
        await UserProfileStorage.updateProfilePhotoUrl(url);
        debugPrint('[ProfilePhoto] hydrated from Firestore urlLen=${url.length}');
        return local.withProfilePhotoUrl(url);
      }

      final b64 = data['profileImageBase64']?.toString();
      if (b64 != null &&
          b64.isNotEmpty &&
          b64.length <= UserProfileStorage.maxProfileImageBase64Length) {
        await UserProfileStorage.saveUserProfile(
          firstName: local.firstName,
          middleName: local.middleName,
          lastName: local.lastName,
          suffix: local.suffix,
          sex: local.sex,
          civilStatus: local.civilStatus,
          nationality: local.nationality,
          dateOfBirth: local.dateOfBirth,
          mobile: local.mobile,
          email: local.email,
          country: local.country,
          province: local.province,
          city: local.city,
          street: local.street,
          barangay: local.barangay,
          touristId: local.touristId,
          profileImageBase64: b64,
        );
        debugPrint('[ProfilePhoto] hydrated from Firestore base64 len=${b64.length}');
        final refreshed = await UserProfileStorage.getUserProfile();
        return refreshed ?? local;
      }

      return local;
    } catch (e, st) {
      debugPrint('[ProfilePhoto] merge failed: $e\n$st');
      return local;
    }
  }
}
