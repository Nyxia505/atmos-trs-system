import 'dart:math' as math;

import 'data.dart';
import 'municipality_coordinates.dart';

/// Default bus terminals/stops keyed by [Municipality.name].
const Map<String, MunicipalityBusTerminal> kDefaultMunicipalityBusTerminals = {
  'Oroquieta City (Provincial Capital)': MunicipalityBusTerminal(
    name: 'Oroquieta bus terminal',
    latitude: 8.493037148800576,
    longitude: 123.79814266814685,
    kind: 'terminal',
  ),
  'Plaridel': MunicipalityBusTerminal(
    name: 'Plaridel bus terminal',
    latitude: 8.620136282529488,
    longitude: 123.70950131047762,
    kind: 'terminal',
  ),
  'Aloran': MunicipalityBusTerminal(
    name: 'Aloran bus stop',
    latitude: 8.412249537859656,
    longitude: 123.82317045284562,
    kind: 'stop',
  ),
  'Lopez Jaena': MunicipalityBusTerminal(
    name: 'Lopez Jaena bus stop',
    latitude: 8.5525828978222,
    longitude: 123.7690860488779,
    kind: 'stop',
  ),
  'Calamba': MunicipalityBusTerminal(
    name: 'Calamba and Baliangao bus terminal',
    latitude: 8.5598630610656,
    longitude: 123.64246380406652,
    kind: 'terminal',
  ),
  'Baliangao': MunicipalityBusTerminal(
    name: 'Calamba and Baliangao bus terminal',
    latitude: 8.5598630610656,
    longitude: 123.64246380406652,
    kind: 'terminal',
  ),
  'Panaon': MunicipalityBusTerminal(
    name: 'Panaon bus stop',
    latitude: 8.374298443375187,
    longitude: 123.84065433688431,
    kind: 'stop',
  ),
  'Sapang Dalaga': MunicipalityBusTerminal(
    name: 'Sapang Dalaga bus stop',
    latitude: 8.54532085508384,
    longitude: 123.5682212764322,
    kind: 'stop',
  ),
  'Jimenez': MunicipalityBusTerminal(
    name: 'Jimenez bus terminal',
    latitude: 8.33713480807977,
    longitude: 123.84553724513275,
    kind: 'terminal',
  ),
  'Sinacaban': MunicipalityBusTerminal(
    name: 'Sinacaban bus terminal',
    latitude: 8.28564823872101,
    longitude: 123.84346050720977,
    kind: 'terminal',
  ),
  'Tudela': MunicipalityBusTerminal(
    name: 'Tudela bus stop',
    latitude: 8.240302600302313,
    longitude: 123.84643162121777,
    kind: 'stop',
  ),
  'Clarin': MunicipalityBusTerminal(
    name: 'Clarin bus terminal',
    latitude: 8.195384812228278,
    longitude: 123.85786167978975,
    kind: 'terminal',
  ),
  'Ozamiz City': MunicipalityBusTerminal(
    name: 'Ozamiz bus terminal',
    latitude: 8.157382755562983,
    longitude: 123.83988623746002,
    kind: 'terminal',
  ),
  'Tangub City': MunicipalityBusTerminal(
    name: 'Tangub bus terminal',
    latitude: 8.073984530739589,
    longitude: 123.75062495439016,
    kind: 'terminal',
  ),
};

/// Municipalities whose bus terminal/stop is never drawn as a map pin (no real
/// stop in town). Fares and routing still use [transportEndpointFor].
const Set<String> kMunicipalitiesWithoutBusPin = {
  'Concepcion',
  'Don Victoriano Chiongbian',
};

bool showsBusTerminalPin(Municipality municipality) =>
    !kMunicipalitiesWithoutBusPin.contains(municipality.name) &&
    !kMunicipalitiesWithoutBusPin.contains(municipality.shortName);

/// Resolves a default terminal for [municipality] by full or short name.
MunicipalityBusTerminal? defaultBusTerminalFor(Municipality municipality) {
  return kDefaultMunicipalityBusTerminals[municipality.name] ??
      kDefaultMunicipalityBusTerminals[municipality.shortName];
}

/// Fills [municipalities] with defaults where [Municipality.busTerminal] is null.
void applyDefaultMunicipalityBusTerminals() {
  for (var i = 0; i < municipalities.length; i++) {
    final m = municipalities[i];
    if (m.busTerminal != null) continue;
    final terminal =
        defaultBusTerminalFor(m) ?? resolveTransportEndpointFor(m);
    municipalities[i] = Municipality(
      name: m.name,
      shortName: m.shortName,
      imagePath: m.imagePath,
      description: m.description,
      spots: m.spots,
      divisionKind: m.divisionKind,
      busTerminal: terminal,
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

/// Nearest registered bus terminal/stop for [municipality] (own default, Firestore
/// terminal, or geographically nearest hub in the province).
MunicipalityBusTerminal resolveTransportEndpointFor(Municipality municipality) {
  final direct = municipality.busTerminal ?? defaultBusTerminalFor(municipality);
  if (direct != null) return direct;

  final center = getMunicipalityCoordinates(municipality);
  if (center == null) {
    return MunicipalityBusTerminal(
      name: '${municipality.shortName} bus stop',
      latitude: 8.45,
      longitude: 123.75,
      kind: 'stop',
    );
  }

  MunicipalityBusTerminal? nearestHub;
  var bestKm = double.infinity;
  for (final hub in kDefaultMunicipalityBusTerminals.values) {
    final km = haversineDistanceKm(
      center.latitude,
      center.longitude,
      hub.latitude,
      hub.longitude,
    );
    if (km < bestKm) {
      bestKm = km;
      nearestHub = hub;
    }
  }

  final via = nearestHub?.name ?? 'provincial bus hub';
  return MunicipalityBusTerminal(
    name: '${municipality.shortName} bus stop (nearest: $via)',
    latitude: center.latitude,
    longitude: center.longitude,
    kind: 'stop',
  );
}

/// Origin/destination endpoint for a municipality (ensures every LGU has a hub).
MunicipalityBusTerminal transportEndpointFor(Municipality municipality) {
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
