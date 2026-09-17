import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:atmos_trs_system/services/auth_service.dart';
import 'package:atmos_trs_system/utils/email_utils.dart';
import 'package:atmos_trs_system/utils/signup_field_validation.dart';

/// Password reset: OTP + push/SMS/email (Cloud Functions) with Firebase email-link fallback.
class PasswordResetService {
  PasswordResetService._();
 
  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  static const Duration _callableTimeout = Duration(seconds: 25);

  static bool _otpWasDelivered(PasswordResetOtpRequestResult parsed) {
    if (parsed.emailSent || parsed.smsSent) return true;
    // Push notifications are not available on web browsers.
    if (!kIsWeb && parsed.pushSent) return true;
    return false;
  }

  /// Sends Firebase's password-reset email (link). Works without Cloud Functions.
  static Future<PasswordResetOtpRequestResult> requestEmailResetLink(
    String email,
  ) async {
    return _sendEmailLinkFallback(normalizeEmail(email));
  }

  /// Completes reset from a Firebase email link (`oobCode` query param on web).
  static Future<void> completeResetFromEmailLink({
    required String oobCode,
    required String newPassword,
  }) async {
    final strengthError = validateStrongPassword(newPassword);
    if (strengthError != null) {
      throw ArgumentError(strengthError);
    }
    final code = oobCode.trim();
    if (code.isEmpty) {
      throw ArgumentError('Reset link is invalid. Request a new one.');
    }
    try {
      await AuthService.verifyPasswordResetCode(code);
      await AuthService.confirmPasswordResetWithCode(
        oobCode: code,
        newPassword: newPassword,
      );
    } on FirebaseAuthException catch (e) {
      throw FirebaseAuthException(
        code: e.code,
        message: AuthService.passwordResetErrorMessage(e),
      );
    }
  }

  /// Step 1: prefer OTP via Cloud Functions; falls back to Firebase reset email if
  /// functions are not deployed or cannot deliver the code.
  static Future<PasswordResetOtpRequestResult> requestOtp(String email) async {
    if (Firebase.apps.isEmpty) {
      throw StateError('Firebase is not available.');
    }
    final normalized = normalizeEmail(email);
    if (!isValidEmailFormat(normalized)) {
      throw ArgumentError('Please enter a valid email address.');
    }

    try {
      final callable = _functions.httpsCallable('requestPasswordResetOtp');
      final result = await callable
          .call<Map<String, dynamic>>({'email': normalized})
          .timeout(_callableTimeout);
      final data = Map<String, dynamic>.from(result.data);
      final parsed = PasswordResetOtpRequestResult.fromMap(data, email: normalized);

      if (!parsed.accountFound) {
        return parsed;
      }

      final delivered = _otpWasDelivered(parsed);
      if (!delivered) {
        debugPrint('[PasswordReset] OTP not delivered; trying email link fallback.');
        return _sendEmailLinkFallback(normalized);
      }
      return parsed;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[PasswordReset] callable failed: ${e.code} ${e.message}');
      if (_shouldUseEmailLinkFallbackOnRequest(e)) {
        return _sendEmailLinkFallback(normalized);
      }
      rethrow;
    } on TimeoutException catch (e, st) {
      debugPrint('[PasswordReset] callable timeout: $e\n$st');
      return _sendEmailLinkFallback(normalized);
    } catch (e, st) {
      debugPrint('[PasswordReset] callable error: $e\n$st');
      if (_looksLikeFunctionsUnavailable(e)) {
        return _sendEmailLinkFallback(normalized);
      }
      rethrow;
    }
  }

  /// Step 2: verify OTP and set new password (requires deployed Cloud Function).
  static Future<void> completeReset({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    if (Firebase.apps.isEmpty) {
      throw StateError('Firebase is not available.');
    }
    final normalized = normalizeEmail(email);
    final strengthError = validateStrongPassword(newPassword);
    if (strengthError != null) {
      throw ArgumentError(strengthError);
    }
    final digits = otp.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 6) {
      throw ArgumentError('Enter the 6-digit code.');
    }
    try {
      final callable = _functions.httpsCallable('completePasswordResetWithOtp');
      await callable
          .call<void>({
            'email': normalized,
            'otp': digits,
            'newPassword': newPassword,
          })
          .timeout(_callableTimeout);
    } on FirebaseFunctionsException catch (e) {
      if (_shouldUseEmailLinkFallbackOnComplete(e)) {
        await _sendEmailLinkFallback(normalized);
        throw PasswordResetNeedsEmailLinkException();
      }
      rethrow;
    } on TimeoutException {
      await _sendEmailLinkFallback(normalized);
      throw PasswordResetNeedsEmailLinkException();
    }
  }

