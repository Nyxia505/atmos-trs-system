import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart' as ll;

import '../data.dart';
import '../municipality_bus_terminals.dart' show showsBusTerminalPin;
import 'google_map_pin_icons.dart';

/// [municipality]'s bus terminal or stop when it should appear on maps.
MunicipalityBusTerminal? busTerminalForMap(Municipality municipality) {
  if (!showsBusTerminalPin(municipality)) return null;
  return municipality.busTerminal;
}

/// Map pin position for [municipality]'s bus terminal or stop.
gmaps.LatLng? busTerminalLatLng(Municipality municipality) {
  final t = busTerminalForMap(municipality);
  if (t == null) return null;
  return gmaps.LatLng(t.latitude, t.longitude);
}

String busTerminalMarkerTitle(MunicipalityBusTerminal terminal) {
  return terminal.kind == 'stop' ? 'Bus stop' : 'Bus terminal';
}

String busTerminalMarkerSnippet(
  Municipality municipality,
  MunicipalityBusTerminal terminal,
) {
  return '${terminal.name} · ${municipality.shortName.isNotEmpty ? municipality.shortName : municipality.name}';
}

Color _osmMarkerColor(MunicipalityBusTerminal terminal) {
  return terminal.kind == 'stop'
      ? GoogleMapPinIcons.busStopColor
      : GoogleMapPinIcons.busTerminalColor;
}

IconData _busMarkerIcon(MunicipalityBusTerminal terminal) {
  return terminal.kind == 'stop'
      ? Icons.directions_bus
      : Icons.directions_bus_filled;
}

/// Google Maps markers for bus terminals / stops (correct colors on web + mobile).
Future<Set<gmaps.Marker>> buildGoogleBusTerminalMarkersAsync(
  Iterable<Municipality> municipalities, {
  void Function(Municipality municipality)? onTap,
}) async {
  final terminalIcon = await GoogleMapPinIcons.busTerminal();
  final stopIcon = await GoogleMapPinIcons.busStop();

  final markers = <gmaps.Marker>{};
  for (final m in municipalities) {
    final terminal = busTerminalForMap(m);
    final pos = busTerminalLatLng(m);
    if (terminal == null || pos == null) continue;

    final id = m.name.replaceAll(RegExp(r'[^\w]'), '_');
    final icon = terminal.kind == 'stop' ? stopIcon : terminalIcon;
    markers.add(
      gmaps.Marker(
        markerId: gmaps.MarkerId('bus_$id'),
        position: pos,
        icon: icon,
        infoWindow: gmaps.InfoWindow(
          title: busTerminalMarkerTitle(terminal),
          snippet: busTerminalMarkerSnippet(m, terminal),
        ),
        onTap: onTap == null ? null : () => onTap(m),
        zIndex: 2,
      ),
    );
  }
  return markers;
}

/// FlutterMap markers for bus terminals / stops.
List<Marker> buildOsmBusTerminalMarkers(
  Iterable<Municipality> municipalities, {
  void Function(Municipality municipality)? onTap,
}) {
  final markers = <Marker>[];
  for (final m in municipalities) {
    final terminal = busTerminalForMap(m);
    final pos = busTerminalLatLng(m);
    if (terminal == null || pos == null) continue;

    final point = ll.LatLng(pos.latitude, pos.longitude);
    final label = busTerminalMarkerSnippet(m, terminal);
    markers.add(
      Marker(
        point: point,
        width: 44,
        height: 44,
        child: GestureDetector(
          onTap: onTap == null ? null : () => onTap(m),
          child: Tooltip(
            message: '${busTerminalMarkerTitle(terminal)}\n$label',
            child: Icon(
              _busMarkerIcon(terminal),
              color: _osmMarkerColor(terminal),
              size: 38,
              shadows: const [
                Shadow(blurRadius: 4, color: Colors.black38),
              ],
            ),
          ),
        ),
      ),
    );
  }
  return markers;
}

/// Legend for Map & Routes (bus terminal vs bus stop vs tourist spot).
Widget buildBusTerminalMapLegend({bool compact = false}) {
  return Container(
    padding: EdgeInsets.symmetric(
      horizontal: compact ? 10 : 12,
      vertical: compact ? 8 : 10,
    ),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Map legend',
          style: TextStyle(
            fontSize: compact ? 11 : 12,
            fontWeight: FontWeight.bold,
            color: AppColors.textDark,
          ),
        ),
        SizedBox(height: compact ? 6 : 8),
        _legendRow(
          icon: Icons.directions_bus_filled,
          color: GoogleMapPinIcons.busTerminalColor,
          label: 'Bus terminal',
          compact: compact,
        ),
        SizedBox(height: compact ? 4 : 6),
        _legendRow(
          icon: Icons.directions_bus,
          color: GoogleMapPinIcons.busStopColor,
          label: 'Bus stop',
          compact: compact,
        ),
        SizedBox(height: compact ? 4 : 6),
        _legendRow(
          icon: Icons.place,
          color: GoogleMapPinIcons.touristSpotColor,
          label: 'Tourist spot',
          compact: compact,
        ),
      ],
    ),
  );
}

Widget _legendRow({
  required IconData icon,
  required Color color,
  required String label,
  required bool compact,
}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: color, size: compact ? 16 : 18),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(
          fontSize: compact ? 11 : 12,
          color: AppColors.textGrey,
        ),
      ),
    ],
  );
}
