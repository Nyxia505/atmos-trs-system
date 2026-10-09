import 'package:flutter/foundation.dart' show kIsWeb;

import 'maps_platform_init_stub.dart'
    if (dart.library.io) 'maps_platform_init_io.dart';

/// Prepares Google Maps on Android before the first [GoogleMap] widget builds.
Future<void> initMapsForPlatform() async {
  if (kIsWeb) return;
  await initMapsForMobile();
}
