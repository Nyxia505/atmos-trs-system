import 'package:flutter/foundation.dart' show kIsWeb;

/// Road directions via Firebase Cloud Function (web needs this for CORS).
///
/// Web: set true after billing is linked and you deploy:
/// `firebase deploy --only functions:getDirectionsHttp --project atmos-trs-system`
/// Android uses Google Directions API directly (no Cloud Function needed).
const bool directionsUseDeployedCloudFunction = false;

/// Trip Route map: when false, uses flutter_map (OpenStreetMap / CARTO).
/// When true, uses Google Maps (requires Maps SDK + billing).
const bool useGoogleMapsOnWeb = false;

/// When false, Trip Route uses Google Maps on all platforms.
bool get tripRouteUsesOsmMap => !useGoogleMapsOnWeb;

/// Google Maps / Directions API keys (Google Cloud Console, project atmos-trs-system).
///
/// Web "For development purposes only" / "can't load Google Maps" → in Cloud Console:
/// 1. Billing → link a billing account to project atmos-trs-system
/// 2. APIs & Services → enable **Maps JavaScript API** and **Directions API**
/// 3. Credentials → web key → Application restrictions: HTTP referrers, e.g.
///    `http://localhost:*`, `http://127.0.0.1:*`,
///    `https://atmos-trs-system.web.app/*`, `https://atmos-trs-system.firebaseapp.com/*`
/// 4. Keep [web/index.html] script key identical to [googleMapsApiKeyWeb]
///
/// Android key: Maps SDK for Android, Directions API, package + SHA-1 restriction.
const String? googleMapsApiKeyWeb = 'AIzaSyABHzKStpFi9K-nIb0TS4kmedR-9_-zqh4';
const String? googleMapsApiKeyAndroid = 'AIzaSyB9VpH9L8BD57CjGQBTTY1ZpLa8OtvYhRI';

/// Primary key for the current platform (map + directions).
String? get googleMapsApiKey => kIsWeb ? googleMapsApiKeyWeb : googleMapsApiKeyAndroid;

/// Keys to try for Directions (platform key first, then the other).
List<String> get googleMapsApiKeysForDirections {
  final keys = <String>[];
  void add(String? value) {
    if (value == null || value.isEmpty) return;
    if (!keys.contains(value)) keys.add(value);
  }

  add(googleMapsApiKey);
  add(kIsWeb ? googleMapsApiKeyAndroid : googleMapsApiKeyWeb);
  return keys;
}
