import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Stores generated tourist QR payloads and optional PNG in Firebase Storage.
class QrRegistryService {
  QrRegistryService._();

  static const String _collection = 'tourist_qr_codes';

  /// Upserts the current tourist QR record and appends a generation history event.
  static Future<void> upsertTouristQr({
    required String touristId,
    required String payload,
    required String fullName,
    required String location,
  }) async {
    if (touristId.trim().isEmpty) return;
    if (Firebase.apps.isEmpty) return;

    final now = DateTime.now();
    final firestore = FirebaseFirestore.instance;
    final docRef = firestore.collection(_collection).doc(touristId);

    try {
      await docRef.set({
        'tourist_id': touristId,
        'payload': payload,
        'full_name': fullName.trim(),
        'location': location.trim(),
        'qr_type': 'tourist',
        'updated_at': FieldValue.serverTimestamp(),
        'client_updated_at': now.toIso8601String(),
      }, SetOptions(merge: true));

      await docRef.collection('history').add({
        'event': 'generated',
        'payload': payload,
        'created_at': FieldValue.serverTimestamp(),
        'client_created_at': now.toIso8601String(),
      });
    } catch (e) {
      debugPrint('[QR Registry] upsertTouristQr failed: $e');
    }
  }

  /// Uploads the rendered QR card PNG to Storage and merges [qr_image_url] on the same Firestore doc.
  static Future<void> uploadQrCardPng({
    required String touristId,
    required Uint8List pngBytes,
  }) async {
    if (touristId.trim().isEmpty || pngBytes.isEmpty) return;
    if (Firebase.apps.isEmpty) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid != touristId) {
      debugPrint('[QR Registry] uploadQrCardPng skipped: not signed in as tourist');
      return;
    }

    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('tourist_qr_cards/$touristId/qr_card.png');
      final task = await storageRef.putData(
        pngBytes,
        SettableMetadata(contentType: 'image/png'),
      );
      final url = await task.ref.getDownloadURL();

      await FirebaseFirestore.instance
          .collection(_collection)
          .doc(touristId)
          .set({
        'qr_image_url': url,
        'qr_image_storage_path': storageRef.fullPath,
        'qr_image_updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[QR Registry] uploadQrCardPng failed: $e');
    }
  }
}
