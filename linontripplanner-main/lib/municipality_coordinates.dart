import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'data.dart';
import 'municipality_bus_terminals.dart' show showsBusTerminalPin;

/// Bounds of Misamis Occidental province (Philippines). Use for cameraTargetBounds so the map stays centered on the province.
final LatLngBounds misamisOccidentalBounds = LatLngBounds(
  southwest: const LatLng(7.85, 123.25),
  northeast: const LatLng(8.75, 123.95),
);

/// Center of Misamis Occidental for initial map camera.
const LatLng misamisOccidentalCenter = LatLng(8.45, 123.75);

/// Approximate center coordinates for Misamis Occidental municipalities (Philippines).
/// Used to pin start/end on the trip route map based on user's chosen municipalities.
final Map<String, LatLng> _municipalityCoordinates = {
  'Aloran': const LatLng(8.412249537859656, 123.82317045284562),
  'Baliangao': const LatLng(8.6601564, 123.6027017),
  'Bonifacio': const LatLng(8.0522878, 123.6139434),
  'Calamba': const LatLng(8.5598630610656, 123.64246380406652),
  'Clarin': const LatLng(8.195384812228278, 123.85786167978975),
  'Concepcion': const LatLng(8.4233368, 123.6032778),
  'Don Victoriano Chiongbian': const LatLng(8.2492223, 123.5673621),
  'Don V. Chiongbian': const LatLng(8.2492223, 123.5673621),
  'Jimenez': const LatLng(8.33713480807977, 123.84553724513275),
  'Lopez Jaena': const LatLng(8.5525828978222, 123.7690860488779),
  'Oroquieta City (Provincial Capital)': const LatLng(8.493037148800576, 123.79814266814685),
  'Oroquieta City': const LatLng(8.493037148800576, 123.79814266814685),
  'Ozamiz City': const LatLng(8.157382755562983, 123.83988623746002),
  'Panaon': const LatLng(8.374298443375187, 123.84065433688431),
  'Plaridel': const LatLng(8.620136282529488, 123.70950131047762),
  'Sapang Dalaga': const LatLng(8.54532085508384, 123.5682212764322),
  'Sinacaban': const LatLng(8.28564823872101, 123.84346050720977),
  'Tangub City': const LatLng(8.073984530739589, 123.75062495439016),
  'Tudela': const LatLng(8.240302600302313, 123.84643162121777),
};

/// Returns the map coordinates for [municipality], or null if not found.
/// Prefers [Municipality.busTerminal], then static centers by name.
LatLng? getMunicipalityCoordinates(Municipality municipality) {
  final terminal = municipality.busTerminal;
  if (terminal != null && showsBusTerminalPin(municipality)) {
    return LatLng(terminal.latitude, terminal.longitude);
  }
  return _municipalityCoordinates[municipality.name] ??
      _municipalityCoordinates[municipality.shortName];
}
