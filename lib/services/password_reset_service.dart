import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:atmos_trs_system/services/auth_service.dart';
import 'package:atmos_trs_system/services/push_notification_service.dart';
import 'package:atmos_trs_system/utils/email_utils.dart';
import 'package:atmos_trs_system/utils/qr_launch_query.dart';
import 'package:atmos_trs_system/utils/signup_field_validation.dart';

/// Password reset: OTP + push/SMS/email (Cloud Functions) with Firebase email-link fallback.
class PasswordResetService {
  PasswordResetService._();

  /// Must match Cloud Function `PASSWORD_RESET_OTP_MINUTES`.
  static const int otpExpiryMinutes = 5;

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  static const Duration _callableTimeout = Duration(seconds: 25);

  static bool _otpWasDelivered(PasswordResetOtpRequestResult parsed) {
    if (parsed.emailSent || parsed.smsSent) return true;
    // Push notifications are not available on web browsers.
    if (!kIsWeb && parsed.pushSent) return true;
    return false;
  }

  /// Emails a reset link that opens the ATMOS web app's own new-password form
  /// (Cloud Function `sendPasswordResetLinkEmail`). Falls back to Firebase's
  /// built-in reset email when the function is not deployed or cannot send.
  static Future<PasswordResetOtpRequestResult> requestEmailResetLink(
    String email,
  ) async {
    final normalized = normalizeEmail(email);
    if (!isValidEmailFormat(normalized)) {
      throw ArgumentError('Please enter a valid email address.');
    }
    try {
      final payload = <String, dynamic>{'email': normalized};
      if (kIsWeb) {
        payload['continueOrigin'] = Uri.base.origin;
      }
      final result = await _functions
          .httpsCallable('sendPasswordResetLinkEmail')
          .call<Map<String, dynamic>>(payload)
          .timeout(_callableTimeout);
      final data = Map<String, dynamic>.from(result.data);
      if (data['accountFound'] != true) {
        return PasswordResetOtpRequestResult(
          email: normalized,
          accountFound: false,
          pushSent: false,
          emailSent: false,
        );
      }
      if (data['emailSent'] == true) {
        return PasswordResetOtpRequestResult(
          email: normalized,
          accountFound: true,
          pushSent: false,
          emailSent: true,
          emailLinkSent: true,
        );
      }
      debugPrint('[PasswordReset] link email not delivered; using Firebase email.');
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[PasswordReset] link callable failed: ${e.code} ${e.message}');
      if (!_shouldUseEmailLinkFallbackOnRequest(e)) rethrow;
    } on TimeoutException catch (e) {
      debugPrint('[PasswordReset] link callable timeout: $e');
    }
    return _sendEmailLinkFallback(normalized);
  }

  /// `oobCode` when the web app was opened from a Firebase password-reset link.
  static String? emailResetOobCodeFromLaunchUrl() {
    if (!kIsWeb) return null;
    final params = mergedLaunchQueryParameters(Uri.base);
    if (params['mode']?.trim() != 'resetPassword') return null;
    final code = params['oobCode']?.trim();
    if (code == null || code.isEmpty) return null;
    return code;
  }

  /// Account email for a reset link; throws [FirebaseAuthException] if the
  /// link is expired, invalid, or already used.
  static Future<String> verifyEmailResetLink(String oobCode) async {
    try {
      return await AuthService.verifyPasswordResetCode(oobCode);
    } on FirebaseAuthException catch (e) {
      throw FirebaseAuthException(
        code: e.code,
        message: AuthService.passwordResetErrorMessage(e),
      );
    }
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
  ///
  /// On mobile, sends this device's FCM token so the Cloud Function can push the
  /// 6-digit code as a heads-up on **this** phone (not only Inbox/Spam).
  static Future<PasswordResetOtpRequestResult> requestOtp(String email) async {
    if (Firebase.apps.isEmpty) {
      throw StateError('Firebase is not available.');
    }
    final normalized = normalizeEmail(email);
    if (!isValidEmailFormat(normalized)) {
      throw ArgumentError('Please enter a valid email address.');
    }

    String? deviceFcmToken;
    if (!kIsWeb) {
      try {
        deviceFcmToken = await getDeviceFcmTokenForOtpDelivery();
      } catch (e, st) {
        debugPrint('[PasswordReset] device FCM token: $e\n$st');
      }
    }

    try {
      final callable = _functions.httpsCallable('requestPasswordResetOtp');
      final payload = <String, dynamic>{'email': normalized};
      if (deviceFcmToken != null && deviceFcmToken.isNotEmpty) {
        payload['fcmToken'] = deviceFcmToken;
      }
      final result = await callable
          .call<Map<String, dynamic>>(payload)
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
      // Anti-enumeration: same soft copy whether or not the email is registered.
      return 'If an account exists for ${maskEmailForDisplay(result.email)}, '
          'you will receive a 6-digit code by phone notification and email. '
          'Codes expire in $otpExpiryMinutes minutes.';
    }
    if (result.pushSent && result.emailSent && result.smsSent) {
      return 'Code sent! Check your phone notification first. '
          'SMS and email inbox are backups. Expires in $otpExpiryMinutes minutes.';
    }
    if (result.smsSent && result.emailSent) {
      return 'Code sent via SMS and email. Check your phone and Inbox. '
          'Expires in $otpExpiryMinutes minutes.';
    }
    if (result.pushSent && result.emailSent) {
      return 'Code sent! Check your phone notification first. '
          'A backup copy is in your email Inbox '
          '(Spam only if you do not see it there). '
          'Expires in $otpExpiryMinutes minutes.';
    }
    if (result.pushSent) {
      return 'Check your phone notification for the 6-digit code. '
          'Expires in $otpExpiryMinutes minutes.';
    }
    if (result.smsSent) {
      return 'Code sent via SMS to your registered mobile number. '
          'Expires in $otpExpiryMinutes minutes.';
    }
    if (result.emailSent) {
      return 'Code sent to your email Inbox. '
          'Open Inbox first — check Spam or Promotions only if it is missing. '
          'Expires in $otpExpiryMinutes minutes.';
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
