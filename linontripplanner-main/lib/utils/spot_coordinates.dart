import 'package:latlong2/latlong.dart';

import '../data.dart';
import '../municipality_coordinates.dart';

/// True when [latitude] / [longitude] are finite numbers in WGS84 range.
bool isValidSpotCoordinate(double? latitude, double? longitude) {
  if (latitude == null || longitude == null) return false;
  if (latitude.isNaN || longitude.isNaN) return false;
  if (latitude.isInfinite || longitude.isInfinite) return false;
  return latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;
}

LatLng misamisOccidentalOsmCenter() => LatLng(
      misamisOccidentalCenter.latitude,
      misamisOccidentalCenter.longitude,
    );

/// Map camera for the tourist-spot location picker.
///
/// Prefers saved coordinates, then the selected municipality center, then
/// the provincial default.
LatLng initialSpotPickerCenter({
  double? latitude,
  double? longitude,
  String? municipalityName,
}) {
  if (isValidSpotCoordinate(latitude, longitude)) {
    return LatLng(latitude!, longitude!);
  }
  final name = municipalityName?.trim() ?? '';
  if (name.isNotEmpty) {
    for (final municipality in municipalities) {
      if (municipality.name == name || municipality.shortName == name) {
        final center = getMunicipalityCoordinates(municipality);
        if (center != null) {
          return LatLng(center.latitude, center.longitude);
        }
        break;
      }
    }
  }
  return misamisOccidentalOsmCenter();
}

double initialSpotPickerZoom({
  double? latitude,
  double? longitude,
  String? municipalityName,
}) {
  if (isValidSpotCoordinate(latitude, longitude)) return 15;
  final name = municipalityName?.trim() ?? '';
  if (name.isNotEmpty) return 13;
  return 9;
}
