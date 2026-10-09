import 'dart:io' show Platform;

import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';

Future<void> initMapsForMobile() async {
  if (!Platform.isAndroid) return;
  try {
    await GoogleMapsFlutterAndroid()
        .initializeWithRenderer(AndroidMapRenderer.latest);
  } catch (_) {
    // Renderer may already be initialized.
  }
}
