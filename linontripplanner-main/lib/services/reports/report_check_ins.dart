import 'package:cloud_firestore/cloud_firestore.dart';

import '../../data.dart';
import '../../trip_planner_utils.dart' show matchMunicipalityByLocalityHint;

/// Normalization for QR check-in documents.
///
/// `qr_checkins` is written by several client versions, so every field is read
/// through a candidate-key list rather than a fixed schema. These helpers are
/// the single source of that tolerance — the admin dashboard tabs and the
/// Reports page both read check-ins through here.

/// Confirmed Firestore collection holding QR check-ins.
const String kQrCheckInsCollection = 'qr_checkins';

/// Merges nested payload maps up into the top level so a single key lookup
/// finds fields regardless of how deeply the writer nested them.
Map<String, dynamic> flattenCheckInRecord(Map<String, dynamic> raw) {
  final flat = <String, dynamic>{...raw};
  for (final nest in const [
    'checkIn',
    'check_in',
    'user',
    'profile',
    'tourist',
    'visitor',
    'data',
    'payload',
  ]) {
    final inner = raw[nest];
    if (inner is Map<String, dynamic>) {
      for (final e in inner.entries) {
        flat.putIfAbsent(e.key, () => e.value);
      }
    }
  }
  return flat;
}

/// First non-empty value among [keys], or `''`.
String checkInStringField(Map<String, dynamic> raw, List<String> keys) {
  final d = flattenCheckInRecord(raw);
  for (final key in keys) {
    final v = d[key];
    if (v == null) continue;
    final s = v.toString().trim();
    if (s.isNotEmpty) return s;
  }
  return '';
}

/// When the check-in happened, across `Timestamp`, `DateTime` and ISO strings.
DateTime? checkInDateTime(Map<String, dynamic> raw) {
  final d = flattenCheckInRecord(raw);
  for (final key in const [
    'checkInAt',
    'checkinAt',
    'visitAt',
    'createdAt',
    'timestamp',
    'timeStamp',
  ]) {
    final v = d[key];
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) {
      final parsed = DateTime.tryParse(v.trim());
      if (parsed != null) return parsed;
    }
  }
  return null;
}

/// Tourist spot named on the check-in, or `''`.
String checkInSpotName(Map<String, dynamic> raw) {
  return checkInStringField(raw, const [
    'spotName',
    'spot_name',
    'touristSpot',
    'tourist_spot',
    'spot',
    'placeName',
    'place_name',
    'attraction',
    'siteName',
  ]);
}

/// Tourist's display name, or `''`.
String checkInTouristName(Map<String, dynamic> raw) {
  return checkInStringField(raw, const [
    'touristName',
    'name',
    'fullName',
    'displayName',
  ]);
}

/// Stable per-person key used to count unique visitors rather than scans.
String checkInIdentity(Map<String, dynamic> raw, String fallbackDocId) {
  final id = checkInStringField(raw, const [
    'userId',
    'uid',
    'firebaseUid',
    'touristID',
    'touristId',
    'email',
    'phone',
    'name',
    'fullName',
  ]);
  return id.isEmpty ? 'doc:$fallbackDocId' : id.toLowerCase();
}

/// Resolves which municipality a check-in belongs to, falling back to the
/// municipality of the named tourist spot.
Municipality? municipalityFromCheckIn(Map<String, dynamic> raw) {
  final hint = checkInStringField(raw, const [
    'visitMunicipality',
    'visitedMunicipality',
    'municipalityName',
    'municipality_name',
    'municipality',
    'lgu',
    'LGU',
    'city',
    'cityName',
    'town',
    'barangay',
    'location',
    'locationName',
    'place',
    'destination',
  ]);
  var matched = matchMunicipalityByLocalityHint(hint);
  if (matched != null) return matched;

  final spotHint = checkInSpotName(raw);
  if (spotHint.isNotEmpty) {
    final lower = spotHint.toLowerCase();
    for (final spot in allSpots) {
      if (spot.name.toLowerCase() == lower ||
          (spot.firestoreDocId?.toLowerCase() == lower)) {
        for (final m in municipalities) {
          if (touristSpotBelongsToMunicipality(spot, m)) return m;
        }
        matched = matchMunicipalityByLocalityHint(spot.location);
        if (matched != null) return matched;
      }
    }
  }
  return null;
}

/// Visits per municipality from QR check-ins. Every LGU is present, so callers
/// can show zeroes rather than omitting quiet municipalities.
Map<String, int> visitsPerMunicipalityFromCheckIns(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final map = <String, int>{for (final m in municipalities) m.name: 0};
  for (final doc in docs) {
    final matched = municipalityFromCheckIn(doc.data());
    if (matched != null) {
      map[matched.name] = (map[matched.name] ?? 0) + 1;
    }
  }
  return map;
}

/// Visits per month (index 0 = January) from QR check-ins.
List<int> visitsPerMonthFromCheckIns(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final monthly = List<int>.filled(12, 0);
  for (final doc in docs) {
    final at = checkInDateTime(doc.data());
    if (at == null) continue;
    final m = at.month;
    if (m >= 1 && m <= 12) monthly[m - 1]++;
  }
  return monthly;
}

/// One check-in, read once so reports do not re-parse the raw map per metric.
class CheckInRecord {
  final String docId;
  final DateTime? at;
  final String touristName;
  final String identity;
  final String spotName;

  /// Resolved tourist spot, when the named spot exists in the catalog.
  final TouristSpot? spot;

  /// Resolved LGU name, or `''` when the check-in names no recognizable place.
  final String municipalityName;

  const CheckInRecord({
    required this.docId,
    required this.at,
    required this.touristName,
    required this.identity,
    required this.spotName,
    required this.spot,
    required this.municipalityName,
  });

  factory CheckInRecord.fromRaw(String docId, Map<String, dynamic> raw) {
    final spotName = checkInSpotName(raw);
    TouristSpot? spot;
    if (spotName.isNotEmpty) {
      final lower = spotName.toLowerCase();
      for (final s in allSpots) {
        if (s.name.toLowerCase() == lower ||
            s.firestoreDocId?.toLowerCase() == lower) {
          spot = s;
          break;
        }
      }
    }
    return CheckInRecord(
      docId: docId,
      at: checkInDateTime(raw),
      touristName: checkInTouristName(raw),
      identity: checkInIdentity(raw, docId),
      spotName: spotName.isNotEmpty ? spotName : (spot?.name ?? ''),
      spot: spot,
      municipalityName: municipalityFromCheckIn(raw)?.name ?? '',
    );
  }
}
