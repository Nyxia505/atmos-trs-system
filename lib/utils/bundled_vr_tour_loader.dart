import 'package:atmos_trs_system/config/vr_tour_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Loads the bundled Marzipano tour (`assets/vr_tour/index.html`) in a WebView.
///
/// Android previously used `https://appassets.androidplatform.net/...` without
/// configuring [WebViewAssetLoader], which caused `net::ERR_NAME_NOT_RESOLVED`.
/// We now load via [WebViewController.loadFlutterAsset] (file:///android_asset/…)
/// with an HTML+baseUrl fallback so relative `css/` and `js/` paths resolve.
Future<void> loadBundledVrTour(WebViewController controller) async {
  try {
    await controller.loadFlutterAsset(kLocalVrTourAssetPath);
  } catch (e, st) {
    debugPrint('loadFlutterAsset failed for VR tour: $e\n$st');
    await _loadBundledVrTourHtmlFallback(controller);
  }
}

/// Fallback: inject HTML with an android_asset / flutter_assets base URL so
/// relative scripts and stylesheets under `assets/vr_tour/` still load.
Future<void> _loadBundledVrTourHtmlFallback(
  WebViewController controller,
) async {
  final html = await rootBundle.loadString(kLocalVrTourAssetPath);
  final baseUrl = defaultTargetPlatform == TargetPlatform.android
      ? 'file:///android_asset/flutter_assets/assets/vr_tour/'
      : null;
  await controller.loadHtmlString(html, baseUrl: baseUrl);
}
