import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/navigation/role_router.dart';
import 'package:atmos_trs_system/services/dashboard_user_service.dart';
import 'package:atmos_trs_system/services/tourist_profile_hydration.dart';
import 'package:atmos_trs_system/services/tourist_activity_firestore_sync.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/services/welcome_notification_service.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Resolves post-login navigation quickly (cache-first), then finishes setup in background.
class LoginFlowService {
  LoginFlowService._();
  static const String _touristVerifiedKeyPrefix = 'tourist_is_verified_';

  static Future<bool?> _getCachedTouristVerified(String uid) async {
    if (uid.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_touristVerifiedKeyPrefix$uid');
  }

  static Future<void> _setCachedTouristVerified(
    String uid,
    bool isVerified,
  ) async {
    if (uid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_touristVerifiedKeyPrefix$uid', isVerified);
  }

  /// Cache-first route; falls back to email heuristics for staff demo accounts.
  static Future<String> resolveRouteFast({
    required String uid,
    required String email,
  }) async {
    // 1) Fast staff routing by email pattern (no Firestore/network).
    final roleFromEmail = SessionStorage.getRoleFromEmail(email);
    if (roleFromEmail == UserRole.governor) return '/governor-dashboard';
    if (roleFromEmail == UserRole.tourism) return '/lgu-dashboard';

    // 2) If this same tourist already logged in before, use cached verification.
    final storedUid = await SessionStorage.getStoredUser();
    final storedRole = await SessionStorage.getStoredRole();
    if (storedUid == uid && storedRole == UserRole.tourist) {
      final cachedVerified = await _getCachedTouristVerified(uid);
      if (cachedVerified == true) {
        return '/dashboard';
      }
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
        if (profile.isGovernor || profile.isTourismOffice) {
          await UserDirectoryService.ensureStaffUserDoc(
            uid: uid,
            email: profile.email,
            roleRaw: profile.roleRaw,
            fullName: profile.fullName,
          );
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
