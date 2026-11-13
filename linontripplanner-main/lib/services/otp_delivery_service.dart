import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'emailjs_service.dart';

/// Delivers signup OTP to email Inbox (Cloud Function SMTP-first → EmailJS).
class OtpDeliveryService {
  OtpDeliveryService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  static Future<String?> sendOtpToUserEmail({
    required String toEmail,
    required String toName,
    required String otp,
  }) async {
    final inboxEmail = toEmail.trim().toLowerCase();
    if (inboxEmail.isEmpty) {
      return 'No email address to send the verification code to.';
    }

    Future<String?> tryEmailJs() => EmailjsService.sendOtpEmail(
          toEmail: inboxEmail,
          toName: toName,
          otp: otp,
        );

    Future<String?> tryCloudFunction() async {
      if (Firebase.apps.isEmpty) {
        return 'Firebase not ready';
      }
      final signedIn = FirebaseAuth.instance.currentUser != null;
      final fnName = signedIn ? 'sendOtpEmail' : 'sendSignupOtpEmail';
      try {
        final callable = _functions.httpsCallable(
          fnName,
          options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
        );
        await callable.call<void>({
          'toEmail': inboxEmail,
          'toName': toName,
          'otp': otp,
          'purpose': 'trip_planner',
        });
        debugPrint('[OTP] Email sent via Cloud Function $fnName to=$inboxEmail');
        return null;
      } on FirebaseFunctionsException catch (e) {
        debugPrint('[OTP] $fnName failed: ${e.code} ${e.message}');
        return e.message ?? e.code;
      } catch (e) {
        debugPrint('[OTP] Cloud Function error: $e');
        return e.toString();
      }
    }

    // Prefer server SMTP (inbox). Client EmailJS often lands in Spam.
    final cfErr = await tryCloudFunction();
    if (cfErr == null) return null;
    debugPrint('[OTP] Cloud Function failed: $cfErr — trying client EmailJS');
    final emailJsErr = await tryEmailJs();
    if (emailJsErr == null) {
      debugPrint('[OTP] Email sent via EmailJS to=$inboxEmail');
      return null;
    }
    return cfErr;
  }

  static Future<OtpDeliveryResult> deliverVerificationCode({
    required String email,
    required String displayName,
    required String otp,
    bool emailInBackground = false,
  }) async {
    if (emailInBackground) {
      unawaited(() async {
        final err = await sendOtpToUserEmail(
          toEmail: email,
          toName: displayName,
          otp: otp,
        );
        if (err != null) {
          debugPrint('[OTP] background email failed: $err');
        }
      }());
      return const OtpDeliveryResult(
        emailSent: false,
        emailDeliveryPending: true,
        otpAlreadyStored: true,
      );
    }

    final emailErr = await sendOtpToUserEmail(
      toEmail: email,
      toName: displayName,
      otp: otp,
    );
    return OtpDeliveryResult(
      emailSent: emailErr == null,
      emailError: emailErr,
      otpAlreadyStored: true,
    );
  }
}

class OtpDeliveryResult {
  const OtpDeliveryResult({
    required this.emailSent,
    this.emailError,
    this.emailDeliveryPending = false,
    this.otpAlreadyStored = false,
  });

  final bool emailSent;
  final String? emailError;
  final bool emailDeliveryPending;
  final bool otpAlreadyStored;

  bool get canContinue =>
      emailSent || emailDeliveryPending || otpAlreadyStored;

  static String deliveryPendingMessage(String email) {
    final shown = email.trim().isEmpty ? 'your email' : email.trim();
    return 'We are sending a 6-digit code to $shown. Open your Inbox '
        '(not Spam) and enter it below.';
  }

  String messageForUser(String email) {
    if (emailSent) {
      return 'Code sent to $email. Open your Inbox (not Spam) and enter the 6-digit code.';
    }
    if (emailDeliveryPending) {
      return deliveryPendingMessage(email);
    }
    return 'We couldn\'t confirm email delivery to $email. Check Inbox first, '
        'then Spam, or tap Resend.';
  }
}
