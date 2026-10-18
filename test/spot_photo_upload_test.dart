import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:atmos_trs_system/services/supabase_storage_upload.dart';

void main() {
  test('spot photos use the tourist-spots folder allowed by storage policy', () {
    final key = SupabaseStorageUpload.spotPhotoObjectKey('Cotta Beach', 'jpg');
    expect(key, startsWith('tourist-spots/CottaBeach/photo_'));
    expect(key, endsWith('.jpg'));
    expect(key.contains('/spots/'), isFalse);
  });

  test('image type comes from file bytes, not the file name', () {
    expect(
      SupabaseStorageUpload.contentTypeForImageBytes(
        Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]),
      ),
      'image/jpeg',
    );
    expect(
      SupabaseStorageUpload.contentTypeForImageBytes(
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]),
      ),
      'image/png',
    );
    expect(
      SupabaseStorageUpload.contentTypeForImageBytes(
        Uint8List.fromList([1, 2, 3, 4]),
      ),
      isNull,
    );
  });

  test('HTTP 400 storage body is shown instead of a generic policy hint', () {
    const body =
        '{"statusCode":"403","error":"Unauthorized","message":"new row violates row-level security policy"}';
    expect(
      SupabaseStorageUpload.storageFailureMessage(400, body),
      'Photo upload failed (400): new row violates row-level security policy',
    );
  });

  test('only this spot folder is deleted after a successful save', () {
    const spotId = 'spot1';
    const owned =
        'https://cgpjqkbbmyxvitwpkikn.supabase.co/storage/v1/object/public/tourist-images/tourist-spots/spot1/photo_1.jpg';
    const shared =
        'https://cgpjqkbbmyxvitwpkikn.supabase.co/storage/v1/object/public/tourist-images/images/plaza.jpg';
    expect(SupabaseStorageUpload.ownsSpotPhoto(owned, spotId), isTrue);
    expect(SupabaseStorageUpload.ownsSpotPhoto(shared, spotId), isFalse);
    expect(SupabaseStorageUpload.ownsSpotPhoto(owned, 'other'), isFalse);
  });
}
