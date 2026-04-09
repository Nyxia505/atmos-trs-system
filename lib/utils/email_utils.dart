/// Normalizes email for Firebase Auth and Firestore (trim + lowercase).
String normalizeEmail(String email) => email.trim().toLowerCase();

/// Validates common email shapes without rejecting longer TLDs (e.g. .travel, .museum).
bool isValidEmailFormat(String email) {
  final s = email.trim();
  if (s.isEmpty) return false;
  return RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(s);
}

/// Masks an email for read-only profile display (e.g. `g***@m***.ph`).
String maskEmailForDisplay(String email) {
  final s = email.trim();
  if (s.isEmpty) return 'N/A';
  final at = s.indexOf('@');
  if (at <= 0) return '***';
  final local = s.substring(0, at);
  final domain = s.substring(at + 1);
  if (local.isEmpty) return '***@$domain';
  final firstLocal = local[0];
  final lastDot = domain.lastIndexOf('.');
  if (lastDot <= 0) {
    return '$firstLocal***@***';
  }
  final tld = domain.substring(lastDot);
  final domainPart = domain.substring(0, lastDot);
  final dMasked = domainPart.isEmpty
      ? '***'
      : '${domainPart[0]}***';
  return '$firstLocal***@$dMasked$tld';
}
