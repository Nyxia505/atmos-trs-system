import 'package:atmos_trs_system/config/vr_tour_config.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Loads the bundled Marzipano tour in a WebView.
///
/// On Android, [WebViewController.loadFlutterAsset] does not resolve relative
/// `js/` / `css/` paths — use the app-assets HTTPS origin instead.
Future<void> loadBundledVrTour(WebViewController controller) {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return controller.loadRequest(
      Uri.parse(
        'https://appassets.androidplatform.net/assets/$kLocalVrTourAssetPath',
      ),
    );
  }
  return controller.loadFlutterAsset(kLocalVrTourAssetPath);
}
