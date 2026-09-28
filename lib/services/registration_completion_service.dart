import 'dart:async' show unawaited;
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:atmos_trs_system/services/welcome_notification_service.dart';
import 'package:atmos_trs_system/services/otp_service.dart';
import 'package:atmos_trs_system/services/pending_registration_cache.dart';
import 'package:atmos_trs_system/services/push_notification_service.dart';
import 'package:atmos_trs_system/services/registration_rollback_service.dart';
import 'package:atmos_trs_system/services/tourist_activity_firestore_sync.dart';
import 'package:atmos_trs_system/services/tourist_registration_service.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/utils/email_utils.dart';

/// Persists Firestore profile docs after OTP verification (deferred signup).
class RegistrationCompletionService {
  RegistrationCompletionService._();

  /// Creates Firebase Auth (first time), then saves verified `tourists` + `users`.
  ///
  /// Used when signup deferred Auth until email OTP succeeded.
  static Future<User> createAuthAndCompleteAfterOtp({
    required PendingRegistration pending,
  }) async {
    final password = pending.password?.trim() ?? '';
    if (password.isEmpty) {
      throw StateError(
        'Signup session expired. Please sign up again.',
      );
    }

    final pendingOtpKey = pending.otpKey;
    var authEmail = normalizeEmail(
      pending.authEmail.isNotEmpty ? pending.authEmail : pending.contactEmail,
    );
    final contactEmail = normalizeEmail(pending.contactEmail);
    final isMinor = pending.touristData['minorAccountHolder'] == true;
    final isGmail = contactEmail.endsWith('@gmail.com') ||
        contactEmail.endsWith('@googlemail.com');

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    UserCredential cred;
    try {
      cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: authEmail,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use' && isMinor && isGmail) {
        authEmail = _buildMinorGmailAlias(contactEmail);
        debugPrint('[REG] minor Auth alias → $authEmail');
        cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: authEmail,
          password: password,
        );
      } else if (e.code == 'email-already-in-use') {
        final durable =
            await UserDirectoryService.emailHasDurableRegistration(contactEmail);
        if (durable) {
          throw StateError(
            'This email is already registered. Please sign in instead.',
          );
        }
        final reclaimed = await _tryReclaimOrphanAuth(
          authEmail: authEmail,
          password: password,
        );
        if (!reclaimed) {
          throw StateError(
            'This email is already used in Authentication. '
            'Delete the orphan Auth user or sign in with that password.',
          );
        }
        cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: authEmail,
          password: password,
        );
      } else {
        rethrow;
      }
    }

    final uid = cred.user?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Auth user id missing after createUser.');
    }

    final user = cred.user!;
    try {
      await user.getIdToken(true);
    } catch (_) {}

    final touristData = Map<String, dynamic>.from(pending.touristData);
    final userData = Map<String, dynamic>.from(pending.userData);
    touristData['firebaseUid'] = uid;
    touristData['authEmail'] = authEmail;
    touristData['email'] = contactEmail.isNotEmpty ? contactEmail : authEmail;
    userData['firebaseUid'] = uid;
    userData['email'] = authEmail;

    final updated = pending.copyWith(
      uid: uid,
      authEmail: authEmail,
      touristData: touristData,
      userData: userData,
      authDeferred: false,
      clearPassword: true,
    );

    await completeAfterOtp(uid: uid, pending: updated);

    // Clear pre-auth local OTP keyed by pending id (may differ from Auth uid).
    if (pendingOtpKey != uid) {
      try {
        await OtpService.deleteOtp(pendingOtpKey);
      } catch (_) {}
    }

    return user;
  }

  static Future<bool> _tryReclaimOrphanAuth({
    required String authEmail,
    required String password,
  }) async {
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: authEmail,
        password: password,
      );
      final orphanUid = cred.user?.uid;
      if (orphanUid == null || orphanUid.isEmpty) return false;
      await RegistrationRollbackService.rollback(orphanUid);
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {}
      debugPrint('[REG] reclaimed orphan Auth for $authEmail');
      return true;
    } catch (e) {
      debugPrint('[REG] orphan reclaim failed: $e');
      return false;
    }
  }

  static String _buildMinorGmailAlias(String parentGmail) {
    final at = parentGmail.indexOf('@');
    final local = at > 0 ? parentGmail.substring(0, at) : parentGmail;
    final domain = at > 0 ? parentGmail.substring(at) : '@gmail.com';
    final tag = Random.secure().nextInt(900000) + 100000;
    return '$local+atmos$tag$domain';
  }

  /// Saves `tourists` + `users`, local prefs, welcome notification; clears pending cache.
  static Future<void> completeAfterOtp({
    required String uid,
    required PendingRegistration pending,
  }) async {
    final touristData = Map<String, dynamic>.from(pending.touristData);
    final userData = Map<String, dynamic>.from(pending.userData);
    touristData['isVerified'] = true;
    userData['isVerified'] = true;
    touristData['firebaseUid'] = uid;
    userData['firebaseUid'] = uid;
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

    // FCM token only after verified profile exists (avoids stub users/tourists docs).
    if (!kIsWeb) {
      unawaited(syncFcmTokenToUserDoc(uid));
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
