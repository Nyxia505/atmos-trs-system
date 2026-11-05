import 'package:firebase_auth/firebase_auth.dart';

/// SnackBar extra action for a failed login (Forgot Password / Sign Up).
enum LoginAuthAction { none, forgotPassword, signUp }

/// User-facing login failure: copy, whether to clear the password, and a CTA.
class LoginAuthFeedback {
  const LoginAuthFeedback({
    required this.message,
    this.clearPassword = false,
    this.action = LoginAuthAction.none,
  });

  final String message;
  final bool clearPassword;
  final LoginAuthAction action;
}

/// Shared login copy. Firebase Identity Toolkit often returns
/// `invalid-credential` for both a missing account and a wrong password
/// (email enumeration protection). Those cases stay ambiguous on purpose.
class LoginAuthMessages {
  LoginAuthMessages._();

  static const emptyEmail = 'Please enter your email address.';
  static const invalidEmail = 'Please enter a valid email address.';
  static const emptyPassword = 'Please enter your password.';
  static const wrongPassword =
      'Sorry, your password is incorrect. Please try again.';
  static const unregisteredEmail =
      'Sorry, your email is not registered. Please sign up first.';
  static const ambiguousCredentials =
      'Incorrect email or password. Please try again or sign up.';
  static const networkError =
      'Unable to connect. Please check your internet connection.';
  static const tooManyAttempts =
      'Too many attempts. Please try again later.';
  static const genericFailure = 'Could not sign in. Please try again.';
  static const accountDisabled = 'This account has been disabled.';

  static String normalizeCode(String code) {
    return code
        .replaceAll(RegExp(r'^firebase_auth/', caseSensitive: false), '')
        .trim()
        .replaceAll('_', '-')
        .toLowerCase();
  }

  static LoginAuthFeedback fromException(FirebaseAuthException e) {
    return fromCode(e.code, message: e.message);
  }

  static LoginAuthFeedback fromCode(String rawCode, {String? message}) {
    final code = normalizeCode(rawCode);
    switch (code) {
      case 'invalid-email':
        return const LoginAuthFeedback(message: invalidEmail);
      case 'user-disabled':
        return const LoginAuthFeedback(message: accountDisabled);
      case 'too-many-requests':
        return const LoginAuthFeedback(message: tooManyAttempts);
      case 'network-request-failed':
        return const LoginAuthFeedback(message: networkError);
      case 'user-not-found':
        return const LoginAuthFeedback(
          message: unregisteredEmail,
          action: LoginAuthAction.signUp,
        );
      case 'wrong-password':
      case 'invalid-password':
        return const LoginAuthFeedback(
          message: wrongPassword,
          clearPassword: true,
          action: LoginAuthAction.forgotPassword,
        );
      case 'invalid-credential':
      case 'invalid-login-credentials':
        // Enumeration protection: do not claim the email exists or does not.
        return const LoginAuthFeedback(
          message: ambiguousCredentials,
          clearPassword: true,
          action: LoginAuthAction.signUp,
        );
    }

    final lower = (message ?? '').toLowerCase();
    if (lower.contains('network') ||
        lower.contains('socket') ||
        lower.contains('connection')) {
      return const LoginAuthFeedback(message: networkError);
    }
    if (lower.contains('too many') || lower.contains('many attempts')) {
      return const LoginAuthFeedback(message: tooManyAttempts);
    }
    return const LoginAuthFeedback(message: genericFailure);
  }

  static LoginAuthFeedback unknownFailure(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('socket') ||
        text.contains('network') ||
        text.contains('failed host lookup') ||
        text.contains('connection')) {
      return const LoginAuthFeedback(message: networkError);
    }
    return const LoginAuthFeedback(message: genericFailure);
  }
}
