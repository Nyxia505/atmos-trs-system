import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:atmos_trs_system/services/welcome_notification_service.dart';
import 'package:atmos_trs_system/services/otp_service.dart';
import 'package:atmos_trs_system/services/pending_registration_cache.dart';
import 'package:atmos_trs_system/services/tourist_activity_firestore_sync.dart';
import 'package:atmos_trs_system/services/tourist_registration_service.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';

/// Persists Firestore profile docs after OTP verification (deferred signup).
class RegistrationCompletionService {
  RegistrationCompletionService._();

  /// Saves `tourists` + `users`, local prefs, welcome notification; clears pending cache.
  static Future<void> completeAfterOtp({
    required String uid,
    required PendingRegistration pending,
  }) async {
    final touristData = Map<String, dynamic>.from(pending.touristData);
    final userData = Map<String, dynamic>.from(pending.userData);
    touristData['isVerified'] = true;
    userData['isVerified'] = true;
    touristData['registeredAt'] = FieldValue.serverTimestamp();
    userData['createdAt'] = FieldValue.serverTimestamp();

    debugPrint('[REG] completing profile after OTP uid=$uid');
    await TouristRegistrationService.saveRegistration(
      uid: uid,
      touristData: touristData,
      userData: userData,
    );
    try {
      await OtpService.deleteOtp(uid);
    } catch (e) {
      debugPrint('[REG] deleteOtp after verify (non-fatal): $e');
    }

    final local = pending.localProfile;
    if (local != null) {
      try {
        await UserProfileStorage.saveUserProfile(
          firstName: local.firstName,
          middleName: local.middleName,
          lastName: local.lastName,
          suffix: local.suffix,
          sex: local.sex,
          nationality: local.nationality,
          dateOfBirth: local.dateOfBirth,
          mobile: local.mobile,
          email: local.email,
          country: local.country,
          province: local.province,
          city: local.city,
          street: local.street,
          barangay: local.barangay,
          touristId: local.touristId,
          profileImageBase64: local.profileImageBase64,
          profilePhotoUrl: local.profilePhotoUrl,
        );
      } catch (e) {
        debugPrint('[REG] local prefs (non-fatal): $e');
      }
    }

    AuthConfig.currentUserUid = uid;
    await UserActivityService.bindToUser(uid);
    TouristActivityFirestoreSync.resetMergeCache();
    try {
      await SessionStorage.saveSession(
        uid,
        role: UserRole.tourist,
        email: pending.authEmail,
      );
    } catch (e) {
      debugPrint('[REG] session save (non-fatal): $e');
    }

    try {
      await WelcomeNotificationService.ensureForUser(
        uid: uid,
        firstName: pending.localProfile?.firstName,
      );
    } catch (e) {
      debugPrint('[REG] welcome notification (non-fatal): $e');
    }

    await PendingRegistrationCache.clear();
  }
}
