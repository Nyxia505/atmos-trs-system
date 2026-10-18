import 'dart:math' as math;

import 'data.dart';
import 'services/bus_location_store.dart';

/// A pin is shown only when Firestore has an active stop with coordinates.
bool showsBusTerminalPin(Municipality municipality) =>
    municipality.busTerminal != null;

MunicipalityBusTerminal? _terminalFromLocation(BusLocation? location) {
  if (location == null || !location.hasValidCoordinates) return null;
  return MunicipalityBusTerminal(
    name: location.name,
    latitude: location.latitude,
    longitude: location.longitude,
    kind: location.locationType,
  );
}

/// Active bus stop/terminal for [municipality] from Firestore. No hardcoded fallback.
MunicipalityBusTerminal? defaultBusTerminalFor(Municipality municipality) {
  return _terminalFromLocation(
        BusLocationStore.instance.primaryForMunicipality(municipality.name),
      ) ??
      _terminalFromLocation(
        BusLocationStore.instance
            .primaryForMunicipality(municipality.shortName),
      );
}

/// Copies Firestore bus locations onto [municipalities]. Missing stops stay null.
void applyDefaultMunicipalityBusTerminals() {
  for (var i = 0; i < municipalities.length; i++) {
    final m = municipalities[i];
    municipalities[i] = Municipality(
      name: m.name,
      shortName: m.shortName,
      imagePath: m.imagePath,
      description: m.description,
      spots: m.spots,
      divisionKind: m.divisionKind,
      busTerminal: defaultBusTerminalFor(m),
    );
  }
}

Map<String, dynamic>? busTerminalFirestorePayload(MunicipalityBusTerminal? t) {
  if (t == null) return null;
  return t.toFirestoreMap();
}

/// Haversine distance in kilometers between two WGS84 points.
double haversineDistanceKm(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const earthRadiusKm = 6371.0;
  final dLat = _toRad(lat2 - lat1);
  final dLon = _toRad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRad(lat1)) *
          math.cos(_toRad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusKm * c;
}

double _toRad(double deg) => deg * math.pi / 180.0;

/// Bus stop/terminal saved for [municipality], or null when none is on file.
MunicipalityBusTerminal? resolveTransportEndpointFor(Municipality municipality) {
  return municipality.busTerminal ?? defaultBusTerminalFor(municipality);
}

/// Origin/destination endpoint for a municipality. Null when Firestore has none.
MunicipalityBusTerminal? transportEndpointFor(Municipality municipality) {
  return resolveTransportEndpointFor(municipality);
}

MunicipalityBusTerminal? busTerminalFromFirestoreDoc(Map<String, dynamic> d) {
  final nested = d['busTerminal'];
  if (nested is Map<String, dynamic>) {
    return MunicipalityBusTerminal.fromFirestoreMap(nested);
  }
  if (nested is Map) {
    return MunicipalityBusTerminal.fromFirestoreMap(
      Map<String, dynamic>.from(nested),
    );
  }
  return null;
}
