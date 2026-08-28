import 'package:atmos_trs_system/models/municipality.dart';
import 'package:atmos_trs_system/features/explore/explore_data.dart' show TouristSpot, kMockSpots;

/// Returns tourist spots that belong to the given municipality/city.
/// Used by the drill-down map and municipality details to filter spots by location.
List<TouristSpot> getTouristSpotsForMunicipality(Municipality municipality) {
  return kMockSpots
      .where((s) => _spotBelongsToMunicipality(s, municipality))
      .toList();
}

/// Returns true if [spot] is considered to be in [municipality] (by city name match).
bool _spotBelongsToMunicipality(TouristSpot spot, Municipality m) {
  final city = spot.city.trim().toLowerCase();
  final name = m.name.toLowerCase();
  if (city == name) return true;
  if (name.startsWith(city) || city.startsWith(name.split(' ').first)) return true;
  if (name.contains(city) || city.contains(name.split(' ').first)) return true;
  return false;
}