  /// Functions missing or down — use Firebase reset email instead.
  static bool _shouldUseEmailLinkFallbackOnRequest(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'invalid-argument':
      case 'deadline-exceeded':
      case 'resource-exhausted':
      case 'permission-denied':
      case 'unauthenticated':
        return false;
      case 'not-found':
      case 'internal':
      case 'unavailable':
      case 'unknown':
      case 'failed-precondition':
        return true;
      default:
        return false;
    }
  }

  /// OTP verify failed vs service down — only fallback when the callable is unavailable.
  static bool _shouldUseEmailLinkFallbackOnComplete(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'invalid-argument':
      case 'not-found':
      case 'deadline-exceeded':
      case 'resource-exhausted':
      case 'permission-denied':
      case 'unauthenticated':
        return false;
      case 'internal':
      case 'unavailable':
      case 'unknown':
      case 'failed-precondition':
        return true;
      default:
        return false;
    }
  }

  static bool _looksLikeFunctionsUnavailable(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('not-found') ||
        s.contains('unavailable') ||
        s.contains('deadline');
  }

  static Future<PasswordResetOtpRequestResult> _sendEmailLinkFallback(
    String email,
  ) async {
    try {
      await AuthService.sendPasswordResetEmail(email);
      return PasswordResetOtpRequestResult(
        email: email,
        accountFound: true,
        pushSent: false,
        emailSent: true,
        emailLinkSent: true,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        return PasswordResetOtpRequestResult(
          email: email,
          accountFound: false,
          pushSent: false,
          emailSent: false,
        );
      }
      rethrow;
    }
  }

  static String messageForOtpRequest(PasswordResetOtpRequestResult result) {
    if (result.emailLinkSent) {
      return 'Reset link sent to ${maskEmailForDisplay(result.email)}. '
          'Open the email, tap the link, and set a new password.';
    }
    if (!result.accountFound) {
      return 'If an account exists for ${maskEmailForDisplay(result.email)}, '
          'you will receive a 6-digit code by email, SMS, or phone notification.';
    }
    if (result.pushSent && result.emailSent && result.smsSent) {
      return 'Code sent! Check your phone notification, SMS, and email inbox.';
    }
    if (result.smsSent && result.emailSent) {
      return 'Code sent via SMS and email. Check your phone and inbox.';
    }
    if (result.pushSent && result.emailSent) {
      return 'Code sent! Check your phone notification first, then your email inbox.';
    }
    if (result.pushSent) {
      return 'Check your phone notification for the 6-digit code.';
    }
    if (result.smsSent) {
      return 'Code sent via SMS to your registered mobile number.';
    }
    if (result.emailSent) {
      return 'Code sent to your email inbox. Check spam if you do not see it.';
    }
    return 'Could not deliver the code. Tap Resend code or try again later.';
  }

  static String errorMessage(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'resource-exhausted':
        return e.message ??
            'Please wait a minute before requesting another code.';
      case 'invalid-argument':
        final msg = e.message?.trim();
        if (msg != null && msg.isNotEmpty) return msg;
        return 'Invalid code or password. Check and try again.';
      case 'deadline-exceeded':
        return e.message ??
            'This code has expired. Tap Resend code for a new one.';
      case 'not-found':
        return e.message ??
            'Invalid email or verification code. Request a new code.';
      case 'unavailable':
        return 'Reset service is busy. Try again in a moment.';
      case 'internal':
        return 'Reset service error. Try again or use the email reset link if offered.';
      default:
        final msg = e.message?.trim();
        if (msg != null && msg.isNotEmpty && msg.toLowerCase() != 'internal') {
          return msg;
        }
        return 'Could not reset password. Check your code and try again.';
    }
  }

  static String authErrorMessage(FirebaseAuthException e) {
    return AuthService.passwordResetErrorMessage(e);
  }

  static String messageForGenericError(Object e) {
    if (e is ArgumentError) {
      return e.message?.toString() ?? 'Invalid input.';
    }
    final s = e.toString();
    if (s.contains('ArgumentError')) {
      return s.replaceFirst('ArgumentError: ', '');
    }
    return 'Could not complete password reset. Please try again.';
  }
}

/// Thrown when OTP completion is unavailable; email link was sent instead.
class PasswordResetNeedsEmailLinkException implements Exception {}

class PasswordResetOtpRequestResult {
  const PasswordResetOtpRequestResult({
    required this.email,
    required this.accountFound,
    required this.pushSent,
    required this.emailSent,
    this.smsSent = false,
    this.emailLinkSent = false,
  });

  final String email;
  final bool accountFound;
  final bool pushSent;
  final bool emailSent;
  final bool smsSent;
  final bool emailLinkSent;

  factory PasswordResetOtpRequestResult.fromMap(
    Map<String, dynamic> map, {
    required String email,
  }) {
    return PasswordResetOtpRequestResult(
      email: email,
      accountFound: map['accountFound'] == true,
      pushSent: map['pushSent'] == true,
      emailSent: map['emailSent'] == true,
      smsSent: map['smsSent'] == true,
    );
  }
}
