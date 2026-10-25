/// VR tour URLs for in-app "Launch VR" / WebView flows.
///
/// Oroquieta City Plaza — 360° tour hosted on [Clear Pano](https://tours.clearpano.com/aCxkEqVT).
const String kOroquietaCityPlazaVrUrl =
    'https://tours.clearpano.com/aCxkEqVT';

/// Kenjelo Farm and Recreation Resort — 360° tour on Clear Pano.
const String kKenjeloFarmVrUrl = 'https://tours.clearpano.com/Rpj4vYOF';

/// Saint John the Baptist Parish Church (Jimenez Church) — 360° tour on Clear Pano.
const String kJimenezChurchVrUrl = 'https://tours.clearpano.com/Yx3FCtm9';

/// Clarin — Suman Capital of Misamis Occidental — 360° tour on Clear Pano.
const String kClarinSumanVrUrl = 'https://tours.clearpano.com/GmFjcb6k';

/// Cotta Fort & Shrine, Ozamiz City — 360° tour on Clear Pano.
const String kCottaFortVrUrl = 'https://tours.clearpano.com/rDNLii_q';

/// True when [url] is a tiiny.host owner preview (not usable by tourists in-app).
bool isTiinyOwnerPreviewUrl(String? url) {
  final uri = Uri.tryParse(url?.trim() ?? '');
  if (uri == null) return false;
  return uri.host == 'tiiny.host' && uri.path.startsWith('/manage');
}

/// URL to open in the in-app WebView, or null when no usable tour link exists.
String? hostedVrUrlForLaunch(String? url) {
  final trimmed = url?.trim() ?? '';
  if (trimmed.isEmpty || isTiinyOwnerPreviewUrl(trimmed)) return null;
  return trimmed;
}

/// Human-readable label for VR UI (Oroquieta flagship spot).
const String kOroquietaCityPlazaVrTitle = 'Oroquieta City Plaza';

/// Firestore document id for the flagship Oroquieta plaza spot.
const String kOroquietaPlazaSpotDocId = 'oroquieta_city_boulevard_and_peoples_park';

/// Default VR tour when no spot-specific link is set (Oroquieta City Plaza).
const String kVrTourUrl = kOroquietaCityPlazaVrUrl;

/// Spot / municipality ids that should open [kOroquietaCityPlazaVrUrl].
const Set<String> kOroquietaPlazaVrSpotIds = {
  'oro-4',
  'oroquieta_city',
  'oroquieta_city_plaza',
  'oroquieta_plaza',
  'oroquieta_city_boulevard_and_peoples_park',
  'oroquieta-city-plaza',
};

const Set<String> kKenjeloFarmVrSpotIds = {
  'oroquieta_kenjelo_farm_resort',
  'kenjelo',
  'kenjelo_farm',
  'kenjelo_farm_and_recreation_resort',
};

const Set<String> kJimenezChurchVrSpotIds = {
  'jimenez_st_john_the_baptist_church',
  'jimenez_church',
  'st_john_the_baptist_church_jimenez',
  'jimenez',
};

const Set<String> kClarinSumanVrSpotIds = {
  'clarin_suman_capital',
  'clarin_suman',
  'suman_capital_clarin',
};

const Set<String> kCottaFortVrSpotIds = {
  'ozamiz_cotta_fort_shrine',
  'cotta_fort',
  'cotta_fort_shrine',
  'cota_fort',
};

/// Canonical Clear Pano destinations (real tours — not placeholders).
class KnownVrDestination {
  const KnownVrDestination({
    required this.spotId,
    required this.name,
    required this.municipalityId,
    required this.municipality,
    required this.category,
    required this.imageAsset,
    required this.vrUrl,
  });

  final String spotId;
  final String name;
  final String municipalityId;
  final String municipality;
  final String category;
  final String imageAsset;
  final String vrUrl;
}

