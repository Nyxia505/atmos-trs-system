import 'dart:async';
import 'dart:convert';

import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show compute, debugPrint, kIsWeb;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class ProfileJpegCompressArgs {
  const ProfileJpegCompressArgs(this.bytes, this.maxSide, this.quality);

  final Uint8List bytes;
  final int maxSide;
  final int quality;
}

/// Top-level entry for [compute] — keeps JPEG work off the UI isolate.
Uint8List compressProfileJpegIsolate(ProfileJpegCompressArgs args) {
  return TouristProfilePhotoService.compressJpeg(
    args.bytes,
    maxSide: args.maxSide,
    quality: args.quality,
  );
}

class TouristProfilePhotoUploadResult {
  const TouristProfilePhotoUploadResult({
    this.profilePhotoUrl,
    this.profileImageBase64,
    this.usedFirestoreFallback = false,
  });

  final String? profilePhotoUrl;
  final String? profileImageBase64;
  final bool usedFirestoreFallback;

  bool get hasPhoto =>
      (profilePhotoUrl != null && profilePhotoUrl!.isNotEmpty) ||
      (profileImageBase64 != null && profileImageBase64!.isNotEmpty);
}

/// Compress + upload tourist profile photos (Storage URL or Firestore base64).
class TouristProfilePhotoService {
  TouristProfilePhotoService._();

