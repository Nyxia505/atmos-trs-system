// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:js' as js;

/// True when the Maps JavaScript API script has loaded (`google.maps` exists).
bool isGoogleMapsJsReady() {
  try {
    final google = js.context['google'];
    if (google == null || google is! js.JsObject) return false;
    final maps = google['maps'];
    if (maps == null || maps is! js.JsObject) return false;
    return maps['Map'] != null;
  } catch (_) {
    return false;
  }
}
