import 'package:atmos_trs_system/models/tourist_spot.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/tourist_spot_visibility.dart';

/// Shared tourist-spot counting for LGU / OPTACA / Governor / QR.
///
/// Canonical Active (bookable / published) status matches QR check-in:
/// empty, `active`, or `published` (case-insensitive).
enum SpotCountKind { total, active, inactive }

abstract final class TouristSpotMetrics {
  /// Same rule as [isTouristSpotActiveStatus] / QR check-in.
  static bool isActiveStatus(String? status) =>
      isTouristSpotActiveStatus(status);

  static bool isInactiveStatus(String? status) {
    final s = (status ?? '').trim().toLowerCase();
    return s == 'inactive' ||
        s == 'closed' ||
        s == 'draft' ||
        s == 'unpublished' ||
        s == 'rejected';
  }

  /// Prefer `municipalityId`, else exact name → MisOcc id.
  static String municipalityIdOf(Map<String, dynamic> row) {
    final mid = normalizeMunicipalityId(row['municipalityId']?.toString());
    if (mid.isNotEmpty && isMisamisOccidentalMunicipalityId(mid)) return mid;
    final fromName = getMunicipalityIdFromName(
      row['municipality']?.toString() ??
          row['municipalityName']?.toString() ??
          row['city']?.toString(),
    );
    return fromName;
  }

  static String municipalityIdOfSpot(TouristSpot spot) {
    final mid = normalizeMunicipalityId(
      spot.municipalityId.isNotEmpty ? spot.municipalityId : null,
    );
    if (mid.isNotEmpty && isMisamisOccidentalMunicipalityId(mid)) return mid;
    return getMunicipalityIdFromName(spot.municipality);
  }

  static Set<String> _municipalityAliases(String municipalityId) {
    final want = <String>{
      for (final id in municipalityIdsForQuery(municipalityId))
        if (normalizeMunicipalityId(id).isNotEmpty) normalizeMunicipalityId(id),
    };
    final single = normalizeMunicipalityId(municipalityId);
    if (single.isNotEmpty) want.add(single);
    return want;
  }

  static bool belongsToMunicipality(
    Map<String, dynamic> spot, {
    required String municipalityId,
  }) {
    final mid = municipalityIdOf(spot);
    return mid.isNotEmpty && _municipalityAliases(municipalityId).contains(mid);
  }

  static bool spotModelBelongsToMunicipality(
    TouristSpot spot, {
    required String municipalityId,
  }) {
    final mid = municipalityIdOfSpot(spot);
    return mid.isNotEmpty && _municipalityAliases(municipalityId).contains(mid);
  }

  static int countMaps(
    Iterable<Map<String, dynamic>> spots, {
    SpotCountKind kind = SpotCountKind.active,
    String? municipalityId,
  }) {
    var n = 0;
    for (final s in spots) {
      if (municipalityId != null &&
          municipalityId.isNotEmpty &&
          !belongsToMunicipality(s, municipalityId: municipalityId)) {
        continue;
      }
      final status = (s['status'] ?? s['Status'])?.toString();
      switch (kind) {
        case SpotCountKind.total:
          n++;
        case SpotCountKind.active:
          if (isActiveStatus(status)) n++;
        case SpotCountKind.inactive:
          if (!isActiveStatus(status)) n++;
      }
    }
    return n;
  }

  static int countModels(
    Iterable<TouristSpot> spots, {
    SpotCountKind kind = SpotCountKind.active,
    String? municipalityId,
  }) {
    var n = 0;
    for (final s in spots) {
      if (municipalityId != null &&
          municipalityId.isNotEmpty &&
          !spotModelBelongsToMunicipality(s, municipalityId: municipalityId)) {
        continue;
      }
      switch (kind) {
        case SpotCountKind.total:
          n++;
        case SpotCountKind.active:
          if (isActiveStatus(s.status)) n++;
        case SpotCountKind.inactive:
          if (!isActiveStatus(s.status)) n++;
      }
    }
    return n;
  }

  static ({int total, int active, int inactive}) breakdownMaps(
    Iterable<Map<String, dynamic>> spots, {
    String? municipalityId,
  }) {
    final total = countMaps(
      spots,
      kind: SpotCountKind.total,
      municipalityId: municipalityId,
    );
    final active = countMaps(
      spots,
      kind: SpotCountKind.active,
      municipalityId: municipalityId,
    );
    return (total: total, active: active, inactive: total - active);
  }

  static ({int total, int active, int inactive}) breakdownModels(
    Iterable<TouristSpot> spots, {
    String? municipalityId,
  }) {
    final total = countModels(
      spots,
      kind: SpotCountKind.total,
      municipalityId: municipalityId,
    );
    final active = countModels(
      spots,
      kind: SpotCountKind.active,
      municipalityId: municipalityId,
    );
    return (total: total, active: active, inactive: total - active);
  }

  /// Deduplicate by document id (prefers non-empty `id`).
  static List<Map<String, dynamic>> dedupeById(
    Iterable<Map<String, dynamic>> spots,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final s in spots) {
      final id = (s['id'] ?? s['spotId'] ?? '').toString().trim();
      if (id.isEmpty) continue;
      byId.putIfAbsent(id, () => s);
    }
    return byId.values.toList();
  }
}
