import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'package:atmos_trs_system/config/supabase_upload_config.dart';
import 'package:atmos_trs_system/services/establishment_firestore_write.dart';
import 'package:atmos_trs_system/services/establishment_registration_service.dart';
import 'package:atmos_trs_system/services/firestore_auth_gate.dart';
import 'package:atmos_trs_system/services/supabase_storage_upload.dart';

/// Gallery photos on `accommodation_establishments.galleryUrls`.
///
/// Files live in Supabase Storage (`tourist-images/establishments/{uid}/…`),
/// same bucket as other tourist photos — not Firebase Storage.
class EstablishmentGalleryService {
  EstablishmentGalleryService._();

  static const int maxImages = 8;
  static const String fieldGalleryUrls = 'galleryUrls';
  static const String fieldCoverImageUrl = 'coverImageUrl';

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

  /// Picks one image, uploads to Supabase, appends public URL on the AE doc.
  static Future<List<String>> pickAndUpload({
    required String establishmentId,
    required List<String> currentUrls,
  }) async {
    // #region agent log
    Future<void> _dbg(String hypothesisId, String message, Map<String, Object?> data) async {
      final payload = <String, Object?>{
        'sessionId': 'b96d41',
        'runId': 'post-fix',
        'hypothesisId': hypothesisId,
        'location': 'establishment_gallery_service.dart:pickAndUpload',
        'message': message,
        'data': data,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      debugPrint('[DBG-b96d41] $message $data');
      try {
        // Fire-and-forget so ingest never blocks picker / snackbars.
        // ignore: unawaited_futures
        http
            .post(
              Uri.parse(
                'http://127.0.0.1:7368/ingest/51ca25ca-c2cb-4a1d-9579-1fa102df2fe9',
              ),
              headers: {
                'Content-Type': 'application/json',
                'X-Debug-Session-Id': 'b96d41',
              },
              body: jsonEncode(payload),
            )
            .timeout(const Duration(milliseconds: 800))
            .catchError((_) => http.Response('', 500));
      } catch (_) {}
    }
    // #endregion

    final uid = FirebaseAuth.instance.currentUser?.uid;
    // #region agent log
    await _dbg('A', 'pickAndUpload entry', {
      'kIsWeb': kIsWeb,
      'hasUid': uid != null && uid.isNotEmpty,
      'estIdMatchesUid':
          uid != null && uid.isNotEmpty && establishmentId.trim() == uid,
      'currentUrlCount': currentUrls.length,
      'authMode': SupabaseUploadConfig.authModeLabel(),
      'hasUploadCredentials': SupabaseUploadConfig.hasUploadCredentials,
      'anonKeyPresent': SupabaseUploadConfig.anonKey.isNotEmpty,
      'serviceRoleKeyPresent': SupabaseUploadConfig.serviceRoleKey.isNotEmpty,
      'anonKeyLen': SupabaseUploadConfig.anonKey.length,
      'serviceRoleKeyLen': SupabaseUploadConfig.serviceRoleKey.length,
    });
    // #endregion
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
      // #region agent log
      await _dbg('A', 'blocked: missing upload credentials', {
        'authMode': SupabaseUploadConfig.authModeLabel(),
        'reason': 'no dart-define and empty supabase_secrets.local.dart',
      });
      // #endregion
      throw StateError(
        'Supabase is not configured for uploads. '
        'Run tools/gen_dart_defines.ps1 once, then hot restart.',
      );
    }

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 72,
      maxWidth: 1280,
    );
    // #region agent log
    await _dbg('C', 'image picker result', {
      'picked': picked != null,
      'nameLen': picked?.name.length ?? 0,
    });
    // #endregion
    if (picked == null) return currentUrls;

    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('Could not read that image.');
    }

    final url = await _uploadBytes(
      uid: uid,
      bytes: bytes,
      fileName: picked.name,
    );
    // #region agent log
    await _dbg('D', 'upload succeeded', {
      'urlHost': Uri.tryParse(url)?.host ?? '',
      'urlPathPrefix':
          (Uri.tryParse(url)?.path ?? '').split('/').take(5).join('/'),
    });
    // #endregion
    final next = [...currentUrls, url];
    // #region agent log
    await _dbg('E', 'persist starting', {
      'urlCount': next.length,
      'uidLen': uid.length,
      'via': kIsWeb ? 'rest' : 'sdk',
    });
    // #endregion
    try {
      // Cached token only — force refresh was timing out and delaying saves.
      final tokenOk =
          await FirestoreAuthGate.ensureFreshIdToken(forceRefresh: false);
      // #region agent log
      await _dbg('E', 'persist auth gate', {'tokenOk': tokenOk});
      // #endregion
      await _persist(uid, next).timeout(const Duration(seconds: 8));
      // #region agent log
      await _dbg('E', 'persist succeeded', {
        'urlCount': next.length,
        'via': kIsWeb ? 'rest' : 'sdk',
      });
      // #endregion
    } catch (e) {
      // #region agent log
      await _dbg('E', 'persist failed', {
        'errorType': e.runtimeType.toString(),
        'error': e.toString().length > 180
            ? e.toString().substring(0, 180)
            : e.toString(),
      });
      // #endregion
      throw StateError(
        'Photo is on storage, but profile save is slow/failed. '
        'Try again in a moment. ($e)',
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

  static Future<String> _uploadBytes({
    required String uid,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final name = fileName.toLowerCase();
    final ext = name.endsWith('.png')
        ? 'png'
        : name.endsWith('.webp')
            ? 'webp'
            : 'jpg';
    final contentType = ext == 'png'
        ? 'image/png'
        : ext == 'webp'
            ? 'image/webp'
            : 'image/jpeg';
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final objectKey = 'establishments/$uid/photo_$stamp.$ext';
    return SupabaseStorageUpload.uploadBytes(
      objectKey: objectKey,
      bytes: bytes,
      contentType: contentType,
    );
  }

  static Future<void> _persist(String uid, List<String> urls) async {
    await EstablishmentFirestoreWrite.mergeFields(uid, {
      fieldGalleryUrls: urls,
      fieldCoverImageUrl: urls.isEmpty ? '' : urls.first,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
