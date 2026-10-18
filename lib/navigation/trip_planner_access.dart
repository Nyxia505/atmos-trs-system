import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

enum TripPlannerAccessResult { allowed, signedOut, denied }

/// Trip Planner is tourist-only and uses the ATMOS Firebase user + `users` profile.
class TripPlannerAccess {
  TripPlannerAccess._();

  static const String deniedMessage =
      'Trip Planner is available only for Tourist accounts.';

  static bool allowsRole(String? roleRaw) =>
      (roleRaw ?? '').trim().toLowerCase() == 'tourist';

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
