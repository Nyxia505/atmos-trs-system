import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:atmos_trs_system/services/emailjs_service.dart';
import 'package:atmos_trs_system/services/push_notification_service.dart';

/// Delivers signup / resend OTP to the user's email inbox, with mobile notification backup.
class OtpDeliveryService {
  OtpDeliveryService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  /// Sends OTP email via Cloud Function (preferred), then client EmailJS fallback.
  /// Returns `null` on success, or an error message.
  static Future<String?> sendOtpToUserEmail({
    required String toEmail,
    required String toName,
    required String otp,
  }) async {
    if (Firebase.apps.isNotEmpty) {
      try {
        final callable = _functions.httpsCallable('sendOtpEmail');
        await callable.call<void>({
          'toEmail': toEmail,
          'toName': toName,
          'otp': otp,
        });
        debugPrint('[OTP] Email sent via Cloud Function');
        return null;
      } on FirebaseFunctionsException catch (e) {
        debugPrint(
          '[OTP] Cloud Function sendOtpEmail failed: ${e.code} ${e.message}',
        );
        if (e.code == 'internal' && (e.message ?? '').contains('EmailJS')) {
          // Fall through to client EmailJS.
        } else if (e.code != 'not-found' && e.code != 'unavailable') {
          return e.message ?? 'Could not send verification email.';
        }
      } catch (e, st) {
        debugPrint('[OTP] Cloud Function error: $e\n$st');
      }
    }

    return EmailjsService.sendOtpEmail(
      toEmail: toEmail,
      toName: toName,
      otp: otp,
    );
  }

  /// After OTP is saved in Firestore: email to inbox + on-device notification (mobile).
  static Future<OtpDeliveryResult> deliverVerificationCode({
    required String uid,
    required String email,
    required String displayName,
    required String otp,
  }) async {
    if (!kIsWeb) {
      await ensureEmailOtpNotificationSupport();
    }

    final emailErr = await sendOtpToUserEmail(
      toEmail: email,
      toName: displayName,
      otp: otp,
    );

    var notificationShown = false;
    if (!kIsWeb) {
      await deliverEmailOtpToDevice(
        uid: uid,
        otp: otp,
        displayName: displayName,
      );
      notificationShown = true;
    }

    return OtpDeliveryResult(
      emailSent: emailErr == null,
      emailError: emailErr,
      notificationShown: notificationShown,
      otpForDebugOnly: kDebugMode ? otp : null,
    );
  }
}

class OtpDeliveryResult {
  const OtpDeliveryResult({
    required this.emailSent,
    this.emailError,
    this.notificationShown = false,
    this.otpForDebugOnly,
  });

  final bool emailSent;
  final String? emailError;
  final bool notificationShown;
  final String? otpForDebugOnly;

  String messageForUser(String email) {
    if (emailSent) {
      if (notificationShown) {
        return 'Verification code sent to $email. Check your mail app and phone notification.';
      }
      return 'Verification code sent to $email. Open Gmail or your mail app on your phone.';
    }
    if (notificationShown) {
      return 'Check your phone notification for the 6-digit code. '
          'Email could not be sent — tap Resend code to try again.';
    }
    if (kDebugMode && otpForDebugOnly != null) {
      return 'Email could not be sent. Dev code: $otpForDebugOnly (expires in 5 min).';
    }
    if (kIsWeb) {
      return 'Could not send email. On this screen, tap "Show code on this device" '
          'or Resend code to try again.';
    }
    return 'Could not send email. Tap Resend code on this screen to try again.';
  }
}
