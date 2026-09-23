import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/qr_launch_query.dart';

/// Public URL opened by device cameras when the app is not installed.
///
/// Path + query (not hash) so Android App Links / iOS Universal Links receive
/// the full QR parameters. Firebase Hosting rewrites `/checkin` → `index.html`.
/// Legacy `#/landing?…` URLs remain parseable via [mergedLaunchQueryParameters].
const String kPublicCheckInBaseUrl = 'https://atmos-trs-system.web.app/checkin';

const String _kPublicCheckInBaseUrl = kPublicCheckInBaseUrl;

/// Parsed LGU QR: municipality id plus optional anchor coordinates printed on the poster.
class LguQrPayload {
  const LguQrPayload({
    required this.municipalityId,
    this.anchorLat,
    this.anchorLng,
  });

  final String municipalityId;
  final double? anchorLat;
  final double? anchorLng;

  bool get hasEmbeddedAnchor =>
      anchorLat != null &&
      anchorLng != null &&
      anchorLat!.abs() > 1e-7 &&
      anchorLng!.abs() > 1e-7;
}

/// Parsed spot check-in deep link / legacy QR payload.
class SpotCheckInPayload {
  const SpotCheckInPayload({
    required this.spotId,
    this.municipalityId,
    this.qrLat,
    this.qrLng,
  });

  final String spotId;
  final String? municipalityId;
  final double? qrLat;
  final double? qrLng;
}

/// Helper for generating unique QR payloads per tourist spot.
/// Scanner accepts URL `?type=spot&spot_id=…` or legacy `ATMOS-TRS-SPOT:municipalityId:spotId`.
/// When [latitude]/[longitude] are set, they are embedded so old prints can be matched to Firestore.
String spotQrData(
  String municipalityId,
  String spotId, {
  double? latitude,
  double? longitude,
}) {
  final id = normalizeMunicipalityId(municipalityId.trim());
  final sid = spotId.trim();
  final params = <String, String>{
    'type': 'spot',
    'municipality_id': id,
    'spot_id': sid,
  };
  if (latitude != null &&
      longitude != null &&
      latitude.abs() > 1e-7 &&
      longitude.abs() > 1e-7) {
    params['lat'] = latitude.toStringAsFixed(6);
    params['lng'] = longitude.toStringAsFixed(6);
  }
  return Uri.parse(_kPublicCheckInBaseUrl).replace(queryParameters: params).toString();
}

/// Parses spot QR (URL or `ATMOS-TRS-SPOT:…`).
SpotCheckInPayload? parseSpotCheckInPayload(String raw) {
  final s = raw.trim();
  final uri = Uri.tryParse(s);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    final q = mergedLaunchQueryParameters(uri);
    final type = (q['type'] ?? '').trim().toLowerCase();
    final spotId = (q['spot_id'] ?? q['spotId'] ?? '').trim();
    if (spotId.isNotEmpty &&
        (type == 'spot' || q.containsKey('spot_id') || q.containsKey('spotId'))) {
      final midRaw = q['municipality_id'] ?? q['municipalityId'] ?? '';
      final mid = midRaw.trim().isNotEmpty
          ? normalizeMunicipalityId(midRaw)
          : null;
      final lat = double.tryParse((q['lat'] ?? '').trim());
      final lng = double.tryParse((q['lng'] ?? '').trim());
      return SpotCheckInPayload(
        spotId: spotId,
        municipalityId: mid,
        qrLat: lat,
        qrLng: lng,
      );
    }
  }

  final legacy = parseSpotQrPayload(s);
  if (legacy.municipalityId != null || s.startsWith('ATMOS-TRS-SPOT:')) {
    return SpotCheckInPayload(
      spotId: legacy.spotId,
      municipalityId: legacy.municipalityId,
    );
  }
  if (legacy.spotId.isNotEmpty && legacy.spotId != s) {
    return SpotCheckInPayload(spotId: legacy.spotId);
  }
  return null;
}

