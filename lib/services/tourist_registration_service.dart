import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Persists tourist signup docs to Firestore, with a Cloud Function fallback when
/// client security rules are missing or outdated on the Firebase project.
class TouristRegistrationService {
  TouristRegistrationService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  static Map<String, dynamic> _jsonSafeMap(Map<String, dynamic> source) {
    final out = <String, dynamic>{};
    source.forEach((key, value) {
      if (value is FieldValue) return;
      out[key] = value;
    });
    return out;
  }

  static Future<void> saveRegistration({
    required String uid,
    required Map<String, dynamic> touristData,
    Map<String, dynamic>? userData,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final touristRef = firestore.collection('tourists').doc(uid);

    try {
      await touristRef.set(touristData);
      debugPrint('[REG] tourists write OK (client Firestore)');
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      debugPrint(
        '[REG] tourists permission-denied — calling saveTouristRegistration',
      );
      await _callSaveRegistration(
        touristData: touristData,
        userData: userData,
      );
      debugPrint('[REG] tourists write OK (Cloud Function)');
      return;
    }

    if (userData == null) return;
    try {
      await firestore.collection('users').doc(uid).set(userData);
      debugPrint('[REG] users write OK (client Firestore)');
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      debugPrint('[REG] users permission-denied — calling Cloud Function');
      await _callSaveRegistration(
        touristData: touristData,
        userData: userData,
      );
    }
  }

  static Future<void> _callSaveRegistration({
    required Map<String, dynamic> touristData,
    Map<String, dynamic>? userData,
  }) async {
    try {
      final callable = _functions.httpsCallable('saveTouristRegistration');
      await callable.call<void>({
        'profile': _jsonSafeMap(touristData),
        if (userData != null) 'user': _jsonSafeMap(userData),
      });
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found' || e.code == 'unavailable') {
        throw FirebaseException(
          plugin: 'cloud_functions',
          code: e.code,
          message:
              'saveTouristRegistration is not deployed. Run: firebase deploy --only functions,firestore:rules',
        );
      }
      rethrow;
    }
  }
}
