import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_selector/file_selector.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:image_picker/image_picker.dart';

import 'package:atmos_trs_system/config/supabase_upload_config.dart';
import 'package:atmos_trs_system/services/establishment_firestore_write.dart';
import 'package:atmos_trs_system/services/establishment_registration_service.dart';
import 'package:atmos_trs_system/services/firestore_auth_gate.dart';
import 'package:atmos_trs_system/services/supabase_storage_upload.dart';

/// Gallery photos on `accommodation_establishments.galleryUrls`.
///
/// Files live in Supabase Storage under `uploads/establishments/{uid}/…`
/// (that prefix is allowed by the existing `tourist-images` insert policy).
class EstablishmentGalleryService {
  EstablishmentGalleryService._();

  static const int maxImages = 8;
  static const String fieldGalleryUrls = 'galleryUrls';
  static const String fieldCoverImageUrl = 'coverImageUrl';

  static const XTypeGroup _imageTypeGroup = XTypeGroup(
    label: 'Images',
    extensions: <String>['jpg', 'jpeg', 'png', 'webp'],
    mimeTypes: <String>['image/jpeg', 'image/png', 'image/webp'],
    webWildCards: <String>['image/*'],
  );

  static CollectionReference<Map<String, dynamic>> get _estCol =>
      FirebaseFirestore.instance
          .collection(EstablishmentRegistrationService.establishmentsCollection);

  static List<String> parseUrls(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((e) =>
            e.startsWith('http') || e.startsWith('data:image'))
        .toList();
  }

  static Future<List<String>> loadUrls(String establishmentId) async {
    final id = establishmentId.trim();
    if (id.isEmpty) return const [];
    try {
      final doc = await _estCol.doc(id).get();
      final d = doc.data() ?? const <String, dynamic>{};
      final urls = parseUrls(d[fieldGalleryUrls]);
      if (urls.isNotEmpty) return urls;
      final cover = (d[fieldCoverImageUrl] ?? '').toString().trim();
      if (cover.startsWith('http') || cover.startsWith('data:image')) {
        return [cover];
      }
      return const [];
    } catch (e) {
      debugPrint('[EstGallery] loadUrls: $e');
      return const [];
    }
  }

  static Stream<List<String>> watchUrls(String establishmentId) {
    final id = establishmentId.trim();
    if (id.isEmpty) return Stream.value(const []);
    return _estCol.doc(id).snapshots().map((doc) {
      final d = doc.data() ?? const <String, dynamic>{};
      final urls = parseUrls(d[fieldGalleryUrls]);
      if (urls.isNotEmpty) return urls;
      final cover = (d[fieldCoverImageUrl] ?? '').toString().trim();
      if (cover.startsWith('http') || cover.startsWith('data:image')) {
        return [cover];
      }
      return const [];
    });
  }

  /// Opens a file picker, uploads PNG/JPG/WEBP, appends public URLs on the AE
  /// doc. Returns `null` when the user cancels; otherwise the new URL list.
  static Future<List<String>?> pickAndUpload({
    required String establishmentId,
    required List<String> currentUrls,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Sign in to upload photos.');
    }
    if (establishmentId.trim() != uid) {
      throw StateError('Only the establishment owner can upload photos.');
    }
    if (currentUrls.length >= maxImages) {
      throw StateError('Maximum $maxImages photos.');
    }
    if (!SupabaseUploadConfig.hasUploadCredentials) {
      throw StateError(
        'Photo storage is not configured. Restart the app and try again.',
      );
    }

    final remaining = maxImages - currentUrls.length;
    final picked = await _pickImages(maxCount: remaining);
    if (picked.isEmpty) return null;

    final next = List<String>.from(currentUrls);
    Object? lastError;
    for (final file in picked) {
      if (next.length >= maxImages) break;
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) {
          throw StateError('Could not read that image.');
        }
        if (bytes.length > SupabaseStorageUpload.maxImageBytes) {
          throw StateError('Photo must be 8 MB or smaller.');
        }
        final url = await _uploadBytes(
          uid: uid,
          bytes: bytes,
          fileName: file.name,
        );
        next.add(url);
      } catch (e) {
        lastError = e;
        debugPrint('[EstGallery] upload one failed: $e');
      }
    }
    if (next.length == currentUrls.length) {
      throw StateError(
        lastError == null
            ? 'Could not read those photos. Use PNG or JPG.'
            : lastError.toString().replaceFirst('Bad state: ', ''),
      );
    }

    try {
      await FirestoreAuthGate.ensureFreshIdToken(forceRefresh: false);
      await _persist(uid, next).timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('[EstGallery] persist delayed: $e');
      unawaited(
        _persist(uid, next).catchError((Object err) {
          debugPrint('[EstGallery] persist retry: $err');
        }),
      );
    }
    return next;
  }

  static Future<List<String>> removeAt({
    required String establishmentId,
    required List<String> currentUrls,
    required int index,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Sign in to manage photos.');
    }
    if (establishmentId.trim() != uid) {
      throw StateError('Only the establishment owner can remove photos.');
    }
    if (index < 0 || index >= currentUrls.length) return currentUrls;
    final removed = currentUrls[index];
    final next = List<String>.from(currentUrls)..removeAt(index);
    await _persist(uid, next);
    await SupabaseStorageUpload.deletePublicUrl(removed);
    return next;
  }

  static Future<List<XFile>> _pickImages({required int maxCount}) async {
    if (maxCount <= 0) return const [];
    try {
      final files = await openFiles(
        acceptedTypeGroups: const [_imageTypeGroup],
      );
      if (files.isEmpty) return const [];
      return files.take(maxCount).toList(growable: false);
    } catch (e) {
      debugPrint('[EstGallery] file_selector: $e');
    }
    try {
      if (maxCount == 1) {
        final one = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          imageQuality: 85,
          maxWidth: 1600,
        );
        return one == null ? const [] : [one];
      }
      final many = await ImagePicker().pickMultiImage(
        imageQuality: 85,
        maxWidth: 1600,
        limit: maxCount,
      );
      return many.take(maxCount).toList(growable: false);
    } catch (e) {
      debugPrint('[EstGallery] image_picker: $e');
      throw StateError(
        kIsWeb
            ? 'Could not open the photo picker. Try another browser.'
            : 'Could not open the photo picker. Choose a PNG or JPG file.',
      );
    }
  }

  static Future<String> _uploadBytes({
    required String uid,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final contentType = SupabaseStorageUpload.contentTypeForImageBytes(bytes) ??
        _contentTypeFromName(fileName);
    if (contentType == null ||
        !SupabaseStorageUpload.allowedImageTypes.contains(contentType)) {
      throw StateError('Use a PNG, JPG, or WEBP photo.');
    }
    return SupabaseStorageUpload.uploadBytes(
      objectKey: SupabaseStorageUpload.establishmentPhotoObjectKey(
        uid,
        SupabaseStorageUpload.extensionForContentType(contentType),
      ),
      bytes: bytes,
      contentType: contentType,
    );
  }

  static String? _contentTypeFromName(String fileName) {
    final name = fileName.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.gif')) return 'image/gif';
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    return null;
  }

  static Future<void> _persist(String uid, List<String> urls) async {
    await EstablishmentFirestoreWrite.mergeFields(uid, {
      fieldGalleryUrls: urls,
      fieldCoverImageUrl: urls.isEmpty ? '' : urls.first,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
