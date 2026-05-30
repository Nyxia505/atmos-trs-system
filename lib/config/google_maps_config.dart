/// Google Maps API keys for the **atmos-trs-system** GCP project.
///
/// **Web:** [webApiKey] in `web/index.html` (Maps JavaScript API).
/// **Android:** [androidApiKey] in `AndroidManifest.xml` (`com.google.android.geo.API_KEY`).
///
/// Override at build time: `--dart-define=GOOGLE_MAPS_API_KEY=...` or
/// `GOOGLE_MAPS_ANDROID_API_KEY=...`. Set `USE_GOOGLE_MAPS_WEB=false` to use OSM on web.
///
/// ### Fix ApiTargetBlockedMapError (console)
/// 1. [Google Cloud Console](https://console.cloud.google.com/) → same project as Firebase
/// 2. **APIs & Services → Library** → enable **Maps JavaScript API**
/// 3. **Credentials** → create **API key** → Application restrictions: **HTTP referrers**
///    - `http://localhost:*/*` and `http://127.0.0.1:*/*` (dev)
///    - `https://atmos-trs-system.web.app/*` (Firebase Hosting)
/// 4. API restrictions: allow **Maps JavaScript API** (do not use Android-only key on web)
/// 5. Enable **billing** on the project
///
/// **Android / iOS** use [androidApiKey] in native config (Maps SDK for Android/iOS).
class GoogleMapsConfig {
  GoogleMapsConfig._();

  /// Browser key for Flutter **web** (`web/index.html`). Not the Android SDK key.
  static const String webApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'AIzaSyABHzKStpFi9K-nIb0TS4kmedR-9_-zqh4',
  );

  @Deprecated('Use webApiKey')
  static const String apiKey = webApiKey;

  static const String androidApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_ANDROID_API_KEY',
    defaultValue: 'AIzaSyB9VpH9L8BD57CjGQBTTY1ZpLa8OtvYhRI',
  );

  static bool get hasWebApiKey => webApiKey.trim().isNotEmpty;
}
