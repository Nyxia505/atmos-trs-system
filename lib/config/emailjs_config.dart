/// Centralized EmailJS configuration for OTP emails.
///
/// **Setup:** In [EmailJS Dashboard](https://dashboard.emailjs.com):
/// 1. **Email Services** → copy **Service ID** (Gmail integration).
/// 2. **Email Templates** → open your OTP template → copy **Template ID**.
/// 3. **Account → General** → copy **Public Key** (safe for client apps).
///
/// **403 "non-browser environments":** In EmailJS go to
/// **Account → Security** and enable **Allow email sending from non-browser
/// applications** (or use the REST `accessToken` private key as below).
///
/// **404 "Account not found":** update [publicKey] and [serviceId] from EmailJS dashboard.
class EmailjsConfig {
  EmailjsConfig._();

  /// Gmail service ID from EmailJS → Email Services.
  static const String serviceId = String.fromEnvironment(
    'EMAILJS_SERVICE_ID',
    defaultValue: 'service_au0q98k',
  );

  /// Template ID from EmailJS → Email Templates (OTP: subject e.g. "ATMOS-TRS OTP code").
  /// Body placeholders: `{{to_name}}`, `{{otp}}`, `{{to_email}}` for the To field.
  static const String templateId = String.fromEnvironment(
    'EMAILJS_TEMPLATE_ID',
    defaultValue: 'template_fk8jzbr',
  );

  /// Public Key from EmailJS → Account → API keys (client-side send only).
  static const String publicKey = String.fromEnvironment(
    'EMAILJS_PUBLIC_KEY',
    defaultValue: '8JZA_nboZm39-Rihv',
  );

  /// EmailJS REST endpoint (v1).
  static const String sendUrl = 'https://api.emailjs.com/api/v1.0/email/send';

  /// Optional private key for REST `accessToken` (only if your EmailJS account
  /// requires it). **Do not hardcode.** Use build flag instead:
  /// `flutter run -d chrome --dart-define=EMAILJS_ACCESS_TOKEN=your_private_key`
  static String get accessTokenFromEnvironment =>
      const String.fromEnvironment('EMAILJS_ACCESS_TOKEN', defaultValue: '');

  /// **Dev/local only:** paste your EmailJS **Private Key** (Account → API keys)
  /// if sends return `404 Account not found` with [publicKey] alone. Leaving this
  /// empty is recommended; use [accessTokenFromEnvironment] for CI/production.
  /// Never commit a real value to a public repository.
  static const String privateAccessToken = String.fromEnvironment(
    'EMAILJS_ACCESS_TOKEN',
    defaultValue: 'axQ3F4ykxyBz1GTozodYe',
  );
}
