import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Public URL opened by device cameras when the app is not installed.
/// Use hash route so Firebase Hosting always lands on the web app's landing page.
const String _kPublicCheckInBaseUrl = 'https://atmos-trs-system.web.app/#/landing';

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

/// Helper for generating unique QR payloads per tourist spot.
/// Scanner expects format: ATMOS-TRS-SPOT:municipalityId:spotId
String spotQrData(String municipalityId, String spotId) {
  final id = normalizeMunicipalityId(municipalityId.trim());
  final sid = spotId.trim();
  // Use URL payload so phone camera apps can open web landing/check-in without the app.
  return Uri.parse(_kPublicCheckInBaseUrl).replace(queryParameters: {
    'type': 'spot',
    'municipality_id': id,
    'spot_id': sid,
  }).toString();
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
LguQrPayload? parseLguQrPayload(String raw) {
  final s = raw.trim();
  final uri = Uri.tryParse(s);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    final q = uri.queryParameters;
    final type = (q['type'] ?? '').trim().toLowerCase();
    final midRaw = q['municipality_id'] ?? q['lgu_id'] ?? '';
    final id = normalizeMunicipalityId(midRaw);
    if (id.isNotEmpty && (type == 'lgu' || q.containsKey('municipality_id') || q.containsKey('lgu_id'))) {
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
  final m = RegExp(r'LGU:\s*', caseSensitive: false).firstMatch(s);
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
  final id = uri.queryParameters['spot_id'] ?? uri.queryParameters['spotId'];
  return id != null && id.isNotEmpty ? id : null;
}
