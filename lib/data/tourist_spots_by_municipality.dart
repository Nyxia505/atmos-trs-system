import 'package:atmos_trs_system/models/municipality.dart';
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/features/explore/explore_data.dart'
    show TouristSpot, kMockSpots;
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/tourist_spot_visibility.dart';

/// Returns tourist spots that belong to the given municipality/city.
/// Used by the drill-down map and municipality details to filter spots by location.
List<TouristSpot> getTouristSpotsForMunicipality(Municipality municipality) {
  return kMockSpots
      .where((s) => _spotBelongsToMunicipality(s, municipality))
      .toList();
}

/// Merges live Active Firestore spots with bundled mock pins for one LGU.
/// Firestore docs win on id collisions; mock-only rows are kept as fallbacks.
List<TouristSpot> mergeMunicipalityTouristSpots({
  required Municipality municipality,
  required List<TouristSpotFirestore> firestoreSpots,
}) {
  final byId = <String, TouristSpot>{};
  for (final s in getTouristSpotsForMunicipality(municipality)) {
    byId[s.id] = s;
  }

  final want = normalizeMunicipalityId(municipality.id);
  for (final fs in firestoreSpots) {
    if (!isTouristSpotActiveStatus(fs.status)) continue;
    final mid = normalizeMunicipalityId(
      fs.municipalityId.isNotEmpty
          ? fs.municipalityId
          : getMunicipalityIdFromName(fs.municipality),
    );
    final belongs = (want.isNotEmpty && mid == want) ||
        _firestoreBelongsToMunicipality(fs, municipality);
    if (!belongs) continue;
    byId[fs.id] = touristSpotFromFirestoreModel(fs);
  }
  return byId.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

TouristSpot touristSpotFromFirestoreModel(TouristSpotFirestore fs) {
  final vr = (fs.vrLink ?? '').trim();
  return TouristSpot(
    id: fs.id,
    name: fs.name,
    category: fs.category.isEmpty ? 'Spot' : fs.category,
    imageUrl: (fs.image ?? '').trim(),
    distance: 0,
    rating: fs.rating,
    description: fs.description,
    city: fs.municipality.isNotEmpty ? fs.municipality : fs.municipalityId,
    vrLink: vr.isEmpty ? null : vr,
    latitude: fs.latitude,
    longitude: fs.longitude,
    hasVR: vr.isNotEmpty,
  );
}

/// Returns true if [spot] is considered to be in [municipality] (by city name match).
bool _spotBelongsToMunicipality(TouristSpot spot, Municipality m) {
  final city = spot.city.trim().toLowerCase();
  final name = m.name.toLowerCase();
  if (city.isEmpty) return false;
  if (city == name) return true;
  if (name.startsWith(city) || city.startsWith(name.split(' ').first)) {
    return true;
  }
  if (name.contains(city) || city.contains(name.split(' ').first)) return true;
  return false;
}

bool _firestoreBelongsToMunicipality(
  TouristSpotFirestore spot,
  Municipality m,
) {
  final city = spot.municipality.trim().toLowerCase();
  final name = m.name.toLowerCase();
  if (city.isEmpty) return false;
  if (city == name) return true;
  if (name.startsWith(city) || city.startsWith(name.split(' ').first)) {
    return true;
  }
  if (name.contains(city) || city.contains(name.split(' ').first)) return true;
  return false;
}
