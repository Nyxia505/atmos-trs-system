import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/navigation/role_router.dart';
import 'package:atmos_trs_system/services/dashboard_user_service.dart';
import 'package:atmos_trs_system/services/tourist_profile_hydration.dart';
import 'package:atmos_trs_system/services/tourist_activity_firestore_sync.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/services/welcome_notification_service.dart';
import 'package:atmos_trs_system/services/pending_lgu_registration_cache.dart';
import 'package:atmos_trs_system/services/pending_establishment_registration_cache.dart';
import 'package:atmos_trs_system/services/pending_registration_cache.dart';
import 'package:atmos_trs_system/services/otp_service.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Resolves post-login navigation quickly (cache-first), then finishes setup in background.
class LoginFlowService {
  LoginFlowService._();

  /// Auth signed in but no durable Firestore registration — must sign up again.
  static const String mustSignUpAgainRoute = '/__must_signup_again__';

  static Future<bool?> _getCachedTouristVerified(String uid) async {
    if (uid.isEmpty) return null;
    final cached = await SessionStorage.isTouristEmailVerifiedCached(uid);
    return cached ? true : null;
  }

  static Future<void> _setCachedTouristVerified(
    String uid,
    bool isVerified,
  ) async {
    await SessionStorage.setTouristEmailVerified(uid, verified: isVerified);
  }

  /// Cache-first route; falls back to email heuristics for staff demo accounts.
  static Future<String> resolveRouteFast({
    required String uid,
    required String email,
  }) async {
    // 1) Fast staff routing by email pattern (no Firestore/network).
    final roleFromEmail = SessionStorage.getRoleFromEmail(email);
    if (roleFromEmail == UserRole.governor) return '/governor-dashboard';
    if (roleFromEmail == UserRole.provincialTourism) {
      return '/provincial-tourism-dashboard';
    }
    if (roleFromEmail == UserRole.tourism) return '/lgu-dashboard';

    // 2) Pending signup OTP (local) — allow finish verification.
    await PendingRegistrationCache.hydrate();
    await PendingLguRegistrationCache.hydrate();
    await PendingEstablishmentRegistrationCache.hydrate();
    if (PendingLguRegistrationCache.forUid(uid) != null ||
        PendingEstablishmentRegistrationCache.forUid(uid) != null ||
        PendingRegistrationCache.forUid(uid) != null) {
      return '/verify-otp';
    }

    // Active signup OTP but no local pending payload — cannot finish profile here.
    // Treat as incomplete / removed registration (must sign up again).
    if (await OtpService.hasActiveOtp(uid) &&
        !await UserDirectoryService.hasDurableRegistrationRecord(uid)) {
      await _setCachedTouristVerified(uid, false);
      return mustSignUpAgainRoute;
    }

    // 3) Cached role only if server still has a completed tourist account.
    final storedUid = await SessionStorage.getStoredUser();
    final storedRole = await SessionStorage.getStoredRole();
    if (storedUid == uid && storedRole == UserRole.tourismEstablishment) {
      final profile = await UserDirectoryService.getProfileByUid(
        uid,
        preferServer: true,
      );
      if (profile != null && profile.isTourismEstablishment) {
        return '/establishment-dashboard';
      }
    }
    if (storedUid == uid && storedRole == UserRole.tourism) {
      return '/lgu-dashboard';
    }
    if (storedUid == uid && storedRole == UserRole.tourist) {
      final cachedVerified = await _getCachedTouristVerified(uid);
      if (cachedVerified == true) {
        if (await UserDirectoryService.hasCompletedTouristAccount(uid)) {
          return '/dashboard';
        }
        await _setCachedTouristVerified(uid, false);
      }
    }

    // 4) Server profile (prefer server so deleted accounts are detected).
    final profile = await UserDirectoryService.getProfileByUid(
      uid,
      preferServer: true,
    );
    if (profile != null) {
      if (profile.isTourist) {
        if (!profile.isVerified) {
          // Email must not stay as an unverified permanent user row.
          return mustSignUpAgainRoute;
        }
        await _setCachedTouristVerified(uid, true);
      }
      return RoleRouter.routeForProfile(profile);
    }

    // 5) Legacy tourists/{uid} only (verified).
    if (await UserDirectoryService.hasCompletedTouristAccount(uid)) {
      await _setCachedTouristVerified(uid, true);
      return '/dashboard';
    }

    // 6) Auth remnant / deleted DB registration → sign up again.
    if (!await UserDirectoryService.hasDurableRegistrationRecord(uid)) {
      await _setCachedTouristVerified(uid, false);
      return mustSignUpAgainRoute;
    }

    final verified =
        await UserDirectoryService.touristEmailVerificationComplete(uid);
    await _setCachedTouristVerified(uid, verified);
    return verified ? '/dashboard' : mustSignUpAgainRoute;
  }

