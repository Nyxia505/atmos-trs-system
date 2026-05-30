import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:atmos_trs_system/services/auth_service.dart';
import 'package:atmos_trs_system/utils/email_utils.dart';

/// Password reset: OTP + push (Cloud Functions) with Firebase email-link fallback.
class PasswordResetService {
  PasswordResetService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  static const Duration _callableTimeout = Duration(seconds: 25);

  /// Step 1: prefer OTP via Cloud Functions; falls back to Firebase reset email if
  /// functions are not deployed or return `internal`.
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

      // Functions ran but could not deliver OTP — try inbox reset link.
      if (parsed.accountFound && !parsed.pushSent && !parsed.emailSent) {
        debugPrint('[PasswordReset] OTP not delivered; trying email link fallback.');
        return _sendEmailLinkFallback(normalized);
      }
      return parsed;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[PasswordReset] callable failed: ${e.code} ${e.message}');
      if (_shouldUseEmailLinkFallback(e)) {
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
    final digits = otp.replaceAll(RegExp(r'\D'), '');
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
      if (_shouldUseEmailLinkFallback(e)) {
        await _sendEmailLinkFallback(normalized);
        throw PasswordResetNeedsEmailLinkException();
      }
      rethrow;
    } on TimeoutException {
      await _sendEmailLinkFallback(normalized);
      throw PasswordResetNeedsEmailLinkException();
    }
  }

  static bool _shouldUseEmailLinkFallback(FirebaseFunctionsException e) {
    const codes = {
      'internal',
      'not-found',
      'unavailable',
      'unknown',
      'failed-precondition',
      'deadline-exceeded',
    };
    if (codes.contains(e.code)) return true;
    final msg = e.message?.toLowerCase() ?? '';
    return msg == 'internal' || msg.contains('not found');
  }

  static bool _looksLikeFunctionsUnavailable(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('internal') ||
        s.contains('not-found') ||
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
          'you will get a 6-digit code on your phone or inbox.';
    }
    if (result.pushSent && result.emailSent) {
      return 'Code sent! Check your phone notification first, then your email inbox.';
    }
    if (result.pushSent) {
      return 'Check your phone notification for the 6-digit code. '
          'No need to open Gmail.';
    }
    if (result.emailSent) {
      return 'Code sent to your inbox. Open your mail app if you do not see a notification.';
    }
    return 'Could not deliver the code. Install ATMOS on your phone and allow notifications, '
        'then tap Resend code.';
  }

  static String errorMessage(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'internal':
        return 'Reset service is not ready yet. We sent a password reset link to your email instead — check your inbox.';
      case 'resource-exhausted':
        return e.message ?? 'Please wait before requesting another code.';
      case 'invalid-argument':
        return e.message ?? 'Invalid code or password.';
      case 'deadline-exceeded':
        return e.message ?? 'This code has expired. Request a new one.';
      case 'not-found':
        return e.message ?? 'Invalid email or code.';
      case 'unavailable':
        return 'Reset service is busy. Check your email for a reset link or try again.';
      default:
        final msg = e.message?.trim();
        if (msg != null && msg.isNotEmpty && msg.toLowerCase() != 'internal') {
          return msg;
        }
        return 'Could not send reset code. Check your email for a reset link or try again.';
    }
  }

  static String authErrorMessage(FirebaseAuthException e) {
    return AuthService.passwordResetErrorMessage(e);
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
    this.emailLinkSent = false,
  });

  final String email;
  final bool accountFound;
  final bool pushSent;
  final bool emailSent;

  /// Firebase password-reset email (used when Cloud Functions are not deployed).
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
    );
  }
}
