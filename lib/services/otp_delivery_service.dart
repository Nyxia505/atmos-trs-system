import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:atmos_trs_system/services/emailjs_service.dart';
import 'package:atmos_trs_system/services/push_notification_service.dart';

/// Delivers signup / resend OTP primarily to the user's email Inbox.
///
/// [notifyOnThisDevice] defaults to false — signup/verify require opening email
/// for the code. Local heads-up is opt-in only.
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

    // Prefer EmailJS for verification mail. Cloud Function sendOtpEmail is
    // inbox-only (must never FCM-push OTP — that leaked to stale fcmTokens).
    final emailJsErr = await tryEmailJs();
    if (emailJsErr == null) {
      debugPrint('[OTP] Email sent via client EmailJS to=$deliverTo');
      return null;
    }
    debugPrint('[OTP] EmailJS failed: $emailJsErr — trying Cloud Function');
    final cfErr = await tryCloudFunction();
    if (cfErr == null) return null;
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

  /// After OTP is saved: email inbox (primary) + optional SMS.
  ///
  /// [notifyOnThisDevice] defaults to **false** for signup / verify — users open
  /// their email Inbox for the code (no on-device OTP heads-up).
  /// Set [otpAlreadyInFirestore] true when signup already stored the code.
  ///
  /// When [emailInBackground] is true, returns quickly and fires the inbox email
  /// without blocking navigation to verify-otp.
  static Future<OtpDeliveryResult> deliverVerificationCode({
    required String uid,
    required String email,
    required String displayName,
    required String otp,
    String? mobile,
    bool notifyOnThisDevice = false,
    bool trySms = false,
    bool otpAlreadyInFirestore = false,
    bool emailInBackground = false,
  }) async {
    // Prepare notification channel only when explicitly requested.
    if (notifyOnThisDevice && !kIsWeb) {
      await ensureEmailOtpNotificationSupport();
    }

    // On-device notify is opt-in only (signup uses email Inbox instead).
    var notificationShown = false;
    if (notifyOnThisDevice && !kIsWeb) {
      try {
        notificationShown = await deliverEmailOtpToDevice(
          uid: uid,
          otp: otp,
          displayName: displayName,
        ).timeout(const Duration(seconds: 4));
      } catch (e, st) {
        debugPrint('[OTP] on-device notify failed: $e\n$st');
        notificationShown = false;
      }
    }

    if (emailInBackground) {
      unawaited(() async {
        final err = await sendOtpToUserEmail(
          toEmail: email,
          toName: displayName,
          otp: otp,
        );
        if (err != null) {
          debugPrint('[OTP] background email failed: $err');
        } else {
          debugPrint('[OTP] background email sent to $email');
        }
      }());
      return OtpDeliveryResult(
        emailSent: false,
        emailError: null,
        notificationShown: notificationShown,
        // Never surface the code on-screen for signup — user must open email.
        otpForDisplay: null,
        otpAlreadyInFirestore: otpAlreadyInFirestore,
      );
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
      // Do not put the OTP on the verify screen — Inbox only.
      otpForDisplay: null,
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

  /// Hard failure only when no OTP was stored and delivery fully failed.
  static String emailDoesNotExistMessage(String email) {
    final shown = email.trim().isEmpty ? 'this email' : email.trim();
    return 'Sorry, $shown does not exist or could not receive our verification '
        'code. Please use Edit details and enter a real, working email address.';
  }

  /// Soft warning when OTP is saved but email delivery was not confirmed.
  static String deliveryUnconfirmedMessage(String email) {
    final shown = email.trim().isEmpty ? 'your email' : email.trim();
    return 'We couldn\'t confirm email delivery to $shown. Check Inbox/Spam, '
        'or tap Resend if the code doesn\'t arrive.';
  }

  String messageForUser(String email) {
    if (smsError != null && smsError!.isNotEmpty) {
      return 'Email: ${emailSent ? "sent" : "failed"}. SMS failed: $smsError';
    }
    if (smsSent && maskedMobile != null) {
      if (emailSent || notificationShown) {
        return 'Code sent by SMS to $maskedMobile'
            '${emailSent ? ". A copy was also sent to $email — open your Inbox." : ""}.';
      }
      return 'Code sent via SMS to $maskedMobile.';
    }
    if (notificationShown && emailSent) {
      return 'Code sent to $email. Open your email Inbox and enter it in the app '
          '(Spam only if you do not see it).';
    }
    if (notificationShown) {
      return 'Open your email Inbox for the verification code, then enter it here.';
    }
    if (emailSent) {
      return 'Code sent to $email. Open your email Inbox and enter the 6-digit code '
          '(check Spam only if it is missing).';
    }
    // OTP stored (or recoverable) but email not confirmed — soft warning, not "does not exist".
    if (otpAlreadyInFirestore || canCompleteRegistration) {
      return OtpDeliveryResult.deliveryUnconfirmedMessage(email);
    }
    if (smsSent && maskedMobile != null) {
      return 'Code sent via SMS to $maskedMobile.';
    }
    return OtpDeliveryResult.emailDoesNotExistMessage(email);
  }
}