  /// Persists staff session from email heuristics only (no Firestore).
  /// Used so dashboards can load immediately while finalize runs in background.
  static Future<void> persistStaffSessionQuick({
    required String uid,
    required String email,
  }) async {
    final role = SessionStorage.getRoleFromEmail(email);
    if (role == UserRole.governor) {
      await SessionStorage.saveSession(
        uid,
        role: UserRole.governor,
        email: email,
      );
      unawaited(
        UserDirectoryService.ensureStaffUserDoc(
          uid: uid,
          email: email,
          roleRaw: 'governor',
        ),
      );
      return;
    }
    if (role == UserRole.provincialTourism) {
      await SessionStorage.saveSession(
        uid,
        role: UserRole.provincialTourism,
        email: email,
      );
      unawaited(
        UserDirectoryService.ensureStaffUserDoc(
          uid: uid,
          email: email,
          roleRaw: 'provincial_tourism',
        ),
      );
      return;
    }
    if (role == UserRole.tourism) {
      final municipalityId =
          SessionStorage.getMunicipalityIdFromTourismEmail(email);
      await SessionStorage.saveSession(
        uid,
        role: UserRole.tourism,
        email: email,
        municipalityId: municipalityId,
      );
      unawaited(
        UserDirectoryService.ensureStaffUserDoc(
          uid: uid,
          email: email,
          roleRaw: 'tourism',
          municipalityId: municipalityId,
        ),
      );
    }
  }

