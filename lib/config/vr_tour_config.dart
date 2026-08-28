/// VR tour URLs for in-app "Launch VR" / WebView flows.
///
/// Oroquieta City Plaza — 360° tour hosted on [Clear Pano](https://tours.clearpano.com/DDf5wDIh).
const String kOroquietaCityPlazaVrUrl =
    'https://tours.clearpano.com/DDf5wDIh';

/// True when [url] is a tiiny.host owner preview (not usable by tourists in-app).
bool isTiinyOwnerPreviewUrl(String? url) {
  final uri = Uri.tryParse(url?.trim() ?? '');
  if (uri == null) return false;
  return uri.host == 'tiiny.host' && uri.path.startsWith('/manage');
}

/// Clear Pano tours are password-protected and usually blank inside WebView/iframes.
bool isClearPanoTourUrl(String? url) {
  final uri = Uri.tryParse(url?.trim() ?? '');
  if (uri == null) return false;
  final host = uri.host.toLowerCase();
  return host == 'tours.clearpano.com' || host.endsWith('.clearpano.com');
}

/// Use the bundled Marzipano tour in-app (Oroquieta default / missing hosted URL).
bool useBundledTourForUrl(String? url) {
  final trimmed = url?.trim() ?? '';
  if (trimmed.isEmpty || trimmed == kOroquietaCityPlazaVrUrl) return true;
  return isClearPanoTourUrl(trimmed);
}

/// URL to open in WebView, or null to use bundled [kLocalVrTourAssetPath].
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

/// Legacy bundled Marzipano tour (unused — VR opens in browser via [kOroquietaCityPlazaVrUrl]).
const String kLocalVrTourAssetPath = 'assets/vr_tour/index.html';

/// Spot / municipality ids that should open [kOroquietaCityPlazaVrUrl].
const Set<String> kOroquietaPlazaVrSpotIds = {
  'oro-4',
  'oroquieta_city',
  'oroquieta_city_plaza',
  'oroquieta_plaza',
  'oroquieta_city_boulevard_and_peoples_park',
  'oroquieta-city-plaza',
};

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

/// Returns the canonical VR URL for Oroquieta plaza spots, or null.
String? vrUrlForSpotId(String? spotId, {String? spotName}) {
  if (isOroquietaPlazaSpot(spotId: spotId, spotName: spotName)) {
    return kOroquietaCityPlazaVrUrl;
  }
  return null;
}

/// Prefer canonical Oroquieta plaza VR URL, then an explicit [vrLink] from Firestore.
String? resolveVrTourUrl({String? vrLink, String? spotId, String? spotName}) {
  final known = vrUrlForSpotId(spotId, spotName: spotName);
  if (known != null) return known;
  final trimmed = vrLink?.trim();
  if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  return null;
}
