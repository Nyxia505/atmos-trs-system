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

  test('event photos use events/{eventId}/{unique file}', () {
    final key = SupabaseStorageUpload.eventPhotoObjectKey('evt_1', 'jpeg');
    expect(key, startsWith('events/evt_1/photo_'));
    expect(key, endsWith('.jpg'));
    expect(
      () => SupabaseStorageUpload.eventPhotoObjectKey('evt_1', 'gif'),
      throwsStateError,
    );
  });

  test('webp bytes are accepted as an event image type', () {
    final bytes = Uint8List.fromList([
      0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, //
      0x57, 0x45, 0x42, 0x50,
    ]);
    expect(SupabaseStorageUpload.contentTypeForImageBytes(bytes), 'image/webp');
    expect(SupabaseStorageUpload.eventImageTypes.contains('image/webp'), isTrue);
  });

  test('event photo delete stays inside that event folder', () {
    const eventId = 'evt1';
    const owned =
        'https://cgpjqkbbmyxvitwpkikn.supabase.co/storage/v1/object/public/tourist-images/events/evt1/photo_1.jpg';
    const firebase =
        'https://firebasestorage.googleapis.com/v0/b/atmos-trs-system.appspot.com/o/lgu_events%2Fa.jpg?alt=media';
    const otherEvent =
        'https://cgpjqkbbmyxvitwpkikn.supabase.co/storage/v1/object/public/tourist-images/events/evt2/photo_1.jpg';
    expect(SupabaseStorageUpload.ownsEventPhoto(owned, eventId), isTrue);
    expect(SupabaseStorageUpload.ownsEventPhoto(firebase, eventId), isFalse);
    expect(SupabaseStorageUpload.ownsEventPhoto(otherEvent, eventId), isFalse);
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
