import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/services/otp_service.dart';
import 'package:atmos_trs_system/services/pending_lgu_registration_cache.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Persists LGU tourism-office profiles after OTP (deferred signup).
class LguRegistrationService {
  LguRegistrationService._();

  static const String usersCollection = 'users';

  static Future<void> saveRegistration({
    required String uid,
    required Map<String, dynamic> userData,
  }) async {
    await FirebaseFirestore.instance
        .collection(usersCollection)
        .doc(uid)
        .set(userData, SetOptions(merge: true));
  }

  static Future<void> completeAfterOtp({
    required String uid,
    required PendingLguRegistration pending,
  }) async {
    final userData = Map<String, dynamic>.from(pending.userData);
    userData['isVerified'] = true;
    userData['createdAt'] = FieldValue.serverTimestamp();
    userData['updatedAt'] = FieldValue.serverTimestamp();

    debugPrint('[LGU-REG] completing profile after OTP uid=$uid');
    await saveRegistration(uid: uid, userData: userData);

    try {
      await OtpService.deleteOtp(uid);
    } catch (e) {
      debugPrint('[LGU-REG] deleteOtp after verify (non-fatal): $e');
    }

    AuthConfig.currentUserUid = uid;
    final munName = (userData['municipality'] ?? '').toString();
    var municipalityId = (userData['municipalityId'] ?? '').toString().trim();
    if (municipalityId.isEmpty) {
      municipalityId = getMunicipalityIdFromName(munName);
    }
    try {
      await SessionStorage.saveSession(
        uid,
        role: UserRole.tourism,
        email: pending.authEmail,
        municipalityId: municipalityId.isNotEmpty ? municipalityId : null,
      );
    } catch (e) {
      debugPrint('[LGU-REG] session save (non-fatal): $e');
    }

    await PendingLguRegistrationCache.clear();
  }
}
