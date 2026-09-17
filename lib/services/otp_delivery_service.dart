import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:atmos_trs_system/services/emailjs_service.dart';
import 'package:atmos_trs_system/services/otp_service.dart';
import 'package:atmos_trs_system/services/push_notification_service.dart';

/// Delivers signup / resend OTP to the tourist's email inbox and registered mobile (SMS).
/// Does not flash the code on the signup device unless [notifyOnThisDevice] is true.
class OtpDeliveryService {
  OtpDeliveryService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  /// Normalizes PH mobiles to E.164 (+639XXXXXXXXX) for SMS APIs.
  static String? formatPhilippineMobile(String raw) {
    var cleaned = raw.replaceAll(RegExp(r'[^\d+]'), '').trim();
    if (cleaned.isEmpty) return null;
    if (cleaned.startsWith('09') && cleaned.length == 11) {
      return '+63${cleaned.substring(1)}';
    }
    if (cleaned.startsWith('639') && cleaned.length == 12) {
      return '+$cleaned';
    }
    if (cleaned.startsWith('+639') && cleaned.length == 13) {
      return cleaned;
    }
    if (cleaned.startsWith('9') && cleaned.length == 10) {
      return '+63$cleaned';
    }
    if (!cleaned.startsWith('+') && cleaned.length >= 10) {
      return '+$cleaned';
    }
    return cleaned.startsWith('+') ? cleaned : null;
  }

  /// Sends OTP email via client EmailJS first on web (browser Origin), then
  /// Cloud Function. Mobile prefers Cloud Function, then EmailJS fallback.
  /// Returns `null` on success, or an error message.
  static Future<String?> sendOtpToUserEmail({
    required String toEmail,
    required String toName,
    required String otp,
  }) async {
    final inboxEmail = toEmail.trim().toLowerCase();
    final authEmail =
        FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase() ?? '';
    // Always deliver to the contact/inbox address the tourist typed.
    final deliverTo = inboxEmail.isNotEmpty ? inboxEmail : authEmail;

    if (deliverTo.isEmpty) {
      return 'No email address to send the verification code to.';
    }

    Future<String?> tryEmailJs() => EmailjsService.sendOtpEmail(
          toEmail: deliverTo,
          toName: toName,
          otp: otp,
        );

    Future<String?> tryCloudFunction() async {
      if (Firebase.apps.isEmpty) {
        return 'Firebase not ready';
      }
      try {
        final callable = _functions.httpsCallable(
          'sendOtpEmail',
          options: HttpsCallableOptions(
            timeout: const Duration(seconds: 12),
          ),
        );
        final payload = <String, dynamic>{
          'toEmail': deliverTo,
          'toName': toName,
          'otp': otp,
        };
        if (authEmail.isNotEmpty && authEmail != deliverTo) {
          payload['inboxEmail'] = deliverTo;
        }
        await callable.call<void>(payload);
        debugPrint('[OTP] Email sent via Cloud Function to=$deliverTo');
        return null;
      } on FirebaseFunctionsException catch (e) {
        debugPrint(
          '[OTP] Cloud Function sendOtpEmail failed: ${e.code} ${e.message}',
        );
        return e.message ?? e.code;
      } catch (e, st) {
        debugPrint('[OTP] Cloud Function error: $e\n$st');
        return e.toString();
      }
    }

    if (kIsWeb) {
      // Web: EmailJS with Origin is the reliable path on Spark (no CF deploy).
      final emailJsErr = await tryEmailJs();
      if (emailJsErr == null) return null;
      debugPrint('[OTP] Web EmailJS failed: $emailJsErr — trying Cloud Function');
      final cfErr = await tryCloudFunction();
      if (cfErr == null) return null;
      return emailJsErr;
    }

    final cfErr = await tryCloudFunction();
    if (cfErr == null) return null;

    final emailJsErr = await tryEmailJs();
    if (emailJsErr == null) {
      debugPrint('[OTP] Email sent via client EmailJS to=$deliverTo');
    }
    return emailJsErr;
  }

  /// SMS to the tourist's own number (Cloud Function + Semaphore when configured).
  static Future<String?> sendOtpSms({
    required String mobile,
    required String otp,
  }) async {
    final e164 = formatPhilippineMobile(mobile);
    if (e164 == null) {
      return 'Invalid mobile number for SMS.';
    }
    if (Firebase.apps.isEmpty) {
      return 'SMS unavailable (Firebase not ready).';
    }
    try {
      final callable = _functions.httpsCallable('sendOtpSms');
      final result = await callable.call<Map<String, dynamic>>({
        'mobile': e164,
        'otp': otp,
      });
      final data = result.data;
      if (data['ok'] == true) {
        if (data['skipped'] == true) {
          debugPrint('[OTP] SMS skipped: ${data['reason']}');
          return 'sms_not_configured';
        }
        final status = data['status']?.toString() ?? '';
        debugPrint(
          '[OTP] SMS to $e164 status=$status network=${data['network']}',
        );
        if (status.toLowerCase() == 'failed' ||
            status.toLowerCase() == 'refunded') {
          return 'SMS $status — load Semaphore credits and approve sender name.';
        }
        return null;
      }
      return data['reason']?.toString() ?? 'Could not send SMS.';
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[OTP] sendOtpSms failed: ${e.code} ${e.message}');
      if (e.code == 'not-found' || e.code == 'unavailable') {
        return 'sms_not_configured';
      }
      return e.message ?? 'Could not send SMS.';
    } catch (e, st) {
      debugPrint('[OTP] sendOtpSms error: $e\n$st');
      return 'Could not send SMS.';
    }
  }

