import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'admin_accounts_service.dart';
import 'auth_role_claims.dart'
    show persistLongTermStaffRoleClaims, refreshAuthRoleClaims;
import 'auth_roles.dart';
import '../firestore_loader.dart';
import 'tourism_session.dart';

/// True when the signed-in user should use the admin dashboard (no network).
bool isKnownAdminEmail(String email) =>
    AdminAccountsService.emailMatchesDefaultAdmin(email);

bool isLikelyAdminSession() {
  final email = FirebaseAuth.instance.currentUser?.email ?? '';
  if (isKnownAdminEmail(email)) return true;
  return AuthRoles.canAccessAdminDashboard();
}

/// After sign-in: JWT role first, then Firestore — avoids sending tourists to admin UI.
Future<bool> resolveOpenAdminDashboardAfterLogin() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;

  final email = user.email ?? '';
  if (isKnownAdminEmail(email)) return true;

  try {
    await refreshAuthRoleClaims();
    final role = await AuthRoles.currentRoleAsync();
    if (role == AppRole.admin || role == AppRole.municipalManager) {
      return true;
    }
    if (role == AppRole.tourist || role == AppRole.user) {
      return false;
    }
  } catch (e) {
    debugPrint('resolveOpenAdminDashboardAfterLogin claims: $e');
  }

  if (await AdminAccountsService.isCurrentUserAdminAccount()) {
    return true;
  }

  try {
    await loadUsersFromFirestore();
  } catch (e) {
    debugPrint('resolveOpenAdminDashboardAfterLogin users: $e');
  }
  return isLikelyAdminSession();
}

/// Heavy Firestore work after the admin UI is already visible.
Future<void> bootstrapAdminSessionInBackground() async {
  try {
    await AdminAccountsService.applyAdminRoleIfRegistered();
    await persistLongTermStaffRoleClaims();
    await bootstrapAppFirestoreOnce();
  } catch (e, st) {
    debugPrint('bootstrapAdminSessionInBackground: $e\n$st');
  }
}

/// Reloads catalogs when the admin dashboard opens (startup may have run as guest).
Future<void> prefetchAdminDashboardCatalogs() async {
  try {
    await AdminAccountsService.applyAdminRoleIfRegistered();
    await persistLongTermStaffRoleClaims();
    await reloadAdminDashboardCatalogs();
  } catch (e, st) {
    debugPrint('prefetchAdminDashboardCatalogs: $e\n$st');
  }
}
