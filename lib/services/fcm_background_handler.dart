import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:atmos_trs_system/firebase_options.dart';

/// Must be a top-level function for [FirebaseMessaging.onBackgroundMessage].
///
/// Signup / verify OTP (`email_otp`) is intentionally not handled here — those
/// codes are local-only on the requesting device. Do not post a local
/// notification from FCM for them (prevents cross-device leaks).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final t = message.data['type']?.toString();
  if (t == 'email_otp') {
    debugPrint(
      '[Push] background: ignoring email_otp (signup OTP is local-only)',
    );
  }
}
