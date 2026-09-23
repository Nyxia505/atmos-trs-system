import 'dart:convert';

import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show compute, debugPrint;
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

  static Future<TouristProfilePhotoUploadResult?> uploadBytes({
    required String uid,
    required Uint8List rawBytes,
  }) async {
    if (rawBytes.isEmpty) return null;
    final compressed = await compute(
      compressProfileJpegIsolate,
      ProfileJpegCompressArgs(rawBytes, 800, 78),
    );
    if (compressed.isEmpty) return null;

    TouristProfilePhotoUploadResult? result;
    try {
      final storageRef =
          FirebaseStorage.instance.ref().child('profile_photos/$uid.jpg');
      final uploadTask = await storageRef.putData(
        compressed,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final url = await uploadTask.ref.getDownloadURL();
      result = TouristProfilePhotoUploadResult(profilePhotoUrl: url);
    } on FirebaseException catch (e, st) {
      if (!_storageShouldUseFirestoreFallback(e)) {
        debugPrint(
          '[ProfilePhoto] Storage fail plugin=${e.plugin} code=${e.code}: $e\n$st',
        );
        rethrow;
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
        debugPrint('[ProfilePhoto] photo too large for Firestore fallback');
        return null;
      }
      result = TouristProfilePhotoUploadResult(
        profileImageBase64: b64,
        usedFirestoreFallback: true,
      );
    }

    await _persistToFirestoreAndLocal(uid: uid, result: result);
    return result;
  }

  static Future<void> _persistToFirestoreAndLocal({
    required String uid,
    required TouristProfilePhotoUploadResult result,
  }) async {
    final url = result.profilePhotoUrl?.trim();
    final b64 = result.profileImageBase64;
    final patch = <String, dynamic>{
      'profilePhotoPending': result.usedFirestoreFallback,
      if (url != null && url.isNotEmpty) 'profilePhotoUrl': url,
      if (b64 != null && b64.isNotEmpty) 'profileImageBase64': b64,
    };
    if (url != null && url.isNotEmpty) {
      patch['profileImageBase64'] = FieldValue.delete();
    }

    if (Firebase.apps.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('tourists')
            .doc(uid)
            .set(patch, SetOptions(merge: true));
      } catch (e, st) {
        debugPrint('[ProfilePhoto] tourists write failed: $e\n$st');
      }
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .set(
              {
                if (url != null && url.isNotEmpty) 'profilePhotoUrl': url,
              },
              SetOptions(merge: true),
            );
      } catch (_) {}
    }

    if (url != null && url.isNotEmpty) {
      await UserProfileStorage.updateProfilePhotoUrl(url);
      return;
    }

    final local = await UserProfileStorage.getUserProfile();
    if (local == null || b64 == null || b64.isEmpty) return;

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
      profilePhotoUrl: local.profilePhotoUrl,
    );
  }
}
