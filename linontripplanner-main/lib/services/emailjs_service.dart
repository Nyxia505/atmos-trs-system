import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;

import '../config/emailjs_config.dart';

/// Sends OTP email via EmailJS REST API (same service as ATMOS TRS).
class EmailjsService {
  EmailjsService._();

  static const String _webOrigin = 'https://atmos-trs-system.web.app';

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

  static String? _friendlyError(int status, String body) {
    final lower = body.toLowerCase();
    if (lower.contains('template id not found') ||
        lower.contains('template_id')) {
      return 'EmailJS template ID is wrong or missing.';
    }
    if (lower.contains('private key') || lower.contains('strict mode')) {
      return 'EmailJS private key rejected. Check EmailJS Security settings.';
    }
    if (lower.contains('service') && lower.contains('not found')) {
      return 'EmailJS service ID not found.';
    }
    return 'EmailJS error ($status): ${_formatEmailJsErrorBody(body)}';
  }

  /// Returns `null` on success, or an error message on failure.
  static Future<String?> sendOtpEmail({
    required String toEmail,
    required String toName,
    required String otp,
  }) async {
    final serviceId = EmailjsConfig.serviceId.trim();
    final templateId = EmailjsConfig.templateId.trim();
    final userId = EmailjsConfig.publicKey.trim();

    if (serviceId.isEmpty || templateId.isEmpty || userId.isEmpty) {
      return 'EmailJS is not configured.';
    }

    final subject = 'Complete your Trip Planner registration';
    final safeName = toName.replaceAll('<', '').replaceAll('>', '');
    final message =
        'Hi $safeName,\n\n'
        'Thanks for registering with Misamis Occidental Trip Planner. '
        'Use this one-time number to finish signup:\n\n'
        '$otp\n\n'
        'Enter it in the app within 5 minutes.\n\n'
        'If you did not start this, you can ignore this message.\n\n'
        'Regards,\n'
        'Misamis Occidental Tourism';
    final templateParams = <String, String>{
      'to_email': toEmail,
      'to_name': toName,
      'otp': otp,
      'name': toName,
      'email': toEmail,
      'user_email': toEmail,
      'subject': subject,
      'from_name': 'Misamis Occidental Tourism',
      'reply_to': 'atmostrs@gmail.com',
      'message': message,
      'message_html':
          '<div style="font-family:Arial,Helvetica,sans-serif;font-size:15px;'
          'color:#222;line-height:1.5;">'
          '<p>Hi $safeName,</p>'
          '<p>Thanks for registering with Misamis Occidental Trip Planner. '
          'Use this one-time number to finish signup:</p>'
          '<p style="font-size:26px;font-weight:700;letter-spacing:4px;'
          'font-family:Consolas,monospace;margin:18px 0;">$otp</p>'
          '<p>Enter it in the app within 5 minutes.</p>'
          '<p style="color:#666;font-size:13px;">If you did not start this, '
          'you can ignore this message.</p>'
          '<p>Regards,<br/>Misamis Occidental Tourism</p>'
          '</div>',
      'preheader': 'Finish your registration in the app within 5 minutes.',
    };

    String? accessForPayload() {
      final fromEnv = EmailjsConfig.accessTokenFromEnvironment.trim();
      if (fromEnv.isNotEmpty) return fromEnv;
      return EmailjsConfig.privateAccessToken.trim().isEmpty
          ? null
          : EmailjsConfig.privateAccessToken.trim();
    }

    Future<http.Response> postSend(Map<String, dynamic> payload) {
      return http.post(
        Uri.parse(EmailjsConfig.sendUrl),
        headers: {
          'Content-Type': 'application/json; charset=UTF-8',
          'Accept': 'application/json',
          'Origin': _webOrigin,
          'Referer': '$_webOrigin/',
          if (!kIsWeb)
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
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
      http.Response response = await postSend(buildPayload(accessToken: access))
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 403 &&
          access != null &&
          response.body.toLowerCase().contains('private key')) {
        response =
            await postSend(buildPayload()).timeout(const Duration(seconds: 12));
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('[EmailJS] SEND_OK to=$toEmail');
        return null;
      }
      return _friendlyError(response.statusCode, response.body);
    } on TimeoutException {
      return 'Email request timed out. Check your connection and try again.';
    } catch (e) {
      debugPrint('[EmailJS] request failed: $e');
      return 'Network error sending email: $e';
    }
  }
}
