import 'dart:async' show unawaited;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:atmos_trs_system/navigation/role_router.dart';
import 'package:atmos_trs_system/services/dashboard_user_service.dart';
import 'package:atmos_trs_system/services/mobile_onboarding_storage.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/services/tourist_profile_hydration.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Fast cold-start routing (cache/session) plus optional background refinement.
class StartupRouteResolver {
  StartupRouteResolver._();

  /// Minimal work before [runApp]: Firebase user + stored session + QR peek.
  static Future<String> resolveQuickInitialRoute() async {
    var route = kIsWeb ? '/landing' : '/login';

    if (Firebase.apps.isEmpty) {
      return _applyQrWelcomeIfNeeded(route, firebaseUser: null);
    }

    final firebaseUser = await _waitForRestoredFirebaseUser();

    if (firebaseUser == null) {
      final storedUid = await SessionStorage.getStoredUser();
      if (storedUid != null) {
        debugPrint('Startup: clearing stale session (no Firebase Auth user).');
        await SessionStorage.clearSession();
        AuthConfig.currentUserUid = null;
      }
      return _applyQrWelcomeIfNeeded(route, firebaseUser: null);
    }

    AuthConfig.currentUserUid = firebaseUser.uid;
    final storedUid = await SessionStorage.getStoredUser();
    if (storedUid == firebaseUser.uid) {
      final role = await SessionStorage.getStoredRole();
      switch (role) {
        case UserRole.governor:
          route = '/governor-dashboard';
          break;
        case UserRole.provincialTourism:
          route = '/provincial-tourism-dashboard';
          break;
        case UserRole.tourism:
          route = '/lgu-dashboard';
          break;
        case UserRole.tourismEstablishment:
          route = '/establishment-dashboard';
          break;
        case UserRole.tourist:
          route = '/dashboard';
          break;
      }
    } else {
      final email = firebaseUser.email ?? '';
      final roleFromEmail = SessionStorage.getRoleFromEmail(email);
      if (roleFromEmail == UserRole.governor) {
        route = '/governor-dashboard';
      } else if (roleFromEmail == UserRole.provincialTourism) {
        route = '/provincial-tourism-dashboard';
      } else if (roleFromEmail == UserRole.tourism) {
        route = '/lgu-dashboard';
      } else {
        route = '/dashboard';
      }
    }

    return _applyQrWelcomeIfNeeded(route, firebaseUser: firebaseUser);
  }

  static Future<String> _applyQrWelcomeIfNeeded(
    String route, {
    required User? firebaseUser,
  }) async {
    final pendingSpot = await PendingSpotCheckInStorage.peek();
    final pendingLgu = await PendingLguCheckInStorage.peek();
    if (firebaseUser == null) {
      if (pendingSpot != null || pendingLgu != null) return '/qr-welcome';
      if (!kIsWeb && !await MobileOnboardingStorage.isComplete()) {
        return '/mobile-onboarding';
      }
      return route;
    }
    if ((pendingSpot != null || pendingLgu != null) &&
        (route == '/dashboard' || route == '/verify-otp')) {
      return '/landing';
    }
    return route;
  }

