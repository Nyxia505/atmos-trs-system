import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';
import 'auth_role_claims.dart';

/// Uploads catalog images to **Supabase Storage** and returns a public HTTPS URL.
///
/// The image file is stored in the Supabase `tourist-images` bucket.
/// Firestore should only keep that public URL (never the binary).
///
/// [folder] e.g. `events/slug`, `announcements/slug`, `municipalities/slug`.
/// Requires a signed-in Firebase staff account (admin catalog gate).
Future<String> uploadTourismCatalogImage(
  Uint8List bytes,
  String folder,
) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw StateError('Sign in required to upload images.');
  }
  await ensurePermanentStaffRoleForCatalogWrite();
  await user.getIdToken(true);
  return uploadBytesToSupabaseStorage(bytes, folder);
}

/// Profile / registration photos — signed-in user only (no staff role).
Future<String> uploadUserProfileImage(
  Uint8List bytes,
  String folder,
) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw StateError('Sign in required to upload images.');
  }
  return uploadBytesToSupabaseStorage(bytes, folder);
}

/// Core Supabase object upload (public bucket URL returned).
Future<String> uploadBytesToSupabaseStorage(
  Uint8List bytes,
  String folder,
) async {
  if (!SupabaseConfig.isConfigured) {
    throw StateError(
      'Supabase is not configured. Open lib/config/supabase_config.dart '
      'and set your project URL + anon key, then create a public bucket '
      '"${SupabaseConfig.imageBucket}".',
    );
  }
  if (bytes.isEmpty) {
    throw StateError('Image file is empty.');
  }

  final mime = _detectImageMime(bytes);
  final ext = _extForMime(mime);
  final objectPath =
      '${_sanitizeStorageFolder(folder)}/${DateTime.now().millisecondsSinceEpoch}.$ext';
  final uri = Uri.parse(
    '${SupabaseConfig.storageApiBase}/object/${SupabaseConfig.imageBucket}/$objectPath',
  );

  final response = await http.post(
    uri,
    headers: {
      'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
      'apikey': SupabaseConfig.anonKey,
      'Content-Type': mime,
      'x-upsert': 'true',
    },
    body: bytes,
  );

  if (response.statusCode < 200 || response.statusCode >= 300) {
    final body = response.body;
    final rls = body.contains('row-level security') ||
        body.contains('AccessDenied') ||
        body.contains('"statusCode":"403"');
    if (rls) {
      throw StateError(
        'Supabase Storage blocked this upload (RLS). '
        'In Supabase → SQL Editor, run the script '
        'main/supabase/storage_policies_tourist_images.sql, '
        'then try again.',
      );
    }
    throw StateError(
      'Supabase upload failed (${response.statusCode}): $body',
    );
  }

  return publicSupabaseImageUrl(objectPath);
}

/// Public URL for an object already stored in the tourism images bucket.
String publicSupabaseImageUrl(String objectPath) =>
    SupabaseConfig.publicObjectUrl(SupabaseConfig.imageBucket, objectPath);

/// Backward-compatible name used by admin forms (uploads to Supabase).
Future<String> uploadImageToFirebaseStorage(
  Uint8List bytes,
  String folder,
) =>
    uploadTourismCatalogImage(bytes, folder);

String _sanitizeStorageFolder(String folder) {
  var s = folder.trim().replaceAll('\\', '/');
  s = s.replaceAll('Tourist Spots Image', 'tourist-spots');
  s = s.replaceAll('Tourist Spots', 'tourist-spots');
  s = s.replaceAll(RegExp(r'\s+'), '-');
  s = s.replaceAll(RegExp(r'[^a-zA-Z0-9/_-]'), '');
  s = s.replaceAll(RegExp(r'/+'), '/');
  s = s.replaceAll(RegExp(r'^/+|/+$'), '');
  if (s.isEmpty) return 'uploads';
  return s.toLowerCase();
}

String _detectImageMime(Uint8List bytes) {
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
      bytes[2] == 0x46) {
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
  return 'image/jpeg';
}

String _extForMime(String mime) {
  switch (mime) {
    case 'image/png':
      return 'png';
    case 'image/gif':
      return 'gif';
    case 'image/webp':
      return 'webp';
    case 'image/jpeg':
    default:
      return 'jpg';
  }
}
