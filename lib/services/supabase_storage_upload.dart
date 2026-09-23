import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import 'package:atmos_trs_system/config/supabase_storage_config.dart';
import 'package:atmos_trs_system/config/supabase_upload_config.dart';

/// Uploads bytes to the shared Supabase `tourist-images` bucket (free-tier safe).
class SupabaseStorageUpload {
  SupabaseStorageUpload._();

  /// Object key under the bucket, e.g. `establishments/{uid}/photo_123.jpg`.
  static Future<String> uploadBytes({
    required String objectKey,
    required Uint8List bytes,
    required String contentType,
    bool upsert = true,
  }) async {
    final bearer = SupabaseUploadConfig.uploadBearer;
    if (bearer.isEmpty) {
      throw StateError(
        'Supabase upload is not configured. Run with '
        '--dart-define-from-file=dart_defines.json '
        '(see tools/gen_dart_defines.ps1).',
      );
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
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $bearer',
        'apikey': bearer,
        'Content-Type': contentType,
        if (upsert) 'x-upsert': 'true',
      },
      body: bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '[SupabaseUpload] ${response.statusCode} ${response.body}',
      );
      throw StateError(
        'Photo upload failed (${response.statusCode}). '
        'Check Supabase Storage credentials / policies.',
      );
    }
    return SupabaseStorageConfig.publicUrlForObjectKey(key);
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
