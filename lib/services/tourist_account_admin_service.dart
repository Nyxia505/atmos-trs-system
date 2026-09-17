import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Result of an admin tourist delete (Cloud Function and/or client Firestore).
class TouristAccountDeleteResult {
  const TouristAccountDeleteResult({
    required this.uid,
    required this.authDeleted,
    required this.usedCloudFunction,
  });

  final String uid;
  final bool authDeleted;
  final bool usedCloudFunction;

  String get successMessage {
    if (authDeleted) {
      return 'Tourist account deleted (profile and login removed).';
    }
    return 'Tourist profile removed from ATMOS-TRS. '
        'Login may still exist until Cloud Functions (Blaze) are deployed.';
  }
}

/// Admin (governor / tourism) deletion of tourist accounts.
///
/// Prefers Cloud Function `deleteTouristAccount` (Auth + Firestore).
/// Falls back to client Firestore deletes when Functions are unavailable
/// (e.g. Spark plan / not deployed).
class TouristAccountAdminService {
  TouristAccountAdminService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static const Duration _timeout = Duration(seconds: 6);

  /// Resolves the Firebase Auth / Firestore document id from a dashboard row.
  static String? resolveTouristUid(Map<String, dynamic> tourist) {
    for (final key in ['id', 'firebaseUid', 'uid', 'userId', 'user_id']) {
      final v = tourist[key]?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  /// True when a dashboard row should be hidden after admin delete / soft-delete.
  static bool isDeletedTouristRow(Map<String, dynamic> row) {
    if (row['accountDeleted'] == true) return true;
    final status = row['status']?.toString().trim().toLowerCase() ?? '';
    return status == 'deleted' || status == 'removed';
  }

  /// Deletes tourist data. Client Firestore wipe first (works without Blaze),
  /// then best-effort Cloud Function for Auth removal when deployed.
  static Future<TouristAccountDeleteResult> deleteTouristAccount(
    String uid,
  ) async {
    final trimmed = uid.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Tourist id is required.');
    }

    final auth = FirebaseAuth.instance.currentUser;
    if (auth == null) {
      throw StateError('Sign in again as governor or tourism staff, then retry.');
    }
    if (auth.uid == trimmed) {
      throw StateError('You cannot delete your own signed-in account here.');
    }

    await _deleteTouristDataOnClient(trimmed);

    // Auth deletion needs Cloud Functions (Blaze). Do not block dashboard UI.
    // ignore: unawaited_futures
    () async {
      try {
        final callable = _functions.httpsCallable(
          'deleteTouristAccount',
          options: HttpsCallableOptions(timeout: _timeout),
        );
        await callable.call<Map<String, dynamic>>({'uid': trimmed});
      } catch (e) {
        debugPrint('[TouristAccountAdmin] CF Auth cleanup skipped: $e');
      }
    }();

    return TouristAccountDeleteResult(
      uid: trimmed,
      authDeleted: false,
      usedCloudFunction: false,
    );
  }

  /// Client-side wipe of tourist Firestore docs (requires staff delete rules).
  static Future<void> _deleteTouristDataOnClient(String uid) async {
    if (Firebase.apps.isEmpty) {
      throw StateError('Firebase is not available.');
    }

    // Guard: do not wipe staff profiles.
    try {
      final userSnap = await _db.collection('users').doc(uid).get();
      if (userSnap.exists) {
        final role =
            (userSnap.data()?['role']?.toString() ?? '').trim().toLowerCase();
        if (role == 'governor' ||
            role == 'tourism' ||
            role == 'tourism_office') {
          throw StateError(
            'Staff accounts cannot be deleted from Registered Tourists.',
          );
        }
      }
    } catch (e) {
      if (e is StateError) rethrow;
      debugPrint('[TouristAccountAdmin] users role check: $e');
    }

    final errors = <String>[];

    // Fast path: remove the profile docs first so the dashboard updates quickly.
    Future<void> deleteDoc(String collection) async {
      try {
        await _db.collection(collection).doc(uid).delete();
      } catch (e) {
        debugPrint('[TouristAccountAdmin] delete $collection/$uid: $e');
        errors.add('$collection: $e');
      }
    }

    await deleteDoc('tourists');
    await deleteDoc('users');
    await deleteDoc('email_otps');
    await deleteDoc('tourist_activity');
    await deleteDoc('tourist_qr_codes');

    // Soft-delete if hard delete of tourists failed (rules not deployed yet).
    try {
      final stillThere = await _db.collection('tourists').doc(uid).get();
      if (stillThere.exists) {
        await _db.collection('tourists').doc(uid).set({
          'accountDeleted': true,
          'status': 'Deleted',
          'accountDeletedAt': FieldValue.serverTimestamp(),
          'accountDeletedBy': FirebaseAuth.instance.currentUser?.uid,
        }, SetOptions(merge: true));
        try {
          await _db.collection('users').doc(uid).set({
            'accountDeleted': true,
            'status': 'Deleted',
            'accountDeletedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[TouristAccountAdmin] soft-delete fallback: $e');
      errors.add('soft-delete: $e');
    }

    final touristsSnap = await _db.collection('tourists').doc(uid).get();
    final gone = !touristsSnap.exists;
    final soft = !gone && touristsSnap.data()?['accountDeleted'] == true;
    if (!gone && !soft) {
      throw StateError(
        'Could not delete tourist data. Deploy Firestore rules '
        '(firebase deploy --only firestore:rules) while signed in as staff, then retry.',
      );
    }

    // Best-effort related cleanup (do not fail the delete if these error).
    Future<void> deleteQuery(Query<Map<String, dynamic>> query) async {
      try {
        final snap = await query.limit(100).get();
        if (snap.docs.isEmpty) return;
        final batch = _db.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      } catch (e) {
        debugPrint('[TouristAccountAdmin] query delete: $e');
      }
    }

    try {
      await Future.wait([
        deleteQuery(
          _db.collection('qr_checkins').where('tourist_id', isEqualTo: uid),
        ),
        deleteQuery(
          _db.collection('qr_checkins').where('userId', isEqualTo: uid),
        ),
        deleteQuery(
          _db.collection('check_ins').where('user_id', isEqualTo: uid),
        ),
        deleteQuery(
          _db.collection('spot_reviews').where('userId', isEqualTo: uid),
        ),
        deleteQuery(
          _db.collection('notifications').where('user_id', isEqualTo: uid),
        ),
      ]);
    } catch (_) {}
  }

  // Keep for UI mapping when CF is the only failure path without fallback.
  static String userFacingError(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return 'Sign in again as governor or tourism staff, then retry.';
      case 'permission-denied':
        return e.message?.trim().isNotEmpty == true
            ? e.message!
            : 'Only governor or tourism staff can delete tourist accounts.';
      case 'not-found':
        return e.message?.trim().isNotEmpty == true
            ? e.message!
            : 'Tourist account was not found (it may already be deleted).';
      case 'unavailable':
      case 'deadline-exceeded':
      case 'internal':
        return 'Could not reach the delete service. Deploy Cloud Functions '
            '(deleteTouristAccount) or try again later.';
      case 'failed-precondition':
        return e.message?.trim().isNotEmpty == true
            ? e.message!
            : 'Delete service is not available. Deploy functions and try again.';
      default:
        final msg = e.message?.trim();
        if (msg != null && msg.isNotEmpty) return msg;
        return 'Could not delete tourist account (${e.code}).';
    }
  }
}
