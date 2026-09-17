import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/services/otp_service.dart';
import 'package:atmos_trs_system/services/pending_establishment_registration_cache.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Persists tourism establishment profiles after OTP (deferred signup).
class EstablishmentRegistrationService {
  EstablishmentRegistrationService._();

  static const String establishmentsCollection = 'accommodation_establishments';
  static const String usersCollection = 'users';

  static const List<String> categoryTypes = [
    'Hotel',
    'Resort',
    'Restaurant',
    'Glamping',
    'Camping',
    'Swimming Pool',
    'Museum/Gallery',
    'Events Place',
    'Attraction',
    'Health & Wellness',
    'Food Provider',
  ];

  static Future<void> saveRegistration({
    required String uid,
    required Map<String, dynamic> userData,
    required Map<String, dynamic> establishmentData,
  }) async {
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    final usersRef = db.collection(usersCollection).doc(uid);
    final estId = (establishmentData['id']?.toString().trim().isNotEmpty == true)
        ? establishmentData['id'].toString()
        : uid;
    final estRef = db.collection(establishmentsCollection).doc(estId);

    batch.set(usersRef, userData, SetOptions(merge: true));
    batch.set(estRef, {
      ...establishmentData,
      'id': estId,
      'ownerUid': uid,
      'authUid': uid,
    }, SetOptions(merge: true));
    await batch.commit();
  }

  static Future<void> completeAfterOtp({
    required String uid,
    required PendingEstablishmentRegistration pending,
  }) async {
    final userData = Map<String, dynamic>.from(pending.userData);
    final establishmentData =
        Map<String, dynamic>.from(pending.establishmentData);
    userData['isVerified'] = true;
    userData['createdAt'] = FieldValue.serverTimestamp();
    establishmentData['updatedAt'] = FieldValue.serverTimestamp();
    establishmentData['createdAt'] = FieldValue.serverTimestamp();

    debugPrint('[EST-REG] completing profile after OTP uid=$uid');
    await saveRegistration(
      uid: uid,
      userData: userData,
      establishmentData: establishmentData,
    );
    try {
      await OtpService.deleteOtp(uid);
    } catch (e) {
      debugPrint('[EST-REG] deleteOtp after verify (non-fatal): $e');
    }

    AuthConfig.currentUserUid = uid;
    final munName =
        (userData['municipality'] ?? establishmentData['municipality'] ?? '')
            .toString();
    final municipalityId = getMunicipalityIdFromName(munName);
    try {
      await SessionStorage.saveSession(
        uid,
        role: UserRole.tourismEstablishment,
        email: pending.authEmail,
        municipalityId: municipalityId.isNotEmpty ? municipalityId : null,
      );
    } catch (e) {
      debugPrint('[EST-REG] session save (non-fatal): $e');
    }

    await PendingEstablishmentRegistrationCache.clear();
  }
}
