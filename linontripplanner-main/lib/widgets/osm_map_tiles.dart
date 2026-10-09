import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// Free OpenStreetMap raster tiles (no third-party basemap API key).
const String kOsmBasemapTileUrl =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

const String kOsmUserAgentPackageName = 'com.atmos.trs';

TileLayer osmBasemapTileLayer() {
  return TileLayer(
    urlTemplate: kOsmBasemapTileUrl,
    userAgentPackageName: kOsmUserAgentPackageName,
    maxNativeZoom: 19,
  );
}

Widget osmMapAttribution() {
  return const RichAttributionWidget(
    alignment: AttributionAlignment.bottomLeft,
    showFlutterMapAttribution: false,
    attributions: [
      TextSourceAttribution('© OpenStreetMap contributors'),
    ],
  );
}