  /// After OTP is saved: email inbox and optionally SMS.
  /// [notifyOnThisDevice] should stay false during signup so a shared phone
  /// does not show another person's code.
  /// Set [otpAlreadyInFirestore] true when signup already stored the code.
  static Future<OtpDeliveryResult> deliverVerificationCode({
    required String uid,
    required String email,
    required String displayName,
    required String otp,
    String? mobile,
    bool notifyOnThisDevice = false,
    bool trySms = false,
    bool otpAlreadyInFirestore = false,
  }) async {
    if (notifyOnThisDevice && !kIsWeb) {
      await ensureEmailOtpNotificationSupport();
    }

    final emailErr = await sendOtpToUserEmail(
      toEmail: email,
      toName: displayName,
      otp: otp,
    );

    String? smsResult;
    final mobileRaw = mobile?.trim() ?? '';
    if (trySms && mobileRaw.isNotEmpty) {
      smsResult = await sendOtpSms(mobile: mobileRaw, otp: otp);
    }

    var notificationShown = false;
    if (notifyOnThisDevice && !kIsWeb) {
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
      smsSent: trySms && smsResult == null && mobileRaw.isNotEmpty,
      smsSkippedNotConfigured: smsResult == 'sms_not_configured',
      smsError:
          trySms &&
              smsResult != null &&
              smsResult != 'sms_not_configured' &&
              mobileRaw.isNotEmpty
          ? smsResult
          : null,
      notificationShown: notificationShown,
      // Reveal code in-app when inbox delivery failed (OTP is already stored).
      otpForDisplay: emailErr != null ? otp : (kDebugMode ? otp : null),
      maskedMobile: mobileRaw.isNotEmpty
          ? _maskMobile(formatPhilippineMobile(mobileRaw) ?? mobileRaw)
          : null,
      otpAlreadyInFirestore: otpAlreadyInFirestore,
    );
  }

  static String _maskMobile(String e164) {
    final digits = e164.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 4) return e164;
    final tail = digits.substring(digits.length - 4);
    return '*** *** $tail';
  }
}

class OtpDeliveryResult {
  const OtpDeliveryResult({
    required this.emailSent,
    this.emailError,
    this.smsSent = false,
    this.smsSkippedNotConfigured = false,
    this.smsError,
    this.maskedMobile,
    this.notificationShown = false,
    this.otpForDisplay,
    this.otpAlreadyInFirestore = false,
  });

  final bool emailSent;
  final String? emailError;
  final bool smsSent;
  final bool smsSkippedNotConfigured;
  final String? smsError;
  final String? maskedMobile;
  final bool notificationShown;
  /// 6-digit code for in-app display when email could not be delivered.
  final String? otpForDisplay;
  final bool otpAlreadyInFirestore;

  /// Signup can continue when email arrived, or OTP is already stored (Resend on next screen).
  bool get canCompleteRegistration =>
      emailSent || otpAlreadyInFirestore || smsSent || notificationShown;

  String messageForUser(String email) {
    if (otpAlreadyInFirestore && !emailSent) {
      if (otpForDisplay != null && otpForDisplay!.length == 6) {
        return 'Email could not be delivered to $email. '
            'Use this code now: $otpForDisplay '
            '(also try Resend after EmailJS Template ID is fixed).';
      }
      return 'Could not email $email right now. Continue to enter your code — '
          'use Resend on the next screen if you did not receive it.';
    }
    if (smsError != null && smsError!.isNotEmpty) {
      return 'Email: ${emailSent ? "sent" : "failed"}. SMS failed: $smsError';
    }
    if (smsSent && maskedMobile != null) {
      if (emailSent) {
        return 'Code sent to $email and SMS to $maskedMobile. '
            'Check your own phone for the text message.';
      }
      return 'Code sent via SMS to $maskedMobile. '
          'Also check $email on the phone where that email is signed in.';
    }
    if (emailSent) {
      if (smsSkippedNotConfigured && maskedMobile != null) {
        return 'Code sent to $email. On your own phone, open the mail app '
            'where you read $email (not necessarily this device).';
      }
      if (notificationShown) {
        return 'Verification code sent to $email and shown in your phone '
            'notification. Also check your email inbox (not Spam).';
      }
      return 'Code sent to $email. Open your mail app and check the inbox '
          '(not Spam) on the phone where that email is signed in.';
    }
    if (smsSent && maskedMobile != null) {
      return 'Code sent via SMS to $maskedMobile.';
    }
    if (otpForDisplay != null && otpForDisplay!.length == 6) {
      return 'Email could not be sent. Your code is $otpForDisplay '
          '(expires in ${OtpService.otpExpiryMinutes} min).';
    }
    if (kIsWeb) {
      return 'Could not send email. Please check your EmailJS Template ID, then tap Resend.';
    }
    return 'Could not send the code. Check your email address and tap Resend.';
  }
}
