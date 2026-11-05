import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// OSM raster tiles — no API key, production-safe on Flutter web.
///
/// Carto Voyager (`basemaps.cartocdn.com/rastertiles/voyager`) now stamps
/// every tile with "API KEY REQUIRED". OpenStreetMap.org is already used by
/// ATMOS maps on the same Firebase Hosting origin.
const String kOsmBasemapTileUrl =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Esri World Street Map — no API key, CORS-friendly fallback if OSM 403/429s.
const String kOsmBasemapFallbackTileUrl =
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}';

const String kOsmUserAgentPackageName = 'com.atmos.trs';

Widget osmBasemapTileLayer() {
  return const OsmBasemapTileLayer();
}

class OsmBasemapTileLayer extends StatefulWidget {
  const OsmBasemapTileLayer({super.key});

  @override
  State<OsmBasemapTileLayer> createState() => _OsmBasemapTileLayerState();
}

class _OsmBasemapTileLayerState extends State<OsmBasemapTileLayer> {
  bool _useFallback = false;

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate:
          _useFallback ? kOsmBasemapFallbackTileUrl : kOsmBasemapTileUrl,
      userAgentPackageName: kOsmUserAgentPackageName,
      maxNativeZoom: 19,
      errorTileCallback: (tile, error, stackTrace) {
        if (_useFallback || !mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _useFallback = true);
        });
      },
    );
  }
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
