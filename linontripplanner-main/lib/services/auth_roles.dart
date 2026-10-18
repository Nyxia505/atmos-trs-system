import 'package:firebase_auth/firebase_auth.dart';

import '../data.dart';
import '../admin_accounts_loader.dart';
import 'admin_accounts_service.dart';
import 'auth_role_claims.dart';

/// Supported app roles (normalized lowercase).
enum AppRole {
  tourist,
  user,
  admin,
  municipalManager;

  static AppRole fromString(String? raw) {
    final r = (raw ?? '').trim().toLowerCase().replaceAll(' ', '_');
    switch (r) {
      case 'admin':
      case 'administrator':
      case 'governor':
        return AppRole.admin;
      case 'municipal_manager':
      case 'municipalmanager':
      case 'municipal manager':
      case 'manager':
        return AppRole.municipalManager;
      case 'tourist':
        return AppRole.tourist;
      case 'user':
      default:
        return AppRole.user;
    }
  }

  String get label {
    switch (this) {
      case AppRole.admin:
        return 'Admin';
      case AppRole.municipalManager:
        return 'Municipal Manager';
      case AppRole.tourist:
        return 'Tourist';
      case AppRole.user:
        return 'User';
    }
  }

  String get firestoreValue {
    switch (this) {
      case AppRole.admin:
        return 'admin';
      case AppRole.municipalManager:
        return 'municipal_manager';
      case AppRole.tourist:
        return 'tourist';
      case AppRole.user:
        return 'user';
    }
  }
}

/// Role checks for the signed-in Firebase user + cached [users] list.
class AuthRoles {
  AuthRoles._();

  static AppRole roleForUser(AppUser? user) => AppRole.fromString(user?.role);

  static AppRole currentRole() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return AppRole.tourist;
    final match = findAppUserByFirebaseUid(uid);
    return roleForUser(match);
  }

  /// Prefer JWT custom claims (permanent); falls back to Firestore [users] role.
  static Future<AppRole> currentRoleAsync() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return AppRole.tourist;
    final match = findAppUserByFirebaseUid(uid);
    return resolveAppRole(fallbackRole: match?.role ?? 'tourist');
  }

  /// ATMOS staff who manage the trip-planner catalog. Their Firestore role
  /// stays unchanged so ATMOS routing is not rewritten to `admin`.
  static bool isAtmosStaffAdminRole(String? raw) {
    final role = (raw ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s-]+'), '_');
    const roles = {
      'governor',
      'provincial_tourism',
      'tourism_province',
      'tourism',
      'tourism_office',
      'lgu_tourism',
      'admin',
      'municipal_manager',
      'municipalmanager',
    };
    return roles.contains(role);
  }

  /// Governor portal + full content management.
  static bool canAccessAdminDashboard([AppUser? user]) {
    final resolved =
        user ?? findAppUserByFirebaseUid(FirebaseAuth.instance.currentUser?.uid);
    final role = roleForUser(resolved);
    if (role == AppRole.admin || role == AppRole.municipalManager) {
      return true;
    }
    if (isAtmosStaffAdminRole(resolved?.role)) return true;
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return AdminAccountsService.emailMatchesDefaultAdmin(email) ||
        isRegisteredAdminEmail(email);
  }

  /// Municipal managers: events/announcements for their area (subset enforced in UI).
  static bool isMunicipalManager([AppUser? user]) {
    final role = user != null ? roleForUser(user) : currentRole();
    return role == AppRole.municipalManager;
  }

  static bool isAdmin([AppUser? user]) {
    final role = user != null ? roleForUser(user) : currentRole();
    return role == AppRole.admin;
  }

  static const adminRolePresetValues = [
    'tourist',
    'user',
    'admin',
    'municipal_manager',
  ];
}
