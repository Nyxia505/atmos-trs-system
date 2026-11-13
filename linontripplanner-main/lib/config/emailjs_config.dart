/// EmailJS config shared with ATMOS TRS OTP delivery (same Firebase / inbox).
class EmailjsConfig {
  EmailjsConfig._();

  static const String serviceId = String.fromEnvironment(
    'EMAILJS_SERVICE_ID',
    defaultValue: 'service_l6fdttb',
  );

  static const String templateId = String.fromEnvironment(
    'EMAILJS_TEMPLATE_ID',
    defaultValue: 'template_ngd8f9t',
  );

  static const String publicKey = String.fromEnvironment(
    'EMAILJS_PUBLIC_KEY',
    defaultValue: 'C3P2wYh7zDIMtMGtd',
  );

  static const String sendUrl = 'https://api.emailjs.com/api/v1.0/email/send';

  static String get accessTokenFromEnvironment =>
      const String.fromEnvironment('EMAILJS_ACCESS_TOKEN', defaultValue: '');

  static const String privateAccessToken = String.fromEnvironment(
    'EMAILJS_ACCESS_TOKEN',
    defaultValue: 'cCuOD6UxqxuNOI6pKtjRP',
  );
}
