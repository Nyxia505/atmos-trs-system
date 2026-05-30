import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// OpenStreetMap.org — reliable on Flutter web (no subdomain).
const String kAtmosOsmPrimaryTemplate =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// Carto Voyager fallback (subdomains required).
const String kAtmosOsmFallbackTemplate =
    'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png';

const List<String> kAtmosOsmTileSubdomains = ['a', 'b', 'c', 'd'];

/// Primary template alias for screens that set [TileLayer.urlTemplate] directly.
const String kAtmosOsmTileTemplate = kAtmosOsmPrimaryTemplate;

/// Shared basemap with automatic fallback when primary tiles fail.
class AtmosOsmTileLayer extends StatefulWidget {
  const AtmosOsmTileLayer({
    super.key,
    this.tileBuilder,
    this.retinaMode = true,
  });

  final TileBuilder? tileBuilder;
  final bool? retinaMode;

  @override
  State<AtmosOsmTileLayer> createState() => _AtmosOsmTileLayerState();
}

class _AtmosOsmTileLayerState extends State<AtmosOsmTileLayer> {
  bool _useFallback = false;

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: _useFallback
          ? kAtmosOsmFallbackTemplate
          : kAtmosOsmPrimaryTemplate,
      subdomains: _useFallback ? kAtmosOsmTileSubdomains : const [],
      userAgentPackageName: 'com.atmos.trs',
      maxNativeZoom: 19,
      retinaMode: widget.retinaMode,
      tileBuilder: widget.tileBuilder,
      errorTileCallback: (tile, error, stackTrace) {
        if (_useFallback || !mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _useFallback = true);
        });
      },
    );
  }
}

/// Convenience for [FlutterMap.children].
Widget buildAtmosOsmTileLayer({
  TileBuilder? tileBuilder,
  bool? retinaMode,
}) {
  return AtmosOsmTileLayer(
    tileBuilder: tileBuilder,
    retinaMode: retinaMode,
  );
}