/// Unique QR per LGU (municipality). Scanner format: ATMOS-TRS-LGU:municipalityId
/// Optional anchor (recommended for strict proximity): ATMOS-TRS-LGU:municipalityId:lat:lng
/// Example: ATMOS-TRS-LGU:ozamiz — Example with anchor: ATMOS-TRS-LGU:oroquieta:8.4859:123.8048
String lguQrData(String municipalityId, {double? anchorLat, double? anchorLng}) {
  final id = normalizeMunicipalityId(municipalityId.trim());
  final params = <String, String>{
    'type': 'lgu',
    'municipality_id': id,
  };
  if (anchorLat != null &&
      anchorLng != null &&
      anchorLat.abs() > 1e-7 &&
      anchorLng.abs() > 1e-7) {
    params['lat'] = anchorLat.toStringAsFixed(6);
    params['lng'] = anchorLng.toStringAsFixed(6);
  }
  // Use URL payload so phone camera apps can open web landing/check-in without the app.
  return Uri.parse(_kPublicCheckInBaseUrl)
      .replace(queryParameters: params)
      .toString();
}

/// Full LGU QR parse (id + optional lat/lng after the id).
///
/// Does **not** claim establishment/spot URLs that happen to include
/// `municipality_id` — those must route to their own handlers first.
LguQrPayload? parseLguQrPayload(String raw) {
  final s = raw.trim();
  final uri = Uri.tryParse(s);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    final q = mergedLaunchQueryParameters(uri);
    final type = (q['type'] ?? '').trim().toLowerCase();
    // Never treat hotel / AE / spot payloads as LGU just because municipality_id is present.
    if (type == 'establishment' ||
        type == 'hotel' ||
        type == 'ae' ||
        type == 'spot' ||
        q.containsKey('establishment_id') ||
        q.containsKey('establishmentId') ||
        q.containsKey('spot_id') ||
        q.containsKey('spotId')) {
      return null;
    }
    final midRaw = q['municipality_id'] ?? q['lgu_id'] ?? '';
    final id = normalizeMunicipalityId(midRaw);
    final isExplicitLgu = type == 'lgu' || type == 'municipality';
    final hasLguKey = q.containsKey('lgu_id');
    // Prefer explicit type=lgu. Allow municipality_id only when type is empty/absent
    // (legacy prints) and no competing typed payload keys above.
    if (id.isNotEmpty && (isExplicitLgu || hasLguKey || (type.isEmpty && q.containsKey('municipality_id')))) {
      final lat = double.tryParse((q['lat'] ?? '').trim());
      final lng = double.tryParse((q['lng'] ?? '').trim());
      if (lat != null && lng != null) {
        return LguQrPayload(municipalityId: id, anchorLat: lat, anchorLng: lng);
      }
      return LguQrPayload(municipalityId: id);
    }
  }

  const prefix = 'ATMOS-TRS-LGU:';
  if (s.startsWith(prefix)) {
    final rest = s.substring(prefix.length).trim();
    final parts = rest.split(':');
    if (parts.isEmpty) return null;
    final id = normalizeMunicipalityId(parts.first.trim());
    if (id.isEmpty) return null;
    if (parts.length >= 3) {
      final lat = double.tryParse(parts[1].trim());
      final lng = double.tryParse(parts[2].trim());
      if (lat != null && lng != null) {
        return LguQrPayload(municipalityId: id, anchorLat: lat, anchorLng: lng);
      }
    }
    return LguQrPayload(municipalityId: id);
  }
  // Avoid matching "establishment" strings that merely contain "LGU:" substring noise.
  if (s.toUpperCase().contains('ATMOS-TRS-EST:') ||
      s.toUpperCase().contains('TYPE=ESTABLISHMENT')) {
    return null;
  }
  final m = RegExp(r'(?:^|[\s/])LGU:\s*', caseSensitive: false).firstMatch(s);
  if (m != null) {
    final rest = s.substring(m.end).trim();
    final parts = rest.split(':');
    if (parts.isEmpty) return null;
    final id = normalizeMunicipalityId(parts.first.trim());
    if (id.isEmpty) return null;
    if (parts.length >= 3) {
      final lat = double.tryParse(parts[1].trim());
      final lng = double.tryParse(parts[2].trim());
      if (lat != null && lng != null) {
        return LguQrPayload(municipalityId: id, anchorLat: lat, anchorLng: lng);
      }
    }
    return LguQrPayload(municipalityId: id);
  }
  return null;
}

