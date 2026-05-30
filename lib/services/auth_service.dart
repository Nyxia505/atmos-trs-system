import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
    if (kIsWeb) {
      final continueUrl = _passwordResetContinueUrl();
      actionCodeSettings = ActionCodeSettings(
        url: continueUrl,
        handleCodeInApp: false,
      );
    }

    await _auth.sendPasswordResetEmail(
      email: normalized,
      actionCodeSettings: actionCodeSettings,
    );
  }

  /// Where users land after finishing reset on Firebase's page (web only).
  static String _passwordResetContinueUrl() {
    final origin = Uri.base.origin;
    final path = Uri.base.path;
    if (path.isEmpty || path == '/') {
      return '$origin/login';
    }
    if (path.endsWith('/')) {
      return '${origin}${path}login';
    }
    if (path.endsWith('index.html')) {
      final base = path.substring(0, path.length - 'index.html'.length);
      return '$origin$base/login';
    }
    return '$origin/login';
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
      default:
        if (raw != null && raw.isNotEmpty) return raw;
        return 'Could not send reset email. Please try again.';
    }
  }

  /// Firebase email link verification: when [User.emailVerified] is true, routing
  /// treats the tourist as verified (see [UserDirectoryService.syncVerifiedStatusFromAuthIfNeeded]).
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
}
