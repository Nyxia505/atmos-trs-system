import 'package:atmos_trs_system/config/session_storage.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/config/auth_config.dart';

/// Maps Firestore [AppUserProfile] + session to dashboard routes.
///
/// **Do not** route by email string alone — always use [AppUserProfile.roleRaw]
/// and [AppUserProfile.municipality] from Firestore.
class RoleRouter {
  RoleRouter._();

  /// Saves [SessionStorage] and returns a [Navigator] route name.
  static Future<String> persistSessionAndGetRoute({
    required AppUserProfile profile,
    required String firebaseUid,
  }) async {
    AuthConfig.currentUserUid = firebaseUid;

    if (profile.isGovernor) {
      await UserDirectoryService.ensureStaffUserDoc(
        uid: firebaseUid,
        email: profile.email,
        roleRaw: 'governor',
        fullName: profile.fullName,
      );
      await SessionStorage.saveSession(
        firebaseUid,
        role: UserRole.governor,
        email: profile.email,
      );
      return '/governor-dashboard';
    }

    if (profile.isTourismOffice) {
      await UserDirectoryService.ensureStaffUserDoc(
        uid: firebaseUid,
        email: profile.email,
        roleRaw: profile.roleRaw,
        fullName: profile.fullName,
      );
      String municipalityId = getMunicipalityIdFromName(profile.municipality);
      if (municipalityId.isEmpty) {
        municipalityId =
            SessionStorage.getMunicipalityIdFromTourismEmail(profile.email) ??
            '';
      }
      await SessionStorage.saveSession(
        firebaseUid,
        role: UserRole.tourism,
        email: profile.email,
        municipalityId: municipalityId.isNotEmpty ? municipalityId : null,
      );
      return '/lgu-dashboard';
    }

    if (profile.isTourist) {
      await SessionStorage.saveSession(
        firebaseUid,
        role: UserRole.tourist,
        email: profile.email,
      );
      final verified =
          await UserDirectoryService.touristEmailVerificationComplete(
        firebaseUid,
      );
      if (!verified) return '/verify-otp';
      return '/dashboard';
    }

    // Unknown role — safe default
    await SessionStorage.saveSession(
      firebaseUid,
      role: UserRole.tourist,
      email: profile.email,
    );
    return '/dashboard';
  }

  /// Cold start: when profile is already loaded (e.g. from [getProfileByUid]).
  static String routeForProfile(AppUserProfile profile) {
    if (profile.isGovernor) return '/governor-dashboard';
    if (profile.isTourismOffice) return '/lgu-dashboard';
    if (profile.isTourist && !profile.isVerified) {
      return '/verify-otp';
    }
    if (profile.isTourist) return '/dashboard';
    return '/dashboard';
  }
}
