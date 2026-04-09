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
    try {
      if (Firebase.apps.isEmpty) return local;
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return local;

      final snap =
          await FirebaseFirestore.instance.collection('tourists').doc(u.uid).get();
      final url = snap.data()?['profilePhotoUrl']?.toString().trim();
      if (url == null || url.isEmpty) return local;

      await UserProfileStorage.updateProfilePhotoUrl(url);
      debugPrint('[ProfilePhoto] hydrated from Firestore urlLen=${url.length}');
      return local.withProfilePhotoUrl(url);
    } catch (e, st) {
      debugPrint('[ProfilePhoto] merge failed: $e\n$st');
      return local;
    }
  }
}