/// Province VR catalog used by OPTACA view-only + tourist launch resolution.
const List<KnownVrDestination> kKnownVrDestinations = [
  KnownVrDestination(
    spotId: kOroquietaPlazaSpotDocId,
    name: 'Oroquieta City Boulevard And People\u2019s Park',
    municipalityId: 'oroquieta',
    municipality: 'Oroquieta City',
    category: 'Park',
    imageAsset: 'assets/images/oroquieta City plaza.jpeg',
    vrUrl: kOroquietaCityPlazaVrUrl,
  ),
  KnownVrDestination(
    spotId: 'oroquieta_kenjelo_farm_resort',
    name: 'Kenjelo Farm and Recreation Resort',
    municipalityId: 'oroquieta',
    municipality: 'Oroquieta City',
    category: 'Nature',
    imageAsset: 'assets/images/Kenjelo.jpg',
    vrUrl: kKenjeloFarmVrUrl,
  ),
  KnownVrDestination(
    spotId: 'jimenez_st_john_the_baptist_church',
    name: 'Jimenez Church (St John The Baptist)',
    municipalityId: 'jimenez',
    municipality: 'Jimenez',
    category: 'Historical',
    imageAsset: 'assets/images/Jimenez.png',
    vrUrl: kJimenezChurchVrUrl,
  ),
  KnownVrDestination(
    spotId: 'clarin_suman_capital',
    name: 'Clarin Suman Capital',
    municipalityId: 'clarin',
    municipality: 'Clarin',
    category: 'Historical',
    imageAsset: 'assets/images/Clarin.png',
    vrUrl: kClarinSumanVrUrl,
  ),
  KnownVrDestination(
    spotId: 'ozamiz_cotta_fort_shrine',
    name: 'Cotta Fort & Shrine',
    municipalityId: 'ozamiz',
    municipality: 'Ozamis City',
    category: 'Historical',
    imageAsset: 'assets/images/Cotta Fort & Shrine.jpg',
    vrUrl: kCottaFortVrUrl,
  ),
];

/// True when this destination is Oroquieta City Plaza (canonical VR tour).
bool isOroquietaPlazaSpot({String? spotId, String? spotName}) {
  final id = spotId?.trim().toLowerCase() ?? '';
  if (id.isNotEmpty && kOroquietaPlazaVrSpotIds.contains(id)) {
    return true;
  }
  final name = spotName?.trim().toLowerCase() ?? '';
  if (name.isEmpty) return false;
  if (!name.contains('oroquieta')) return false;
  return name.contains('plaza') ||
      name.contains('boulevard') ||
      name.contains('people') ||
      name.contains('peoples') ||
      name.contains('park');
}

bool isKenjeloFarmSpot({String? spotId, String? spotName}) {
  final id = spotId?.trim().toLowerCase() ?? '';
  if (id.isNotEmpty && kKenjeloFarmVrSpotIds.contains(id)) return true;
  final name = spotName?.trim().toLowerCase() ?? '';
  return name.contains('kenjelo');
}

bool isJimenezChurchSpot({String? spotId, String? spotName}) {
  final id = spotId?.trim().toLowerCase() ?? '';
  if (id.isNotEmpty && kJimenezChurchVrSpotIds.contains(id)) return true;
  final name = spotName?.trim().toLowerCase() ?? '';
  if (name.isEmpty) return false;
  if (name.contains('jimenez') &&
      (name.contains('church') ||
          name.contains('baptist') ||
          name.contains('st john') ||
          name.contains('saint john'))) {
    return true;
  }
  return false;
}

bool isClarinSumanSpot({String? spotId, String? spotName}) {
  final id = spotId?.trim().toLowerCase() ?? '';
  if (id.isNotEmpty && kClarinSumanVrSpotIds.contains(id)) return true;
  final name = spotName?.trim().toLowerCase() ?? '';
  if (name.isEmpty) return false;
  return name.contains('suman') ||
      (name.contains('clarin') && name.contains('capital'));
}

bool isCottaFortSpot({String? spotId, String? spotName}) {
  final id = spotId?.trim().toLowerCase() ?? '';
  if (id.isNotEmpty && kCottaFortVrSpotIds.contains(id)) return true;
  final name = spotName?.trim().toLowerCase() ?? '';
  if (name.isEmpty) return false;
  return name.contains('cotta fort') ||
      name.contains('cota fort') ||
      (name.contains('cotta') && name.contains('shrine')) ||
      (name.contains('cota') && name.contains('fort'));
}

