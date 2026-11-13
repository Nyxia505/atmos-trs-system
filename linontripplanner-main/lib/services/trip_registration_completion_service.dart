import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../firestore_loader.dart';
import '../services/storage_image_upload.dart';
import '../services/tourism_session.dart';
import 'otp_service.dart';
import 'pending_trip_registration_cache.dart';

/// Creates Firebase Auth + tourist profile after email OTP (ATMOS-style deferred signup).
class TripRegistrationCompletionService {
  TripRegistrationCompletionService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  static Future<User> createAuthAndCompleteAfterOtp({
    required PendingTripRegistration pending,
  }) async {
    final password = pending.password.trim();
    if (password.isEmpty) {
      throw StateError('Signup session expired. Please sign up again.');
    }

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: pending.email.trim().toLowerCase(),
      password: password,
    );
    final user = cred.user;
    if (user == null) {
      throw StateError('Auth user missing after createUser.');
    }

    final uid = user.uid;
    try {
      await user.getIdToken(true);
    } catch (_) {}

    if (pending.fullName.trim().isNotEmpty) {
      try {
        await user.updateDisplayName(pending.fullName.trim());
      } catch (_) {}
    }

    String? photoUrl;
    final bytes = pending.facePhotoBytes;
    if (bytes != null && bytes.isNotEmpty) {
      try {
        final uploaded =
            await uploadUserProfileImage(bytes, 'user_profiles/$uid');
        if (uploaded.trim().isNotEmpty) {
          photoUrl = uploaded.trim();
          await user.updatePhotoURL(photoUrl);
        }
      } catch (e) {
        debugPrint('[REG] face photo upload (non-fatal): $e');
      }
    }

    final registration = Map<String, dynamic>.from(pending.registration);
    registration['isVerified'] = true;
    registration['emailVerifiedViaOtp'] = true;

    try {
      await saveTouristRegistrationToFirestore(
        uid: uid,
        fullName: pending.fullName,
        email: pending.email.trim().toLowerCase(),
        phone: pending.phone,
        profilePhotoUrl: photoUrl,
        registration: registration,
      );
    } catch (e) {
      debugPrint('[REG] client tourists write failed: $e — CF fallback');
      await _saveViaCloudFunction(
        uid: uid,
        pending: pending,
        photoUrl: photoUrl,
        registration: registration,
      );
    }

    try {
      await OtpService.deleteOtp(pending.otpKey);
    } catch (_) {}

    try {
      await syncAccountAfterLogin();
      await loadTourismDataForSession();
    } catch (e, st) {
      debugPrint('[REG] post-registration sync: $e\n$st');
    }

    await PendingTripRegistrationCache.clear();
    return user;
  }

  static Future<void> _saveViaCloudFunction({
    required String uid,
    required PendingTripRegistration pending,
    required String? photoUrl,
    required Map<String, dynamic> registration,
  }) async {
    final callable = _functions.httpsCallable('saveTouristRegistration');
    await callable.call<void>({
      'profile': {
        ...registration,
        'fullName': pending.fullName,
        'name': pending.fullName,
        'email': pending.email.trim().toLowerCase(),
        'firebaseUid': uid,
        'touristId': uid,
        'isVerified': true,
        if (pending.phone != null && pending.phone!.trim().isNotEmpty)
          'phone': pending.phone!.trim(),
        if (photoUrl != null && photoUrl.trim().isNotEmpty)
          'profilePhotoUrl': photoUrl.trim(),
      },
      'user': {
        'firebaseUid': uid,
        'email': pending.email.trim().toLowerCase(),
        'fullName': pending.fullName,
        'role': 'tourist',
        'isVerified': true,
      },
    });
  }
}
