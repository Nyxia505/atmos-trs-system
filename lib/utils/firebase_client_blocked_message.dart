import 'package:flutter/foundation.dart' show debugPrint;

/// Messages when Google returns "Requests from this Android client … are blocked".
/// That happens if the Android SHA-1 is missing in Firebase or the API key in
/// Google Cloud Console does not allow this package + certificate.

bool looksLikeGoogleFirebaseClientBlocked(String? message) {
  if (message == null || message.isEmpty) return false;
  final m = message.toLowerCase();
  if (!m.contains('blocked')) return false;
  return m.contains('android client') ||
      m.contains('ios client') ||
      m.contains('requests from this');
}

/// Short text for SnackBars; full steps are in [firebaseClientBlockedDebugHint].
String firebaseClientBlockedUserMessage() {
  return 'Android app is not yet allowed by Firebase. Add SHA-1 for '
      'com.atmos.trs in Firebase/Google Cloud, then try again.';
}

void debugPrintFirebaseClientBlockedHint() {
  debugPrint(
    '[Firebase Android] If Auth says "Android client … blocked": '
    '(1) Firebase Console → Project settings → Android app → Add fingerprint. '
    '(2) Google Cloud Console → Credentials → API key (see google-services.json) '
    '→ Application restrictions: add Android package com.atmos.trs + same SHA-1, '
    'or None. Debug SHA-1: '
    'keytool -list -v -keystore USERPROFILE\\.android\\debug.keystore '
    '-alias androiddebugkey -storepass android -keypass android',
  );
}
