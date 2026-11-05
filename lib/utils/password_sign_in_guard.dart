import 'package:atmos_trs_system/utils/email_utils.dart';

/// Rules for treating a Firebase sign-in as valid for an explicit login attempt.
class PasswordSignInGuard {
  PasswordSignInGuard._();

  /// The Auth user from [signInWithEmailAndPassword] must exist and match the
  /// email the person just typed. A leftover [currentUser] from another session
  /// is not proof that this password was accepted.
  static bool credentialMatchesAttempt({
    required String submittedEmail,
    required String? authenticatedEmail,
    required String? authenticatedUid,
  }) {
    if (authenticatedUid == null || authenticatedUid.isEmpty) return false;
    if (authenticatedEmail == null || authenticatedEmail.isEmpty) return false;
    return normalizeEmail(authenticatedEmail) == normalizeEmail(submittedEmail);
  }

  /// Firestore `users/{uid}` must be the same account as Firebase Auth.
  static bool profileBelongsToAuthUser({
    required String firebaseUid,
    required String profileUid,
  }) {
    return firebaseUid.isNotEmpty &&
        profileUid.isNotEmpty &&
        firebaseUid == profileUid;
  }
}
