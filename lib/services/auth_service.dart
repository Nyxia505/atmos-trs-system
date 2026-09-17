import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:atmos_trs_system/utils/email_utils.dart';
import 'package:atmos_trs_system/utils/firebase_client_blocked_message.dart';

/// Auth helpers: Firebase Auth session + legacy email verification (optional).
class AuthService {
  AuthService._();

  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static User? get currentUser => _auth.currentUser;

  /// Signs out (clears Firebase Auth session).
  static Future<void> signOut() => _auth.signOut();

  /// Legacy Firebase email link reset (often lands in spam). Prefer
  /// [PasswordResetService] OTP + push notification flow instead.
  static Future<void> sendPasswordResetEmail(String email) async {
    final normalized = normalizeEmail(email);
    if (!isValidEmailFormat(normalized)) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Please enter a valid email address.',
      );
    }

    ActionCodeSettings? actionCodeSettings;
    final continueUrl = _passwordResetContinueUrl();
    actionCodeSettings = ActionCodeSettings(
      url: continueUrl,
      handleCodeInApp: kIsWeb,
      androidPackageName: kIsWeb ? null : 'com.atmos.trs',
      androidInstallApp: !kIsWeb,
      androidMinimumVersion: kIsWeb ? null : '1',
    );

    await _auth.sendPasswordResetEmail(
      email: normalized,
      actionCodeSettings: actionCodeSettings,
    );
  }

  /// Completes a Firebase email-link reset using the `oobCode` from the email.
  static Future<void> confirmPasswordResetWithCode({
    required String oobCode,
    required String newPassword,
  }) async {
    await _auth.confirmPasswordReset(code: oobCode.trim(), newPassword: newPassword);
  }

  /// True when [code] is still valid for setting a new password.
  static Future<void> verifyPasswordResetCode(String code) async {
    await _auth.verifyPasswordResetCode(code.trim());
  }

  /// Legacy helper — prefer [_passwordResetContinueUrl].
  static String passwordResetContinueUrl() => _passwordResetContinueUrl();

  /// Where users land after finishing reset on Firebase's page (web only).
  static String _passwordResetContinueUrl() {
    final origin = Uri.base.origin;
    final path = Uri.base.path;
    String basePath;
    if (path.isEmpty || path == '/') {
      basePath = '/';
    } else if (path.endsWith('index.html')) {
      basePath = path.substring(0, path.length - 'index.html'.length);
    } else if (path.endsWith('/')) {
      basePath = path;
    } else {
      basePath = '$path/';
    }
    return '$origin${basePath}forgot-password';
  }

  /// User-facing message for password-reset failures.
  static String passwordResetErrorMessage(FirebaseAuthException e) {
    final raw = e.message?.trim();
    if (looksLikeGoogleFirebaseClientBlocked(raw)) {
      return firebaseClientBlockedUserMessage();
    }
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'too-many-requests':
        return 'Too many requests. Please wait a few minutes and try again.';
      case 'user-not-found':
        return 'No login account exists for this email. '
            'Use Sign Up to create one, or check the spelling.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'expired-action-code':
        return 'This reset link has expired. Request a new one.';
      case 'invalid-action-code':
        return 'This reset link is invalid or already used. Request a new one.';
      case 'weak-password':
        return 'Password is too weak. Use at least 8 characters with uppercase, lowercase, and a number.';
      default:
        if (raw != null && raw.isNotEmpty) return raw;
        return 'Could not send reset email. Please try again.';
    }
  }

  /// Sends Firebase's built-in verification email (optional). Tourist routing uses
  /// in-app OTP on [VerifyOtpScreen], not [User.emailVerified].
  static Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) return;
    if (user.emailVerified) return;
    await _auth.currentUser!.sendEmailVerification();
  }

  static Future<bool> reloadAndCheckEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await _auth.currentUser!.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  /// Re-authenticates the signed-in user then sets a new password in Firebase Auth.
  /// Call this when staff change password in Settings so login stays in sync with
  /// SharedPreferences overrides.
  static Future<void> reauthenticateAndUpdatePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'Not signed in. Log in again, then change your password.',
      );
    }
    final credential = EmailAuthProvider.credential(
      email: normalizeEmail(email),
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
  }

  /// Demo governor/tourism: Settings may update SharedPreferences while Firebase Auth
  /// still has the previous password. Sign in with a known prior password, then push
  /// [newPassword] into Auth so the next login succeeds.
  static Future<UserCredential?> syncDemoStaffAuthPassword({
    required String email,
    required String newPassword,
    required Iterable<String> previousPasswordCandidates,
  }) async {
    final normalized = normalizeEmail(email);
    for (final oldPassword in previousPasswordCandidates) {
      if (oldPassword.isEmpty || oldPassword == newPassword) continue;
      try {
        var cred = await _auth.signInWithEmailAndPassword(
          email: normalized,
          password: oldPassword,
        );
        final user = cred.user;
        if (user == null) continue;
        try {
          await user.updatePassword(newPassword);
        } on FirebaseAuthException catch (e) {
          debugPrint(
            '[Auth] syncDemoStaff updatePassword failed: ${e.code} ${e.message}',
          );
          if (e.code == 'requires-recent-login') {
            try {
              cred = await _auth.signInWithEmailAndPassword(
                email: normalized,
                password: oldPassword,
              );
              await cred.user?.updatePassword(newPassword);
            } on FirebaseAuthException catch (e2) {
              debugPrint(
                '[Auth] syncDemoStaff retry updatePassword failed: ${e2.code}',
              );
              // Keep the signed-in session anyway so the governor can proceed.
            }
          }
          // Keep signed-in session even if Auth password could not be updated.
        }
        return cred;
      } on FirebaseAuthException catch (e) {
        debugPrint(
          '[Auth] syncDemoStaff sign-in candidate failed: ${e.code}',
        );
        continue;
      } catch (e) {
        debugPrint('[Auth] syncDemoStaff error: $e');
        continue;
      }
    }
    return null;
  }
}
