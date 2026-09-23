import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:atmos_trs_system/config/emailjs_config.dart';
import 'package:http/http.dart' as http;

/// Sends transactional email via [EmailJS](https://www.emailjs.com/) REST API.
///
/// **Endpoint:** `POST https://api.emailjs.com/api/v1.0/email/send`
/// **JSON body:** `service_id`, `template_id`, `user_id` (public key),
/// `accessToken` (private key — required when "Use Private Key" is on),
/// `template_params`.
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
      return 'EmailJS template ID is wrong or missing. In EmailJS → Email Templates, '
          'copy the Template ID (template_xxxxxxx) into lib/config/emailjs_config.dart.';
    }
    if (lower.contains('private key') || lower.contains('strict mode')) {
      return 'EmailJS private key rejected. Re-copy Private Key from Account → API keys '
          'into emailjs_config.dart, and keep "Use Private Key" + non-browser API enabled.';
    }
    if (lower.contains('service') && lower.contains('not found')) {
      return 'EmailJS service ID not found. Check Email Services → service_l6fdttb.';
    }
    return 'EmailJS error ($status): ${_formatEmailJsErrorBody(body)}';
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
    debugPrint('[EmailJS] user_id (PUBLIC key only)=$userId');

    if (userId.isEmpty) {
      return 'EmailJS public key is empty. Set EmailjsConfig.publicKey in '
          'lib/config/emailjs_config.dart (Account → API keys → Public Key).';
    }

    // Soft transactional copy — avoid ALL-CAPS / “URGENT” / link bait (spam triggers).
    // Inbox vs Spam still depends on EmailJS From-domain SPF/DKIM (see EmailjsConfig).
    final subject = 'Your ATMOS-TRS verification code';
    final message =
        'Hi $toName,\n\n'
        'Here is your ATMOS-TRS verification code:\n\n'
        '$otp\n\n'
        'Enter this code in the app. It expires in 5 minutes.\n\n'
        'If you did not request this, you can ignore this email.\n\n'
        'Thanks,\n'
        'ATMOS-TRS Tourism';
    final templateParams = <String, String>{
      'to_email': toEmail,
      'to_name': toName,
      'otp': otp,
      'name': toName,
      'email': toEmail,
      'user_email': toEmail,
      'subject': subject,
      'from_name': 'ATMOS-TRS Tourism',
      'reply_to': 'atmostrs@gmail.com',
      'message': message,
      'message_html':
          '<p>Hi ${toName.replaceAll('<', '').replaceAll('>', '')},</p>'
          '<p>Here is your ATMOS-TRS verification code:</p>'
          '<p style="font-size:28px;font-weight:700;letter-spacing:6px;'
          'font-family:monospace;">$otp</p>'
          '<p>Enter this code in the app. It expires in 5 minutes.</p>'
          '<p style="color:#666;font-size:13px;">If you did not request this, '
          'you can ignore this email.</p>'
          '<p>Thanks,<br/>ATMOS-TRS Tourism</p>',
      'preheader': 'Your ATMOS-TRS code · expires in 5 minutes',
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
      // Origin helps EmailJS accept browser-like clients; required for some
      // free-plan / domain setups. Flutter mobile still needs accessToken.
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
      if (access != null) {
        debugPrint('[EmailJS] accessToken set (length=${access.length})');
      } else {
        debugPrint(
          '[EmailJS] no accessToken — enable Private Key in EmailJS Security '
          'or set EmailjsConfig.privateAccessToken',
        );
      }

      // Prefer private key when configured (strict mode). Retry without if
      // the account rejects the token field on browser Origin requests.
      http.Response response = await postSend(buildPayload(accessToken: access))
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 403 &&
          access != null &&
          response.body.toLowerCase().contains('private key')) {
        debugPrint('[EmailJS] retrying without accessToken (Origin mode)');
        response = await postSend(buildPayload())
            .timeout(const Duration(seconds: 12));
      }

      debugPrint('[EmailJS] response.statusCode=${response.statusCode}');
      debugPrint('[EmailJS] response.body=${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('[EmailJS] SEND_OK to=$toEmail');
        return null;
      }

      return _friendlyError(response.statusCode, response.body);
    } on TimeoutException catch (e, st) {
      debugPrint('[EmailJS] timeout: $e\n$st');
      return 'Email request timed out. Check your connection and try again.';
    } catch (e, st) {
      debugPrint('[EmailJS] request failed: $e\n$st');
      return 'Network error sending email: $e';
    }
  }
}