  /// Firestore session persist, staff docs, profile hydrate (non-blocking for UI).
  static Future<void> finalizeLoginInBackground({
    required String uid,
    required String email,
    required String password,
  }) async {
    try {
      var profile =
          await UserDirectoryService.getProfileByUid(
            uid,
            preferServer: false,
          ) ??
          await UserDirectoryService.getProfileByEmail(email);

      if (profile != null) {
        if (profile.isGovernor ||
            profile.isProvincialTourism ||
            profile.isTourismOffice) {
          await UserDirectoryService.ensureStaffUserDoc(
            uid: uid,
            email: profile.email,
            roleRaw: profile.roleRaw,
            fullName: profile.fullName,
          );
          UserDirectoryService.markStaffFirestoreAccessReady(uid);
        }
        if (profile.isTourist) {
          await UserActivityService.bindToUser(uid);
          TouristActivityFirestoreSync.resetMergeCache();
          await TouristProfileHydration.hydrateFromFirestore(
            uid: uid,
            email: email,
          );
          await WelcomeNotificationService.ensureForUser(uid: uid);
          await _setCachedTouristVerified(uid, profile.isVerified);
        }
        await RoleRouter.persistSessionAndGetRoute(
          profile: profile,
          firebaseUid: uid,
        );
        return;
      }

      final dash = await DashboardUserService.getProfileByEmail(email);
      if (dash != null && dash.role == 'governor') {
        await UserDirectoryService.ensureStaffUserDoc(
          uid: uid,
          email: email,
          roleRaw: 'governor',
        );
        await SessionStorage.saveSession(
          uid,
          role: UserRole.governor,
          email: email,
        );
        return;
      }
      if (dash != null && dash.role == 'tourism') {
        await UserDirectoryService.ensureStaffUserDoc(
          uid: uid,
          email: email,
          roleRaw: 'tourism',
        );
        var municipalityId = getMunicipalityIdFromName(dash.municipality);
        if (municipalityId.isEmpty) {
          municipalityId =
              SessionStorage.getMunicipalityIdFromTourismEmail(email) ?? '';
        }
        await SessionStorage.saveSession(
          uid,
          role: UserRole.tourism,
          email: email,
          municipalityId: municipalityId.isNotEmpty ? municipalityId : null,
        );
        return;
      }

      final legacyMunId = SessionStorage.getMunicipalityIdFromTourismEmail(
        email,
      );
      if (legacyMunId != null) {
        await UserDirectoryService.ensureStaffUserDoc(
          uid: uid,
          email: email,
          roleRaw: 'tourism',
          municipalityId: legacyMunId,
        );
        await SessionStorage.saveSession(
          uid,
          role: UserRole.tourism,
          email: email,
          municipalityId: legacyMunId,
        );
        return;
      }

      if (email.toLowerCase().trim() ==
              SessionStorage.governorEmail.toLowerCase() &&
          await SessionStorage.validateCredentialsAsync(email, password)) {
        final synthetic = AppUserProfile(
          uid: uid,
          email: email,
          roleRaw: 'governor',
          isVerified: true,
        );
        await RoleRouter.persistSessionAndGetRoute(
          profile: synthetic,
          firebaseUid: uid,
        );
        return;
      }

      if (email.toLowerCase().trim() ==
              SessionStorage.tourismEmail.toLowerCase() &&
          await SessionStorage.validateCredentialsAsync(email, password)) {
        final synthetic = AppUserProfile(
          uid: uid,
          email: email,
          roleRaw: 'tourism',
          isVerified: true,
        );
        await RoleRouter.persistSessionAndGetRoute(
          profile: synthetic,
          firebaseUid: uid,
        );
        return;
      }

      if (SessionStorage.isProvincialTourismEmail(email) &&
          await SessionStorage.validateCredentialsAsync(email, password)) {
        final synthetic = AppUserProfile(
          uid: uid,
          email: email,
          roleRaw: 'provincial_tourism',
          isVerified: true,
        );
        await RoleRouter.persistSessionAndGetRoute(
          profile: synthetic,
          firebaseUid: uid,
        );
        return;
      }

      final migratedVerified =
          await UserDirectoryService.getTouristIsVerifiedFromTouristsDoc(uid);
      if (migratedVerified != true &&
          !await UserDirectoryService.hasCompletedTouristAccount(uid)) {
        debugPrint(
          '[LoginFlow] skip synthetic tourist — no durable verified registration',
        );
        return;
      }
      final synthetic = AppUserProfile(
        uid: uid,
        email: email,
        roleRaw: 'tourist',
        isVerified: true,
      );
      await UserActivityService.bindToUser(uid);
      TouristActivityFirestoreSync.resetMergeCache();
      await TouristProfileHydration.hydrateFromFirestore(
        uid: uid,
        email: email,
      );
      await WelcomeNotificationService.ensureForUser(uid: uid);
      await _setCachedTouristVerified(uid, true);
      await RoleRouter.persistSessionAndGetRoute(
        profile: synthetic,
        firebaseUid: uid,
      );
    } catch (e) {
      debugPrint('LoginFlowService.finalizeLoginInBackground: $e');
    }
  }

  static void scheduleBackgroundFinalize({
    required String uid,
    required String email,
    required String password,
  }) {
    unawaited(
      finalizeLoginInBackground(uid: uid, email: email, password: password),
    );
  }
}
