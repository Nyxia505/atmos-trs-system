import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:atmos_trs_system/services/otp_service.dart';
import 'package:atmos_trs_system/services/pending_registration_cache.dart';
import 'package:atmos_trs_system/services/pending_establishment_registration_cache.dart';
import 'package:atmos_trs_system/services/pending_lgu_registration_cache.dart';

/// Removes partial signup data when OTP verification fails or is abandoned.
class RegistrationRollbackService {
  RegistrationRollbackService._();

  static Future<void> rollback(String uid) async {
    debugPrint('[REG] rollback registration uid=$uid');
    await PendingRegistrationCache.clear();
    await PendingEstablishmentRegistrationCache.clear();
    await PendingLguRegistrationCache.clear();
    if (Firebase.apps.isNotEmpty) {
      try {
        await OtpService.refreshAuthTokenForUid(uid);
      } catch (_) {}
      try {
        await OtpService.deleteOtp(uid);
      } catch (e) {
        debugPrint('[REG] rollback delete email_otps: $e');
      }
      try {
        final db = FirebaseFirestore.instance;
        final batch = db.batch();
        batch.delete(db.collection('tourists').doc(uid));
        batch.delete(db.collection('users').doc(uid));
        batch.delete(db.collection('accommodation_establishments').doc(uid));
        await batch.commit();
      } catch (e) {
        debugPrint('[REG] rollback Firestore: $e');
      }
      try {
        await FirebaseStorage.instance
            .ref()
            .child('profile_photos/$uid.jpg')
            .delete();
      } catch (_) {}
    }
    try {
      await FirebaseAuth.instance.currentUser?.delete();
    } catch (e) {
      debugPrint('[REG] deleteAuthUserBestEffort: $e');
    }
  }
}
