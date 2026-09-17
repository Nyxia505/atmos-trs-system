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
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Resolves post-login navigation quickly (cache-first), then finishes setup in background.
class LoginFlowService {
  LoginFlowService._();

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

    // 2) If this same user already logged in before, use cached role/verification.
    final storedUid = await SessionStorage.getStoredUser();
    final storedRole = await SessionStorage.getStoredRole();
    if (storedUid == uid && storedRole == UserRole.tourismEstablishment) {
      return '/establishment-dashboard';
    }
    if (storedUid == uid && storedRole == UserRole.tourism) {
      return '/lgu-dashboard';
    }
    if (storedUid == uid && storedRole == UserRole.tourist) {
      final cachedVerified = await _getCachedTouristVerified(uid);
      if (cachedVerified == true) {
        return '/dashboard';
      }
    }

    // 2b) Pending LGU / establishment signup — finish OTP first.
    await PendingLguRegistrationCache.hydrate();
    await PendingEstablishmentRegistrationCache.hydrate();
    if (PendingLguRegistrationCache.forUid(uid) != null ||
        PendingEstablishmentRegistrationCache.forUid(uid) != null) {
      return '/verify-otp';
    }

    // 3) Cached profile lookup (doc by uid only; cheaper than extra email query).
    final profile = await UserDirectoryService.getProfileByUid(
      uid,
      preferServer: false,
    );
    if (profile != null) {
      if (profile.isTourist) {
        await _setCachedTouristVerified(uid, profile.isVerified);
      }
      return RoleRouter.routeForProfile(profile);
    }

    // 4) Tourist fallback: keep verify-OTP correctness for first-time/no-cache users.
    final verified =
        await UserDirectoryService.touristEmailVerificationComplete(uid);
    await _setCachedTouristVerified(uid, verified);
    return verified ? '/dashboard' : '/verify-otp';
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
      return;
    }
    if (role == UserRole.provincialTourism) {
      await SessionStorage.saveSession(
        uid,
        role: UserRole.provincialTourism,
        email: email,
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
      final synthetic = AppUserProfile(
        uid: uid,
        email: email,
        roleRaw: 'tourist',
        isVerified: migratedVerified == true,
      );
      await UserActivityService.bindToUser(uid);
      TouristActivityFirestoreSync.resetMergeCache();
      await TouristProfileHydration.hydrateFromFirestore(
        uid: uid,
        email: email,
      );
      await WelcomeNotificationService.ensureForUser(uid: uid);
      await _setCachedTouristVerified(uid, synthetic.isVerified);
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
