import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// FlutterFire options. **Web** must use [web] — [FirebaseOptions.appId] contains `:web:`.
///
/// **Web:** If Auth on Chrome fails with client-application-blocked errors, the API key in
/// [web] may be restricted to Android-only in Google Cloud Console. Open
/// **APIs & Services → Credentials**, select the key matching [web.apiKey], and set
/// **Application restrictions** to **HTTP referrers** (include `http://localhost/*`,
/// `http://127.0.0.1/*`) or **None** for local dev — not Android-only.
///
/// **Android:** If Auth shows `Requests from this Android client application com.atmos.trs are blocked`,
/// add your **SHA-1** (and SHA-256) in Firebase Console → Project settings → Your apps → Android app.
/// Then open Google Cloud Console → **APIs & Services → Credentials** → the API key matching
/// [android.apiKey] → under **Application restrictions**, either set **None** (dev) or add
/// **Android app** with package `com.atmos.trs` and the **same** SHA-1. Debug keystore:
/// `keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore -alias androiddebugkey -storepass android -keypass android`
///
/// Re-sync: `dart pub global activate flutterfire_cli` then `flutterfire configure`.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  /// "ATMOS-TRS Web" — must match Firebase Console → Project settings → Your apps → Web.
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAQcksY7LOLTeGKx_OwhDQ2wNLJ4o_OgtU',
    appId: '1:760231001760:web:609c5e6783594773cf13c5',
    messagingSenderId: '760231001760',
    projectId: 'atmos-trs-system',
    authDomain: 'atmos-trs-system.firebaseapp.com',
    storageBucket: 'atmos-trs-system.firebasestorage.app',
    measurementId: 'G-4B8Z74TKFZ',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBuYILpEr9o7m3KUblvE90KrPouvK4mHm0',
    appId: '1:760231001760:android:7bec7cd7e6227d84cf13c5',
    messagingSenderId: '760231001760',
    projectId: 'atmos-trs-system',
    storageBucket: 'atmos-trs-system.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBuYILpEr9o7m3KUblvE90KrPouvK4mHm0',
    appId: '1:760231001760:ios:7bec7cd7e6227d84cf13c5',
    messagingSenderId: '760231001760',
    projectId: 'atmos-trs-system',
    storageBucket: 'atmos-trs-system.firebasestorage.app',
    iosBundleId: 'com.atmos.trs',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyBuYILpEr9o7m3KUblvE90KrPouvK4mHm0',
    appId: '1:760231001760:ios:7bec7cd7e6227d84cf13c5',
    messagingSenderId: '760231001760',
    projectId: 'atmos-trs-system',
    storageBucket: 'atmos-trs-system.firebasestorage.app',
    iosBundleId: 'com.atmos.trs',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAQcksY7LOLTeGKx_OwhDQ2wNLJ4o_OgtU',
    appId: '1:760231001760:web:609c5e6783594773cf13c5',
    messagingSenderId: '760231001760',
    projectId: 'atmos-trs-system',
    authDomain: 'atmos-trs-system.firebaseapp.com',
    storageBucket: 'atmos-trs-system.firebasestorage.app',
    measurementId: 'G-4B8Z74TKFZ',
  );
}