  static Uint8List compressJpeg(
    Uint8List raw, {
    int maxSide = 1024,
    int quality = 82,
  }) {
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return raw;
      var work = decoded;
      if (work.width > maxSide || work.height > maxSide) {
        if (work.width >= work.height) {
          work = img.copyResize(work, width: maxSide);
        } else {
          work = img.copyResize(work, height: maxSide);
        }
      }
      return Uint8List.fromList(img.encodeJpg(work, quality: quality));
    } catch (e, st) {
      debugPrint('Profile image compress skipped: $e $st');
      return raw;
    }
  }

  static String? base64ForFirestore(Uint8List jpegBytes) {
    var bytes = jpegBytes;
    var encoded = base64Encode(bytes);
    if (encoded.length <= UserProfileStorage.maxProfileImageBase64Length) {
      return encoded;
    }
    bytes = compressJpeg(bytes, maxSide: 512, quality: 70);
    encoded = base64Encode(bytes);
    if (encoded.length <= UserProfileStorage.maxProfileImageBase64Length) {
      return encoded;
    }
    bytes = compressJpeg(bytes, maxSide: 384, quality: 60);
    encoded = base64Encode(bytes);
    if (encoded.length <= UserProfileStorage.maxProfileImageBase64Length) {
      return encoded;
    }
    return null;
  }

  static bool _storageShouldUseFirestoreFallback(FirebaseException e) {
    if (e.plugin != 'firebase_storage') return false;
    const fallbackCodes = {
      'quota-exceeded',
      'unauthorized',
      'unauthenticated',
      'retry-limit-exceeded',
      'bucket-not-found',
      'project-not-found',
      'object-not-found',
      'canceled',
      'unavailable',
      'unknown',
    };
    if (fallbackCodes.contains(e.code)) return true;
    final m = (e.message ?? '').toLowerCase();
    return m.contains('billing') ||
        m.contains('delinquent') ||
        m.contains('402') ||
        m.contains('payment') ||
        m.contains('terminated the upload');
  }

  static const Duration _storageUploadTimeout = Duration(seconds: 15);
  static const Duration _firestoreWriteTimeout = Duration(seconds: 12);

  /// Web picks are already resized by the browser (canvas); decoding them again
  /// with `package:image` runs on the UI thread there and freezes the page.
  static const int _webSkipCompressBelowBytes = 600 * 1024;

  static Future<Uint8List> _prepareJpeg(Uint8List rawBytes) async {
    if (kIsWeb) {
      if (rawBytes.length <= _webSkipCompressBelowBytes) return rawBytes;
      return compressJpeg(rawBytes, maxSide: 800, quality: 78);
    }
    return compute(
      compressProfileJpegIsolate,
      ProfileJpegCompressArgs(rawBytes, 800, 78),
    );
  }

  /// Compresses, uploads to Storage (15 s cap), falls back to Firestore base64,
  /// then saves the result to Firestore + local profile.
  ///
  /// Throws when the photo could not be saved anywhere.
  static Future<TouristProfilePhotoUploadResult> uploadBytes({
    required String uid,
    required Uint8List rawBytes,
  }) async {
    if (rawBytes.isEmpty) {
      throw StateError('No photo data to upload.');
    }
    final compressed = await _prepareJpeg(rawBytes);
    if (compressed.isEmpty) {
      throw StateError('Could not read this photo. Try another one.');
    }

    final previousUrl = UserProfileStorage.cachedProfile?.profilePhotoUrl;
    TouristProfilePhotoUploadResult? result;
    try {
      final url = await _uploadToStorage(uid: uid, bytes: compressed);
      result = TouristProfilePhotoUploadResult(profilePhotoUrl: url);
    } on FirebaseException catch (e, st) {
      if (!_storageShouldUseFirestoreFallback(e)) {
        debugPrint(
          '[ProfilePhoto] Storage fail plugin=${e.plugin} code=${e.code}: $e\n$st',
        );
      }
      debugPrint(
        '[ProfilePhoto] Storage unavailable (${e.code}); Firestore base64 fallback',
      );
    } catch (e, st) {
      debugPrint('[ProfilePhoto] Storage error; trying Firestore fallback: $e\n$st');
    }

    if (result == null) {
      final b64 = base64ForFirestore(compressed);
      if (b64 == null) {
        throw StateError('This photo is too large. Try a smaller one.');
      }
      result = TouristProfilePhotoUploadResult(
        profileImageBase64: b64,
        usedFirestoreFallback: true,
      );
    }

    await _persistToFirestoreAndLocal(uid: uid, result: result);

    final newUrl = result.profilePhotoUrl;
    if (newUrl != null && previousUrl != null && previousUrl != newUrl) {
      unawaited(_deleteOldStoragePhoto(previousUrl));
    }
    return result;
  }

  /// Unique object name per upload so the new download URL never hits a cached
  /// copy of the previous photo.
  static Future<String> _uploadToStorage({
    required String uid,
    required Uint8List bytes,
  }) async {
    final storage = FirebaseStorage.instance;
    storage.setMaxUploadRetryTime(_storageUploadTimeout);
    storage.setMaxOperationRetryTime(_storageUploadTimeout);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final ref = storage.ref().child('profile_photos/${uid}_$stamp.jpg');
    final task = ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    final snapshot = await task.timeout(
      _storageUploadTimeout,
      onTimeout: () async {
        try {
          await task.cancel();
        } catch (_) {}
        throw TimeoutException('Storage upload timed out', _storageUploadTimeout);
      },
    );
    return snapshot.ref.getDownloadURL().timeout(const Duration(seconds: 10));
  }

  static Future<void> _deleteOldStoragePhoto(String url) async {
    if (!url.contains('profile_photos')) return;
    try {
      await FirebaseStorage.instance.refFromURL(url).delete();
    } catch (e) {
      debugPrint('[ProfilePhoto] old photo cleanup skipped: $e');
    }
  }

  static Future<void> _persistToFirestoreAndLocal({
    required String uid,
    required TouristProfilePhotoUploadResult result,
  }) async {
    final url = result.profilePhotoUrl?.trim();
    final b64 = result.profileImageBase64;
    final hasUrl = url != null && url.isNotEmpty;
    // A stale profilePhotoUrl would win over the new base64 in every avatar.
    final patch = <String, dynamic>{
      'profilePhotoPending': result.usedFirestoreFallback,
      'profilePhotoUrl': hasUrl ? url : FieldValue.delete(),
      'profileImageBase64':
          (!hasUrl && b64 != null && b64.isNotEmpty) ? b64 : FieldValue.delete(),
    };

    if (Firebase.apps.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('tourists')
            .doc(uid)
            .set(patch, SetOptions(merge: true))
            .timeout(_firestoreWriteTimeout);
      } catch (e, st) {
        debugPrint('[ProfilePhoto] tourists write failed: $e\n$st');
        throw StateError(
          'Could not save your photo. Check your internet connection.',
        );
      }
      unawaited(
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set(
              {'profilePhotoUrl': hasUrl ? url : FieldValue.delete()},
              SetOptions(merge: true),
            )
            .catchError((Object _) {}),
      );
    }

    if (hasUrl) {
      await UserProfileStorage.updateProfilePhotoUrl(url);
    } else if (b64 != null && b64.isNotEmpty) {
      await UserProfileStorage.updateProfileImageBase64(b64);
    }
  }
}
