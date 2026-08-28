import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Persists tourist signup docs to Firestore, with a Cloud Function fallback when
/// client security rules are missing or outdated on the Firebase project.
class TouristRegistrationService {
  TouristRegistrationService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  static Future<void> _refreshAuthTokenForUid(String uid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != uid) return;
    try {
      await user.getIdToken(true);
    } catch (_) {}
  }

  /// Strips [FieldValue] for in-memory pending registration payloads.
  static Map<String, dynamic> jsonSafeMap(Map<String, dynamic> source) {
    return _jsonSafeMap(source);
  }

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
    var touristSaved = false;

    try {
      // OTP verification happens immediately before this call; force-refresh so
      // Firestore rules reliably see request.auth.uid (avoids transient denials).
      await _refreshAuthTokenForUid(uid);
      await touristRef.set(touristData);
      touristSaved = true;
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
      await _writeUserDocWithRetry(
        firestore: firestore,
        uid: uid,
        userData: userData,
      );
      debugPrint('[REG] users write OK (client Firestore)');
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      debugPrint('[REG] users permission-denied — calling Cloud Function');
      try {
        await _callSaveRegistration(
          touristData: touristData,
          userData: userData,
        );
      } on FirebaseException catch (fallbackError) {
        if ((fallbackError.code == 'not-found' ||
                fallbackError.code == 'unavailable') &&
            touristSaved) {
          debugPrint(
            '[REG] users fallback unavailable, but tourist profile already saved; '
            'continuing signup without failing OTP completion',
          );
          return;
        }
        rethrow;
      }
    }
  }

  static Future<void> _writeUserDocWithRetry({
    required FirebaseFirestore firestore,
    required String uid,
    required Map<String, dynamic> userData,
  }) async {
    FirebaseException? lastError;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        await _refreshAuthTokenForUid(uid);
        await firestore.collection('users').doc(uid).set(userData);
        return;
      } on FirebaseException catch (e) {
        lastError = e;
        if (e.code != 'permission-denied' || attempt == 3) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 350 * (attempt + 1)));
      }
    }
    if (lastError != null) throw lastError;
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
              'Cloud fallback saveTouristRegistration is unavailable on this Firebase '
              'project. Deploy functions if you want server-side signup fallback.',
        );
      }
      rethrow;
    }
  }
}