/// Returns canonical municipality id if [raw] is an LGU QR, else null.
/// Accepts `ATMOS-TRS-LGU:id` and variants with spaces (e.g. printed as `ATMOS TRS LGU:id`).
String? parseLguMunicipalityId(String raw) => parseLguQrPayload(raw)?.municipalityId;

/// Parses a scanned QR payload.
/// Returns (municipalityId, spotId) if format is ATMOS-TRS-SPOT:municipalityId:spotId.
/// Otherwise returns (null, raw) so caller can look up spot by doc id (e.g. oroquieta_plaza).
({String? municipalityId, String spotId}) parseSpotQrPayload(String raw) {
  final s = raw.trim();
  if (s.startsWith('ATMOS-TRS-SPOT:')) {
    final parts = s.split(':');
    if (parts.length >= 3) {
      return (municipalityId: parts[1].trim(), spotId: parts.sublist(2).join(':').trim());
    }
  }
  return (municipalityId: null, spotId: s);
}

/// Deep-link QR payload, e.g. `https://myapp.com/checkin?spot_id=oroquieta_plaza`.
String? extractSpotIdFromCheckInDeepLink(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return null;
  final q = mergedLaunchQueryParameters(uri);
  final id = q['spot_id'] ?? q['spotId'];
  return id != null && id.isNotEmpty ? id : null;
}

/// Parsed establishment (hotel / AE) QR.
class EstablishmentQrPayload {
  const EstablishmentQrPayload({
    required this.establishmentId,
    this.municipalityId,
    this.businessName,
  });

  final String establishmentId;
  final String? municipalityId;
  final String? businessName;
}

/// Public URL / payload for an establishment stay QR.
String establishmentQrData(
  String establishmentId, {
  String? municipalityId,
  String? businessName,
}) {
  final eid = establishmentId.trim();
  final params = <String, String>{
    'type': 'establishment',
    'establishment_id': eid,
  };
  final mid = (municipalityId ?? '').trim();
  if (mid.isNotEmpty) {
    params['municipality_id'] = normalizeMunicipalityId(mid);
  }
  final name = (businessName ?? '').trim();
  if (name.isNotEmpty) {
    params['name'] = name;
  }
  return Uri.parse(_kPublicCheckInBaseUrl)
      .replace(queryParameters: params)
      .toString();
}

/// Parses establishment QR (URL `type=establishment` or `ATMOS-TRS-EST:…`).
EstablishmentQrPayload? parseEstablishmentQrPayload(String raw) {
  final s = raw.trim();
  final uri = Uri.tryParse(s);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    final q = mergedLaunchQueryParameters(uri);
    final type = (q['type'] ?? '').trim().toLowerCase();
    final eid = (q['establishment_id'] ?? q['establishmentId'] ?? '').trim();
    if (eid.isNotEmpty &&
        (type == 'establishment' ||
            type == 'hotel' ||
            type == 'ae' ||
            q.containsKey('establishment_id') ||
            q.containsKey('establishmentId'))) {
      final midRaw = q['municipality_id'] ?? q['municipalityId'] ?? '';
      final mid = midRaw.trim().isNotEmpty
          ? normalizeMunicipalityId(midRaw)
          : null;
      final name = (q['name'] ?? q['business_name'] ?? '').trim();
      return EstablishmentQrPayload(
        establishmentId: eid,
        municipalityId: mid,
        businessName: name.isEmpty ? null : name,
      );
    }
  }

  const prefix = 'ATMOS-TRS-EST:';
  if (s.startsWith(prefix)) {
    final rest = s.substring(prefix.length).trim();
    final parts = rest.split(':');
    if (parts.isEmpty) return null;
    if (parts.length >= 2) {
      final mid = normalizeMunicipalityId(parts.first.trim());
      final eid = parts.sublist(1).join(':').trim();
      if (eid.isEmpty) return null;
      return EstablishmentQrPayload(
        establishmentId: eid,
        municipalityId: mid.isEmpty ? null : mid,
      );
    }
    final eid = parts.first.trim();
    if (eid.isEmpty) return null;
    return EstablishmentQrPayload(establishmentId: eid);
  }
  return null;
}
