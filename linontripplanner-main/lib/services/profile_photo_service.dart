import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;

import '../firestore_loader.dart'
    show
        fetchTouristFirestoreDataForFirebaseUid,
        kTouristCollection,
        kUsersCollection,
        profileImageBytesFromFirestoreMap,
        profilePhotoSourceFromFirestoreMap;
import 'storage_image_upload.dart';

bool isFirebaseStorageHttpUrl(String url) {
  final lower = url.toLowerCase();
  return lower.contains('firebasestorage.googleapis.com') ||
      lower.contains('firebasestorage.app');
}

/// Extracts object path from a Firebase download URL for [Reference.getData].
String? storagePathFromFirebaseDownloadUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  final segments = uri.pathSegments;
  if (segments.isEmpty) return null;
  final oIndex = segments.indexOf('o');
  if (oIndex < 0 || oIndex >= segments.length - 1) return null;
  final encoded = segments.sublist(oIndex + 1).join('/');
  if (encoded.isEmpty) return null;
  return Uri.decodeComponent(encoded);
}

/// Turns Firestore value into a usable HTTPS download URL (not a Storage path).
Future<String?> normalizeProfilePhotoToDownloadUrl(String raw) async {
  final t = raw.trim();
  if (t.isEmpty) return null;

  if (t.startsWith('http://') || t.startsWith('https://')) {
    // Supabase (and other) public HTTPS URLs — use as-is.
    if (!isFirebaseStorageHttpUrl(t)) {
      return t;
    }
    // Firebase Storage: billing may be closed; do not pretend the URL works.
    try {
      final res = await http
          .head(Uri.parse(t))
          .timeout(const Duration(seconds: 6));
      final ct = (res.headers['content-type'] ?? '').toLowerCase();
      if (res.statusCode == 402 ||
          ct.contains('application/json') ||
          ct.contains('text/html')) {
        debugPrint('normalizeProfilePhoto: dead Firebase Storage URL');
        return null;
      }
    } catch (e) {
      debugPrint('normalizeProfilePhoto probe failed: $e');
      return null;
    }
    return t;
  }

  if (t.startsWith('gs://')) {
    try {
      return await FirebaseStorage.instance.refFromURL(t).getDownloadURL();
    } catch (e) {
      debugPrint('normalizeProfilePhoto gs: $e');
      return null;
    }
  }

  // Value is a Storage object path, e.g. user_profiles/<uid>/face_photo.jpg
  if (t.contains('/') && !t.contains(r':\')) {
    try {
      return await FirebaseStorage.instance.ref(t).getDownloadURL();
    } catch (e) {
      debugPrint('normalizeProfilePhoto storage path "$t": $e');
      return null;
    }
  }

  return null;
}

Future<String?> _getDownloadUrlForRef(String path) async {
  try {
    return await FirebaseStorage.instance
        .ref(path)
        .getDownloadURL()
        .timeout(const Duration(seconds: 6));
  } catch (_) {
    return null;
  }
}

/// Fast Storage lookup — direct paths only (no slow listAll).
Future<String?> resolveProfilePhotoUrlForLookupId(String lookupId) async {
  if (lookupId.isEmpty) return null;
  final paths = <String>[
    'user_profiles/$lookupId/face_photo.jpg',
    'user_profiles/$lookupId/face_photo.jpeg',
    'user_profiles/$lookupId/face_photo.png',
    'profile_photos/$lookupId.jpg',
    'profile_photos/$lookupId.jpeg',
    'profile_photos/$lookupId.png',
  ];
  for (final path in paths) {
    final url = await _getDownloadUrlForRef(path);
    if (url != null && url.isNotEmpty) return url;
  }
  return null;
}

/// Loads raw JPEG bytes from Storage (works when network image fails on web).
Future<Uint8List?> loadProfilePhotoBytesFromStorage(
  String uid, {
  String? downloadUrl,
}) async {
  if (downloadUrl != null && downloadUrl.trim().isNotEmpty) {
    final trimmedUrl = downloadUrl.trim();
    if (!isFirebaseStorageHttpUrl(trimmedUrl) &&
        (trimmedUrl.startsWith('http://') ||
            trimmedUrl.startsWith('https://'))) {
      try {
        final res = await http
            .get(Uri.parse(trimmedUrl))
            .timeout(const Duration(seconds: 12));
        if (res.statusCode >= 200 &&
            res.statusCode < 300 &&
            res.bodyBytes.isNotEmpty) {
          return res.bodyBytes;
        }
      } catch (e) {
        debugPrint('loadProfilePhotoBytes http: $e');
      }
    }
    if (isFirebaseStorageHttpUrl(trimmedUrl)) {
      try {
        final data = await FirebaseStorage.instance
            .refFromURL(trimmedUrl)
            .getData(3 * 1024 * 1024)
            .timeout(const Duration(seconds: 12));
        if (data != null && data.isNotEmpty) return data;
      } catch (e) {
        debugPrint('loadProfilePhotoBytes refFromURL: $e');
      }
    }
    final fromUrl = storagePathFromFirebaseDownloadUrl(trimmedUrl);
    if (fromUrl != null && fromUrl.isNotEmpty) {
      try {
        final data = await FirebaseStorage.instance
            .ref(fromUrl)
            .getData(3 * 1024 * 1024)
            .timeout(const Duration(seconds: 12));
        if (data != null && data.isNotEmpty) return data;
      } catch (e) {
        debugPrint('loadProfilePhotoBytes from path "$fromUrl": $e');
      }
    }
  }

  if (uid.trim().isEmpty) return null;
  final id = uid.trim();
  final paths = [
    'user_profiles/$id/face_photo.jpg',
    'profile_photos/$id.jpg',
  ];
  for (final path in paths) {
    try {
      final data = await FirebaseStorage.instance
          .ref(path)
          .getData(3 * 1024 * 1024)
          .timeout(const Duration(seconds: 12));
      if (data != null && data.isNotEmpty) return data;
    } catch (e) {
      debugPrint('loadProfilePhotoBytes $path: $e');
    }
  }
  return null;
}

/// Loads profile photo URL: Firestore → Storage → Auth `photoURL`.
Future<String?> fetchBestProfilePhotoUrl(String uid) async {
  if (uid.trim().isEmpty) return null;
  final id = uid.trim();

  Future<String?> fromDoc(Map<String, dynamic>? data) async {
    if (data == null) return null;
    final raw = profilePhotoSourceFromFirestoreMap(data);
    if (raw.isEmpty) return null;
    return normalizeProfilePhotoToDownloadUrl(raw);
  }

  try {
    return await _fetchBestProfilePhotoUrlInner(id, fromDoc).timeout(
      const Duration(seconds: 12),
      onTimeout: () {
        debugPrint('fetchBestProfilePhotoUrl: timed out for $id');
        return null;
      },
    );
  } on TimeoutException {
    return null;
  } catch (e) {
    debugPrint('fetchBestProfilePhotoUrl: $e');
    return null;
  }
}

Future<String?> _fetchBestProfilePhotoUrlInner(
  String id,
  Future<String?> Function(Map<String, dynamic>?) fromDoc,
) async {
  final auth = FirebaseAuth.instance.currentUser;

  try {
    final user = await FirebaseFirestore.instance
        .collection(kUsersCollection)
        .doc(id)
        .get()
        .timeout(const Duration(seconds: 8));
    if (user.exists) {
      final url = await fromDoc(user.data());
      if (url != null && url.isNotEmpty) {
        debugPrint('profile photo: users/$id');
        return url;
      }
    }
  } catch (e) {
    debugPrint('fetchBestProfilePhotoUrl users/$id: $e');
  }

  try {
    final tourist = await FirebaseFirestore.instance
        .collection(kTouristCollection)
        .doc(id)
        .get()
        .timeout(const Duration(seconds: 8));
    if (tourist.exists) {
      final url = await fromDoc(tourist.data());
      if (url != null && url.isNotEmpty) {
        debugPrint('profile photo: tourists/$id');
        return url;
      }
    }
  } catch (e) {
    debugPrint('fetchBestProfilePhotoUrl tourists/$id: $e');
  }

  final fromStorage = await resolveProfilePhotoUrlForLookupId(id);
  if (fromStorage != null && fromStorage.isNotEmpty) {
    debugPrint('profile photo: storage $id');
    return fromStorage;
  }

  if (auth != null && auth.uid == id) {
    final authUrl = auth.photoURL?.trim() ?? '';
    if (authUrl.isNotEmpty) {
      final refreshed = await normalizeProfilePhotoToDownloadUrl(authUrl);
      if (refreshed != null && refreshed.isNotEmpty) return refreshed;
    }
  }

  return null;
}

/// Uploads face photo to Supabase and saves `profilePhotoUrl` on `users` + `tourists`.
Future<String?> uploadAndSaveProfilePhoto({
  required String uid,
  required Uint8List bytes,
}) async {
  if (uid.trim().isEmpty || bytes.isEmpty) return null;
  final id = uid.trim();

  try {
    final url = await uploadUserProfileImage(bytes, 'user_profiles/$id');

    final auth = FirebaseAuth.instance.currentUser;
    if (auth != null && auth.uid == id) {
      try {
        await auth.updatePhotoURL(url);
      } catch (e) {
        debugPrint('uploadAndSaveProfilePhoto updatePhotoURL: $e');
      }
    }

    final patch = {
      'profilePhotoUrl': url,
      'photoURL': url,
      'firebaseUid': id,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await FirebaseFirestore.instance
        .collection(kUsersCollection)
        .doc(id)
        .set(patch, SetOptions(merge: true));

    await FirebaseFirestore.instance
        .collection(kTouristCollection)
        .doc(id)
        .set(patch, SetOptions(merge: true));

    debugPrint('uploadAndSaveProfilePhoto ok $id');
    return url;
  } catch (e) {
    debugPrint('uploadAndSaveProfilePhoto failed: $e');
    return null;
  }
}

/// Use Storage bytes when network URL fails (common on Flutter web + Firebase).
bool shouldFallbackProfilePhotoToBytes(String? downloadUrl) => kIsWeb;

bool profilePhotoUrlLooksReady(Map<String, dynamic> data) {
  final url = profilePhotoSourceFromFirestoreMap(data).trim();
  return url.startsWith('http://') || url.startsWith('https://');
}

/// Profile face from Firestore inline base64 or Storage URL.
Future<Uint8List?> fetchProfilePhotoBytesForUid(String uid) async {
  if (uid.trim().isEmpty) return null;
  final id = uid.trim();

  try {
    final user = await FirebaseFirestore.instance
        .collection(kUsersCollection)
        .doc(id)
        .get();
    if (user.exists) {
      final bytes = profileImageBytesFromFirestoreMap(user.data());
      if (bytes != null) return bytes;
    }
  } catch (e) {
    debugPrint('fetchProfilePhotoBytes users/$id: $e');
  }

  try {
    final touristData = await fetchTouristFirestoreDataForFirebaseUid(id);
    if (touristData != null) {
      final bytes = profileImageBytesFromFirestoreMap(touristData);
      if (bytes != null) return bytes;
    }
  } catch (e) {
    debugPrint('fetchProfilePhotoBytes tourists/$id: $e');
  }

  final url = await fetchBestProfilePhotoUrl(id);
  if (url != null && url.isNotEmpty) {
    return loadProfilePhotoBytesFromStorage(id, downloadUrl: url);
  }
  return null;
}

/// Firestore `profilePhotoUrl` when it is already an HTTPS link (no async refresh).
String? httpProfilePhotoUrlFromMap(Map<String, dynamic>? data) {
  if (data == null) return null;
  final raw = profilePhotoSourceFromFirestoreMap(data);
  if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
  return null;
}

/// Copies `profilePhotoUrl` between `tourists/{uid}` and `users/{uid}` so Profile can read it.
Future<String?> syncProfilePhotoUrlForUid(String uid) async {
  if (uid.trim().isEmpty) return null;
  final id = uid.trim();
  final userRef =
      FirebaseFirestore.instance.collection(kUsersCollection).doc(id);
  final touristRef =
      FirebaseFirestore.instance.collection(kTouristCollection).doc(id);

  Map<String, dynamic>? userData;
  Map<String, dynamic>? touristData;
  try {
    final userSnap = await userRef.get();
    if (userSnap.exists) userData = userSnap.data();
  } catch (e) {
    debugPrint('syncProfilePhotoUrl users/$id: $e');
  }
  try {
    touristData = await fetchTouristFirestoreDataForFirebaseUid(id);
  } catch (e) {
    debugPrint('syncProfilePhotoUrl tourists/$id: $e');
  }

  final inlineBytes = profileImageBytesFromFirestoreMap(userData) ??
      profileImageBytesFromFirestoreMap(touristData);
  if (inlineBytes != null && inlineBytes.isNotEmpty) {
    try {
      final uploaded = await uploadAndSaveProfilePhoto(
        uid: id,
        bytes: inlineBytes,
      );
      if (uploaded != null && uploaded.isNotEmpty) return uploaded;
    } catch (e) {
      debugPrint('syncProfilePhotoUrl upload base64: $e');
    }
  }

  Future<String> urlFromMap(Map<String, dynamic>? data) async {
    if (data == null) return '';
    final http = httpProfilePhotoUrlFromMap(data);
    if (http != null && http.isNotEmpty) return http;
    final raw = profilePhotoSourceFromFirestoreMap(data);
    if (raw.isEmpty) return '';
    final normalized = await normalizeProfilePhotoToDownloadUrl(raw);
    return normalized?.trim() ?? '';
  }

  final userUrl = await urlFromMap(userData);
  final touristUrl = await urlFromMap(touristData);
  var best = userUrl.isNotEmpty ? userUrl : touristUrl;
  if (best.isEmpty) {
    best = await resolveProfilePhotoUrlForLookupId(id) ?? '';
  }
  if (best.isEmpty) {
    final auth = FirebaseAuth.instance.currentUser;
    if (auth != null && auth.uid == id) {
      final authUrl = auth.photoURL?.trim() ?? '';
      if (authUrl.isNotEmpty) {
        best = await normalizeProfilePhotoToDownloadUrl(authUrl) ?? authUrl;
      }
    }
  }
  if (best.isEmpty) return null;

  final patch = {
    'profilePhotoUrl': best,
    'photoURL': best,
    'profilePhotoPending': false,
    'updatedAt': FieldValue.serverTimestamp(),
  };
  try {
    if (userUrl.isEmpty) {
      await userRef.set(
        {...patch, 'firebaseUid': id},
        SetOptions(merge: true),
      );
    } else if (userUrl != best) {
      await userRef.set(patch, SetOptions(merge: true));
    }
    if (touristUrl.isEmpty) {
      await touristRef.set(
        {...patch, 'firebaseUid': id, 'touristID': id, 'touristId': id},
        SetOptions(merge: true),
      );
    }
  } catch (e) {
    debugPrint('syncProfilePhotoUrl write $id: $e');
  }

  final auth = FirebaseAuth.instance.currentUser;
  if (auth != null && auth.uid == id && (auth.photoURL ?? '').trim() != best) {
    try {
      await auth.updatePhotoURL(best);
    } catch (_) {}
  }

  return best;
}