  /// Full Firestore-backed route; run after first frame.
  static Future<String> resolveAuthoritativeRoute() async {
    var route = kIsWeb ? '/landing' : '/login';

    if (Firebase.apps.isEmpty) return route;

    var firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return route;

    final staffFastRoute = await _resolveTrustedStaffRoute(firebaseUser);
    if (staffFastRoute != null) {
      return _applyQrWelcomeIfNeeded(staffFastRoute, firebaseUser: firebaseUser);
    }

    try {
      await firebaseUser.reload();
      firebaseUser = FirebaseAuth.instance.currentUser;
    } catch (e) {
      debugPrint('Error reloading Firebase user: $e');
    }
    if (firebaseUser == null) return route;

    AuthConfig.currentUserUid = firebaseUser.uid;
    final email = firebaseUser.email ?? '';

    unawaited(
      TouristProfileHydration.hydrateFromFirestore(
        uid: firebaseUser.uid,
        email: email,
      ),
    );
    unawaited(UserProfileStorage.warmCache());

    final profile =
        await UserDirectoryService.getProfileByUid(
          firebaseUser.uid,
          preferServer: false,
        ) ??
        await UserDirectoryService.getProfileByEmail(email);

    if (profile != null) {
      route = await RoleRouter.persistSessionAndGetRoute(
        profile: profile,
        firebaseUid: firebaseUser.uid,
      );
    } else {
      final dash = await DashboardUserService.getProfileByEmail(email);
      if (dash != null && dash.role == 'governor') {
        await UserDirectoryService.ensureStaffUserDoc(
          uid: firebaseUser.uid,
          email: email,
          roleRaw: 'governor',
        );
        await SessionStorage.saveSession(
          firebaseUser.uid,
          role: UserRole.governor,
          email: email,
        );
        route = '/governor-dashboard';
      } else if (dash != null && dash.role == 'tourism') {
        var municipalityId = getMunicipalityIdFromName(dash.municipality);
        if (municipalityId.isEmpty) {
          municipalityId =
              SessionStorage.getMunicipalityIdFromTourismEmail(email) ?? '';
        }
        await UserDirectoryService.ensureStaffUserDoc(
          uid: firebaseUser.uid,
          email: email,
          roleRaw: 'tourism',
          municipalityId: municipalityId.isNotEmpty ? municipalityId : null,
        );
        await SessionStorage.saveSession(
          firebaseUser.uid,
          role: UserRole.tourism,
          email: email,
          municipalityId: municipalityId.isNotEmpty ? municipalityId : null,
        );
        route = '/lgu-dashboard';
      } else {
        final legacyMunId = SessionStorage.getMunicipalityIdFromTourismEmail(
          email,
        );
        if (legacyMunId != null) {
          await UserDirectoryService.ensureStaffUserDoc(
            uid: firebaseUser.uid,
            email: email,
            roleRaw: 'tourism',
            municipalityId: legacyMunId,
          );
          await SessionStorage.saveSession(
            firebaseUser.uid,
            role: UserRole.tourism,
            email: email,
            municipalityId: legacyMunId,
          );
          route = '/lgu-dashboard';
        } else if (email.toLowerCase().trim() ==
            SessionStorage.tourismEmail.toLowerCase()) {
          await UserDirectoryService.ensureStaffUserDoc(
            uid: firebaseUser.uid,
            email: email,
            roleRaw: 'tourism',
          );
          await SessionStorage.saveSession(
            firebaseUser.uid,
            role: UserRole.tourism,
            email: email,
          );
          route = '/lgu-dashboard';
        } else if (SessionStorage.isProvincialTourismEmail(email)) {
          await UserDirectoryService.ensureStaffUserDoc(
            uid: firebaseUser.uid,
            email: email,
            roleRaw: 'provincial_tourism',
          );
          await SessionStorage.saveSession(
            firebaseUser.uid,
            role: UserRole.provincialTourism,
            email: email,
          );
          route = '/provincial-tourism-dashboard';
        } else {
          await SessionStorage.saveSession(
            firebaseUser.uid,
            role: UserRole.tourist,
            email: email,
          );
          final verified =
              await UserDirectoryService.touristEmailVerificationComplete(
                firebaseUser.uid,
              );
          route = verified ? '/dashboard' : '/verify-otp';
        }
      }
    }

    return _applyQrWelcomeIfNeeded(route, firebaseUser: firebaseUser);
  }

  /// If authoritative route differs from what UI showed, replace root route.
  static Future<void> refineAndNavigateIfNeeded(
    String currentRoute, {
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    try {
      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        final staffFastRoute = await _resolveTrustedStaffRoute(firebaseUser);
        if (staffFastRoute != null && staffFastRoute == currentRoute) {
          return;
        }
      }

      final authoritative = await resolveAuthoritativeRoute();
      if (authoritative == currentRoute) return;

      // Keep verified tourists on the dashboard if Firestore is briefly stale.
      if (authoritative == '/verify-otp' && currentRoute == '/dashboard') {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null &&
            await SessionStorage.isTouristEmailVerifiedCached(uid)) {
          return;
        }
      }

      final nav = navigatorKey.currentState;
      if (nav == null) return;
      nav.pushReplacementNamed(authoritative);
      debugPrint('Startup refined route: $currentRoute → $authoritative');
    } catch (e) {
      debugPrint('Startup route refine skipped: $e');
    }
  }

  /// Staff with matching session + email heuristics — skip Firestore reload.
  static Future<String?> _resolveTrustedStaffRoute(User firebaseUser) async {
    final storedUid = await SessionStorage.getStoredUser();
    if (storedUid != firebaseUser.uid) return null;

    final storedRole = await SessionStorage.getStoredRole();
    if (!SessionStorage.isStaffRole(storedRole)) {
      return null;
    }

    final emailRole = SessionStorage.getRoleFromEmail(firebaseUser.email ?? '');
    if (emailRole != storedRole) return null;

    return SessionStorage.getDashboardRoute(storedRole);
  }

  /// Waits for Firebase Auth persistence to restore the signed-in user after restart.
  static Future<User?> _waitForRestoredFirebaseUser() async {
    var user = FirebaseAuth.instance.currentUser;
    if (user != null) return user;

    final timeout = kIsWeb
        ? const Duration(seconds: 3)
        : const Duration(milliseconds: 1500);

    try {
      user = await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((u) => u != null)
          .timeout(timeout);
    } catch (_) {
      user = FirebaseAuth.instance.currentUser;
    }
    return user;
  }
}
