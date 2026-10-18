import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:trip_plan/services/admin_accounts_service.dart';

enum TripPlannerAccessResult { allowed, signedOut, denied }

/// Trip Planner is tourist-only and uses the ATMOS Firebase user + `users` profile.
class TripPlannerAccess {
  TripPlannerAccess._();

  static const String deniedMessage =
      'Trip Planner is available only for Tourist accounts.';

  static bool allowsRole(String? roleRaw) =>
      (roleRaw ?? '').trim().toLowerCase() == 'tourist';

  /// Governor, provincial tourism, and LGU tourism open the Trip Planner
  /// admin dashboard. Their Firestore role is not changed.
  static bool isCatalogAdminRole(String? roleRaw) {
    final role = (roleRaw ?? '')
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

  /// Trip Planner admin accounts (including OPTACA) even when the ATMOS
  /// email map still treats the address as a tourist.
  static bool isTripPlannerAdminEmail(String? email) {
    final value = (email ?? '').trim();
    if (value.isEmpty) return false;
    return AdminAccountsService.emailMatchesDefaultAdmin(value) ||
        isRegisteredAdminEmail(value);
  }

  static Future<bool> isCatalogAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    final email = user.email ?? '';
    if (isTripPlannerAdminEmail(email)) return true;
    if (email.isNotEmpty &&
        _storedRoleIsCatalogAdmin(SessionStorage.getRoleFromEmail(email)) &&
        SessionStorage.isStaffRole(SessionStorage.getRoleFromEmail(email))) {
      return true;
    }
    final profile = await UserDirectoryService.getProfileByUid(user.uid);
    if (profile != null && isCatalogAdminRole(profile.roleRaw)) return true;
    final storedUid = await SessionStorage.getStoredUser();
    if (storedUid != user.uid) return false;
    final stored = await SessionStorage.getStoredRole();
    return _storedRoleIsCatalogAdmin(stored);
  }

  static bool _storedRoleIsCatalogAdmin(UserRole role) {
    return role == UserRole.governor ||
        role == UserRole.provincialTourism ||
        role == UserRole.tourism;
  }

  static Future<TripPlannerAccessResult> evaluate() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return TripPlannerAccessResult.signedOut;

    final email = user.email ?? '';
    if (email.isNotEmpty &&
        SessionStorage.isStaffRole(SessionStorage.getRoleFromEmail(email))) {
      return TripPlannerAccessResult.denied;
    }

    final storedUid = await SessionStorage.getStoredUser();
    final stored = await SessionStorage.getStoredRole();
    final sessionMatches = storedUid == user.uid;
    if (sessionMatches && stored != UserRole.tourist) {
      return TripPlannerAccessResult.denied;
    }

    final profile = await UserDirectoryService.getProfileByUid(user.uid);
    if (profile != null) {
      return allowsRole(profile.roleRaw)
          ? TripPlannerAccessResult.allowed
          : TripPlannerAccessResult.denied;
    }

    if (sessionMatches && stored == UserRole.tourist) {
      return TripPlannerAccessResult.allowed;
    }
    return TripPlannerAccessResult.denied;
  }

  static Future<void> showDenied(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tourist accounts only'),
        content: const Text(deniedMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
