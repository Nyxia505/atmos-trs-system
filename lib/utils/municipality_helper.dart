import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';

/// Normalizes municipality ID for consistent storage and querying.
/// - Trims and lowercases.
/// - Maps common spelling variants to canonical id (e.g. "ozamis" → "ozamiz")
///   so check-ins appear on the correct municipality dashboard.
String normalizeMunicipalityId(String? id) {
  if (id == null) return '';
  final v = id.trim().toLowerCase();
  if (v.isEmpty) return '';
  // Canonical id in data is "ozamiz"; "ozamis" is a common spelling.
  if (v == 'ozamis') return 'ozamiz';
  return v;
}

/// Returns the canonical municipality id for dashboard filtering when you only
/// have a display name (e.g. "Oroquieta City" → "oroquieta", "Tangub City" → "tangub").
/// Used so check-ins saved with municipality = "Oroquieta City" get municipalityId = "oroquieta"
/// and appear on that LGU's dashboard.
String getMunicipalityIdFromName(String? displayName) {
  if (displayName == null || displayName.trim().isEmpty) return '';
  final name = displayName.trim().toLowerCase();
  for (final m in getMisamisOccidentalMunicipalities()) {
    if (m.name.trim().toLowerCase() == name) return m.id;
  }
  // "Ozamiz City" (common spelling) → ozamiz (data uses "Ozamis City")
  if (name == 'ozamiz city') return 'ozamiz';
  return normalizeMunicipalityId(displayName);
}

/// Returns municipality IDs to use in Firestore queries so that all
/// check-ins for a municipality are found (canonical + alternate spellings).
List<String> municipalityIdsForQuery(String? storedMunicipalityId) {
  final canonical = normalizeMunicipalityId(storedMunicipalityId);
  if (canonical.isEmpty) return [];
  if (canonical == 'ozamiz') return ['ozamiz', 'ozamis'];
  return [canonical];
}

/// Canonical ids for the province (Governor / province-wide filters).
Set<String> misamisOccidentalMunicipalityIdSet() {
  return {
    for (final m in getMisamisOccidentalMunicipalities()) normalizeMunicipalityId(m.id),
  };
}

/// True when [municipalityId] matches one of the 17 Misamis Occidental LGUs.
bool isMisamisOccidentalMunicipalityId(String? municipalityId) {
  final id = normalizeMunicipalityId(municipalityId);
  if (id.isEmpty) return false;
  return misamisOccidentalMunicipalityIdSet().contains(id);
}

/// Municipal center (Misamis Occidental list) for LGU QR proximity when the QR has no embedded anchor.
({double lat, double lng})? getMunicipalityAnchorCoordinates(String municipalityId) {
  final id = normalizeMunicipalityId(municipalityId);
  if (id.isEmpty) return null;
  for (final m in getMisamisOccidentalMunicipalities()) {
    if (m.id == id) return (lat: m.lat, lng: m.lng);
  }
  return null;
}
