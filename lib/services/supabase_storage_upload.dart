import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import 'package:atmos_trs_system/config/supabase_storage_config.dart';
import 'package:atmos_trs_system/config/supabase_upload_config.dart';

/// Uploads bytes to the shared Supabase `tourist-images` bucket (free-tier safe).
class SupabaseStorageUpload {
  SupabaseStorageUpload._();

  /// Bucket policy allows 10 MB. Stay under that so Storage does not reject the file.
  static const int maxImageBytes = 8 * 1024 * 1024;

  /// Folder allowed by the existing `tourist-images` insert policy.
  /// `spots/` is rejected with HTTP 400 / "row-level security policy".
  static const String spotPhotoFolder = 'tourist-spots';

  static const Set<String> allowedImageTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/gif',
  };

  /// Object key that matches the storage policy: `tourist-spots/{spotId}/photo_{time}.ext`.
  static String spotPhotoObjectKey(String spotId, String extension) {
    final safeId = spotId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    if (safeId.isEmpty) {
      throw StateError('This tourist spot cannot store photos.');
    }
    final ext = extension.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (ext.isEmpty) {
      throw StateError('Unsupported photo type. Use JPG, PNG, or WEBP.');
    }
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return '$spotPhotoFolder/$safeId/photo_$stamp.$ext';
  }

  /// Reads the real image type from file bytes. Flutter Web file names are often wrong.
  static String? contentTypeForImageBytes(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return 'image/gif';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }

  static String extensionForContentType(String contentType) {
    switch (contentType) {
      case 'image/png':
        return 'png';
      case 'image/webp':
        return 'webp';
      case 'image/gif':
        return 'gif';
      default:
        return 'jpg';
    }
  }

  /// True only for a photo this spot uploaded under its own folder.
  static bool ownsSpotPhoto(String publicUrl, String spotId) {
    final key = _objectKeyFromPublicUrl(publicUrl);
    if (key == null) return false;
    final safeId = spotId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    if (safeId.isEmpty) return false;
    return key.startsWith('$spotPhotoFolder/$safeId/');
  }

  /// Deletes spot-owned objects that were removed after a successful save.
  static Future<void> deleteReplacedSpotPhotos({
    required String spotId,
    required List<String> previousUrls,
    required List<String> nextUrls,
  }) async {
    final kept = nextUrls.map((url) => url.trim()).toSet();
    for (final url in previousUrls) {
      final trimmed = url.trim();
      if (trimmed.isEmpty || kept.contains(trimmed)) continue;
      if (!ownsSpotPhoto(trimmed, spotId)) continue;
      await deletePublicUrl(trimmed);
    }
  }

  static String storageFailureMessage(int statusCode, String body) {
    final raw = body.trim();
    String? message;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final value = decoded['message'] ?? decoded['error'] ?? decoded['msg'];
        if (value is String && value.trim().isNotEmpty) message = value.trim();
      }
    } catch (_) {}
    message ??= raw;
    if (message.length > 180) message = '${message.substring(0, 180)}…';
    if (message.isEmpty) {
      return 'Photo upload failed ($statusCode).';
    }
    return 'Photo upload failed ($statusCode): $message';
  }

  /// Object key under the bucket, e.g. `establishments/{uid}/photo_123.jpg`.
  static Future<String> uploadBytes({
    required String objectKey,
    required Uint8List bytes,
    required String contentType,
    bool upsert = true,
    void Function(double progress)? onProgress,
  }) async {
    final bearer = SupabaseUploadConfig.uploadBearer;
    if (bearer.isEmpty) {
      throw StateError(
        'Supabase upload is not configured. Run with '
        '--dart-define-from-file=dart_defines.json '
        '(see tools/gen_dart_defines.ps1).',
      );
    }
    if (bytes.isEmpty) {
      throw StateError('That image file is empty.');
    }
    final key = SupabaseStorageConfig.sanitizeObjectKey(
      objectKey.replaceAll('\\', '/').replaceAll(RegExp(r'^/+'), ''),
    );
    if (key.isEmpty) {
      throw StateError('Invalid storage object key.');
    }
    final encodedKey = key
        .split('/')
        .where((s) => s.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    final uri = Uri.parse(
      '${SupabaseUploadConfig.projectUrl}/storage/v1/object/'
      '${SupabaseUploadConfig.bucket}/$encodedKey',
    );
    final request = http.StreamedRequest('POST', uri)
      ..headers.addAll({
        'Authorization': 'Bearer $bearer',
        'apikey': bearer,
        'Content-Type': contentType,
        'cache-control': '3600',
        if (upsert) 'x-upsert': 'true',
      });
    const chunkSize = 16 * 1024;
    var sent = 0;
    onProgress?.call(0);
    for (var offset = 0; offset < bytes.length; offset += chunkSize) {
      final end = offset + chunkSize > bytes.length
          ? bytes.length
          : offset + chunkSize;
      request.sink.add(bytes.sublist(offset, end));
      sent = end;
      onProgress?.call(sent / bytes.length);
    }
    final responseFuture = request.send();
    await request.sink.close();
    final streamed = await responseFuture;
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '[SupabaseUpload] ${response.statusCode} ${response.body}',
      );
      throw StateError(
        storageFailureMessage(response.statusCode, response.body),
      );
    }
    onProgress?.call(1);
    return SupabaseStorageConfig.publicUrlForObjectKey(key);
  }

  /// Spot photo upload: JPG, PNG, WEBP, or GIF, at most 8 MB.
  static Future<String> uploadSpotPhoto({
    required String spotId,
    required Uint8List bytes,
    void Function(double progress)? onProgress,
  }) async {
    if (bytes.length > maxImageBytes) {
      throw StateError('Photo must be 8 MB or smaller.');
    }
    final contentType = contentTypeForImageBytes(bytes);
    if (contentType == null || !allowedImageTypes.contains(contentType)) {
      throw StateError('Use a JPG, PNG, or WEBP photo.');
    }
    return uploadBytes(
      objectKey: spotPhotoObjectKey(spotId, extensionForContentType(contentType)),
      bytes: bytes,
      contentType: contentType,
      onProgress: onProgress,
    );
  }

  static Future<void> deletePublicUrl(String publicUrl) async {
    final key = _objectKeyFromPublicUrl(publicUrl);
    if (key == null) return;
    final bearer = SupabaseUploadConfig.uploadBearer;
    if (bearer.isEmpty) return;
    final encodedKey = key
        .split('/')
        .where((s) => s.isNotEmpty)
        .map(Uri.encodeComponent)
        .join('/');
    final uri = Uri.parse(
      '${SupabaseUploadConfig.projectUrl}/storage/v1/object/'
      '${SupabaseUploadConfig.bucket}/$encodedKey',
    );
    try {
      final response = await http.delete(
        uri,
        headers: {
          'Authorization': 'Bearer $bearer',
          'apikey': bearer,
        },
      );
      if (response.statusCode >= 300) {
        debugPrint(
          '[SupabaseUpload] delete ${response.statusCode} ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('[SupabaseUpload] delete failed (non-fatal): $e');
    }
  }

  static String? _objectKeyFromPublicUrl(String url) {
    final asset = SupabaseStorageConfig.assetPathFromPublicUrl(url);
    if (asset == null) return null;
    // assetPathFromPublicUrl returns `assets/...`
    if (asset.startsWith('assets/')) {
      return asset.substring('assets/'.length);
    }
    return asset;
  }
}