/// Returns the canonical VR URL for known Clear Pano spots, or null.
String? vrUrlForSpotId(String? spotId, {String? spotName}) {
  if (isOroquietaPlazaSpot(spotId: spotId, spotName: spotName)) {
    return kOroquietaCityPlazaVrUrl;
  }
  if (isKenjeloFarmSpot(spotId: spotId, spotName: spotName)) {
    return kKenjeloFarmVrUrl;
  }
  if (isJimenezChurchSpot(spotId: spotId, spotName: spotName)) {
    return kJimenezChurchVrUrl;
  }
  if (isClarinSumanSpot(spotId: spotId, spotName: spotName)) {
    return kClarinSumanVrUrl;
  }
  if (isCottaFortSpot(spotId: spotId, spotName: spotName)) {
    return kCottaFortVrUrl;
  }
  return null;
}

/// Prefer canonical Clear Pano URL for known spots, then an explicit [vrLink].
String? resolveVrTourUrl({String? vrLink, String? spotId, String? spotName}) {
  final known = vrUrlForSpotId(spotId, spotName: spotName);
  if (known != null) return known;
  final trimmed = vrLink?.trim();
  if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  return null;
}

/// Merge Firestore spot rows with [kKnownVrDestinations] so OPTACA always lists
/// the real Clear Pano tours (Jimenez, Kenjelo, Clarin Suman, Cotta Fort, Plaza).
List<Map<String, dynamic>> mergeKnownVrDestinations(
  List<Map<String, dynamic>> spots,
) {
  final byId = <String, Map<String, dynamic>>{
    for (final s in spots)
      if ((s['id']?.toString() ?? '').isNotEmpty) s['id'].toString(): s,
  };

  final out = <Map<String, dynamic>>[];
  final seen = <String>{};

  for (final known in kKnownVrDestinations) {
    final existing = byId[known.spotId];
    if (existing != null) {
      final merged = Map<String, dynamic>.from(existing);
      final link = (merged['vr_link'] ??
              merged['vrLink'] ??
              merged['vrTourUrl'] ??
              '')
          .toString()
          .trim();
      if (link.isEmpty) {
        merged['vr_link'] = known.vrUrl;
        merged['hasVR'] = true;
      }
      if ((merged['image_url'] ?? merged['image'] ?? '')
          .toString()
          .trim()
          .isEmpty) {
        merged['image_url'] = known.imageAsset;
      }
      out.add(merged);
      seen.add(known.spotId);
      continue;
    }

    // Spot missing from Firestore — still show the real Clear Pano tour.
    out.add({
      'id': known.spotId,
      'name': known.name,
      'municipalityId': known.municipalityId,
      'municipality': known.municipality,
      'category': known.category,
      'description': '${known.name} — 360° virtual tour',
      'image_url': known.imageAsset,
      'vr_link': known.vrUrl,
      'hasVR': true,
      'status': 'Active',
    });
    seen.add(known.spotId);
  }

  for (final s in spots) {
    final id = s['id']?.toString() ?? '';
    if (id.isNotEmpty && seen.contains(id)) continue;
    final name = s['name']?.toString();
    final link = resolveVrTourUrl(
      vrLink: (s['vr_link'] ?? s['vrLink'] ?? s['vrTourUrl'] ?? '')
          .toString()
          .trim(),
      spotId: id,
      spotName: name,
    );
    if (link == null || hostedVrUrlForLaunch(link) == null) continue;
    final merged = Map<String, dynamic>.from(s);
    if ((merged['vr_link'] ?? '').toString().trim().isEmpty) {
      merged['vr_link'] = link;
      merged['hasVR'] = true;
    }
    out.add(merged);
    if (id.isNotEmpty) seen.add(id);
  }

  out.sort(
    (a, b) => (a['name']?.toString() ?? '')
        .toLowerCase()
        .compareTo((b['name']?.toString() ?? '').toLowerCase()),
  );
  return out;
}
