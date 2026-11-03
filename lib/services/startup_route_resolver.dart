import 'dart:async' show unawaited;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/module_shell_prefs.dart';
import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:atmos_trs_system/navigation/role_router.dart';
import 'package:atmos_trs_system/services/dashboard_user_service.dart';
import 'package:atmos_trs_system/services/mobile_onboarding_storage.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/services/tourist_profile_hydration.dart';
import 'package:atmos_trs_system/services/lgu_office_registry_service.dart';
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

    final storedUidBeforeRestore = await SessionStorage.getStoredUser();
    final firebaseUser = await _waitForRestoredFirebaseUser(
      hasStoredSession:
          storedUidBeforeRestore != null && storedUidBeforeRestore.isNotEmpty,
    );

    if (firebaseUser == null) {
      // Auth restore can lag behind SharedPreferences on web. Give one more
      // short chance before wiping the session (avoids false logout on refresh).
      await Future<void>.delayed(const Duration(milliseconds: 750));
      final lateUser = FirebaseAuth.instance.currentUser;
      if (lateUser == null) {
        final storedUid = storedUidBeforeRestore;
        if (storedUid != null) {
          debugPrint(
            'Startup: clearing stale session (no Firebase Auth user after wait).',
          );
          await SessionStorage.clearSession();
          AuthConfig.currentUserUid = null;
        }
        return _applyQrWelcomeIfNeeded(route, firebaseUser: null);
      }
      return _routeForRestoredUser(lateUser);
    }

    return _routeForRestoredUser(firebaseUser);
  }

  static Future<String> _routeForRestoredUser(User firebaseUser) async {
    AuthConfig.currentUserUid = firebaseUser.uid;
    var route = kIsWeb ? '/landing' : '/login';
    final storedUid = await SessionStorage.getStoredUser();
    if (storedUid == firebaseUser.uid) {
      final role = await SessionStorage.getStoredRole();
      switch (role) {
        case UserRole.governor:
          route = '/governor-dashboard';
          break;
        case UserRole.provincialTourism:
          route = await _provincialOrTripPlannerAdminRoute();
          break;
        case UserRole.tourism:
          route = await _lguOrTripPlannerAdminRoute();
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
        route = await _provincialOrTripPlannerAdminRoute();
      } else if (roleFromEmail == UserRole.tourism) {
        route = await _lguOrTripPlannerAdminRoute();
      } else {
        route = '/dashboard';
      }
    }

    if (route == '/governor-dashboard' ||
        route == '/provincial-tourism-dashboard' ||
        route == '/lgu-dashboard' ||
        route == '/trip-planner-admin') {
      unawaited(LguOfficeRegistryService.syncForCurrentUser());
    }
    return _applyQrWelcomeIfNeeded(route, firebaseUser: firebaseUser);
  }

  /// OPTACA / catalog admin: restore Trip Planner admin shell after refresh.
  static Future<String> _provincialOrTripPlannerAdminRoute() async {
    return _maybeTripPlannerAdminShell('/provincial-tourism-dashboard');
  }

  static Future<String> _lguOrTripPlannerAdminRoute() async {
    return _maybeTripPlannerAdminShell('/lgu-dashboard');
  }

  static Future<String> _maybeTripPlannerAdminShell(String fallback) async {
    final shell = await ModuleShellPrefs.getActiveShell();
    if (shell == ModuleShellPrefs.tripPlannerAdmin) {
      return '/trip-planner-admin';
    }
    return fallback;
  }

  static Future<String> _applyQrWelcomeIfNeeded(
    String route, {
    required User? firebaseUser,
  }) async {
    final pendingSpot = await PendingSpotCheckInStorage.peek();
    final pendingLgu = await PendingLguCheckInStorage.peek();
    if (firebaseUser == null) {
      if (pendingSpot != null || pendingLgu != null) {
        // Scanned spot is already stored. Go straight to tourist login.
        return '/login';
      }
      if (!kIsWeb && !await MobileOnboardingStorage.isComplete()) {
        return '/mobile-onboarding';
      }
      return route;
    }
    if (pendingSpot != null || pendingLgu != null) {
      // Logged-in tourist with a camera/App-Link pending QR → resume fill-up.
      if (route == '/dashboard' ||
          route == '/verify-otp' ||
          route == '/landing' ||
          route == '/login') {
        return '/qr-resume';
      }
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
          route = await _provincialOrTripPlannerAdminRoute();
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

    if (route == '/provincial-tourism-dashboard' ||
        route == '/lgu-dashboard' ||
        route == '/governor-dashboard') {
      route = await _maybeTripPlannerAdminShell(route);
    }
    return _applyQrWelcomeIfNeeded(route, firebaseUser: firebaseUser);
  }

  /// If authoritative route differs from what UI showed, replace root route.
  static Future<void> refineAndNavigateIfNeeded(
    String currentRoute, {
    required GlobalKey<NavigatorState> navigatorKey,
  }) async {
    try {
      // Do not kick OPTACA off Trip Planner admin while Auth/profile is refining.
      if (currentRoute == '/trip-planner-admin' &&
          FirebaseAuth.instance.currentUser != null &&
          await ModuleShellPrefs.getActiveShell() ==
              ModuleShellPrefs.tripPlannerAdmin) {
        return;
      }

      final firebaseUser = FirebaseAuth.instance.currentUser;
      if (firebaseUser != null) {
        final staffFastRoute = await _resolveTrustedStaffRoute(firebaseUser);
        if (staffFastRoute != null && staffFastRoute == currentRoute) {
          return;
        }
      }

      var authoritative = await resolveAuthoritativeRoute();
      authoritative = await _maybeTripPlannerAdminShell(authoritative);
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

    final base = SessionStorage.getDashboardRoute(storedRole);
    return _maybeTripPlannerAdminShell(base);
  }

  /// Waits for Firebase Auth persistence to restore the signed-in user after restart.
  ///
  /// With a saved session we wait longer so a slow restore (cold start, weak
  /// network, web IndexedDB) does not wipe the session and bounce to login.
  static Future<User?> _waitForRestoredFirebaseUser({
    bool hasStoredSession = false,
  }) async {
    var user = FirebaseAuth.instance.currentUser;
    if (user != null) return user;

    final timeout = hasStoredSession
        ? const Duration(seconds: 12)
        : kIsWeb
            ? const Duration(seconds: 5)
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
