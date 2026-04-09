import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:atmos_trs_system/config/emailjs_config.dart';
import 'package:http/http.dart' as http;

/// Sends transactional email via [EmailJS](https://www.emailjs.com/) REST API.
///
/// **Endpoint:** `POST https://api.emailjs.com/api/v1.0/email/send`
/// **JSON body:** `service_id`, `template_id`, `user_id` (your **public** key), `template_params`.
///
/// Template params must match your EmailJS template variables exactly
/// (e.g. `to_email`, `to_name`, `otp`, `name`).
class EmailjsService {
  EmailjsService._();

  static String _formatEmailJsErrorBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return '(empty response)';
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map && decoded['text'] != null) {
        return decoded['text'].toString();
      }
    } catch (_) {}
    return trimmed;
  }

  /// Sends the ATMOS-TRS OTP email using configured service + template.
  ///
  /// Returns `null` on success, or an error message string on failure.
  static Future<String?> sendOtpEmail({
    required String toEmail,
    required String toName,
    required String otp,
  }) async {
    if (EmailjsConfig.templateId == 'REPLACE_WITH_TEMPLATE_ID_FROM_EMAILJS' ||
        EmailjsConfig.templateId.isEmpty) {
      return 'EmailJS template ID is not set. Edit lib/config/emailjs_config.dart '
          'and set EmailjsConfig.templateId to your template ID from the EmailJS dashboard.';
    }

    final serviceId = EmailjsConfig.serviceId.trim();
    final templateId = EmailjsConfig.templateId.trim();
    final userId = EmailjsConfig.publicKey.trim();

    if (serviceId.isEmpty) {
      return 'EmailJS service ID is empty. Set EmailjsConfig.serviceId in '
          'lib/config/emailjs_config.dart (Email Services → Service ID).';
    }

    debugPrint('[EmailJS] sendUrl=${EmailjsConfig.sendUrl}');
    debugPrint('[EmailJS] serviceId=$serviceId');
    debugPrint('[EmailJS] templateId=$templateId');
    debugPrint('[EmailJS] user_id (PUBLIC key only, never private)=$userId');

    if (userId.isEmpty) {
      return 'EmailJS public key is empty. Set EmailjsConfig.publicKey in '
          'lib/config/emailjs_config.dart (Account → API keys → Public Key).';
    }

    // Include common aliases so templates using {{email}} / {{user_email}} work.
    final templateParams = <String, String>{
      'to_email': toEmail,
      'to_name': toName,
      'otp': otp,
      'name': toName,
      'email': toEmail,
      'user_email': toEmail,
    };

    String? accessForPayload() {
      final fromEnv = EmailjsConfig.accessTokenFromEnvironment.trim();
      if (fromEnv.isNotEmpty) return fromEnv;
      return EmailjsConfig.privateAccessToken.trim().isEmpty
          ? null
          : EmailjsConfig.privateAccessToken.trim();
    }

    Future<http.Response> postSend(Map<String, dynamic> payload) {
      debugPrint('[EmailJS] POST body keys: ${payload.keys.join(", ")}');
      return http.post(
        Uri.parse(EmailjsConfig.sendUrl),
        headers: const {
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: jsonEncode(payload),
      );
    }

    Map<String, dynamic> buildPayload({String? accessToken}) {
      final p = <String, dynamic>{
        'service_id': serviceId,
        'template_id': templateId,
        'user_id': userId,
        'template_params': templateParams,
      };
      if (accessToken != null && accessToken.isNotEmpty) {
        p['accessToken'] = accessToken;
      }
      return p;
    }

    try {
      final access = accessForPayload();
      if (access != null) {
        debugPrint(
          '[EmailJS] accessToken set (length=${access.length})',
        );
      } else {
        debugPrint(
          '[EmailJS] no accessToken — if you get 404 Account not found, add '
          'EmailjsConfig.privateAccessToken in emailjs_config.dart or '
          '--dart-define=EMAILJS_ACCESS_TOKEN=...',
        );
      }

      final response = await postSend(buildPayload(accessToken: access));

      debugPrint('[EmailJS] response.statusCode=${response.statusCode}');
      debugPrint('[EmailJS] response.body=${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint(
          '[EmailJS] SEND_OK statusCode=${response.statusCode} '
          'body=${response.body}',
        );
        return null;
      }

      debugPrint(
        '[EmailJS] SEND_FAIL statusCode=${response.statusCode} '
        'body=${response.body}',
      );
      return 'EmailJS error (${response.statusCode}): '
          '${_formatEmailJsErrorBody(response.body)}';
    } on TimeoutException catch (e, st) {
      debugPrint('[EmailJS] timeout: $e\n$st');
      return 'Email request timed out. Check your connection and try again.';
    } catch (e, st) {
      debugPrint('[EmailJS] request failed: $e\n$st');
      return 'Network error sending email: $e';
    }
  }
}
