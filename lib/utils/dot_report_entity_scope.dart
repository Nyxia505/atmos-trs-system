import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// What the DOT export panel is scoped to.
enum DotReportEntityKind {
  /// Whole LGU (municipal staff) or whole province (OPTACA / Governor).
  all,

  /// One tourist attraction / spot (VAR family).
  spot,

  /// All eligible tourist spots in one city/municipality (VAR family).
  municipalitySpots,

  /// One accommodation establishment (DAE family).
  establishment,
}

/// Selectable spot or establishment for form fill / download.
class DotReportEntityOption {
  const DotReportEntityOption({
    required this.id,
    required this.name,
    required this.kind,
    this.municipalityId = '',
    this.municipalityName = '',
  });

  final String id;
  final String name;
  final DotReportEntityKind kind;
  final String municipalityId;
  final String municipalityName;

  String get dropdownLabel {
    final mun = municipalityName.trim().isNotEmpty
        ? municipalityName.trim()
        : (municipalityId.trim().isNotEmpty ? municipalityId.trim() : '');
    if (mun.isEmpty) return name;
    return '$name · $mun';
  }
}

/// Filters check-ins for spot- or municipality-specific DOT forms.
abstract final class DotReportEntityScope {
  static bool checkInMatchesSpot(
    Map<String, dynamic> checkIn, {
    required String spotId,
    required String spotName,
  }) {
    final id = (checkIn['spotId'] ??
            checkIn['spot_id'] ??
            checkIn['attractionId'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    final targetId = spotId.trim().toLowerCase();
    if (targetId.isNotEmpty && id == targetId) return true;

    final name = (checkIn['spot_name'] ??
            checkIn['spotName'] ??
            checkIn['attractionName'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    final targetName = spotName.trim().toLowerCase();
    if (targetName.isNotEmpty && name == targetName) return true;
    return false;
  }

  static List<Map<String, dynamic>> filterCheckInsForSpot(
    List<Map<String, dynamic>> checkIns, {
    required String spotId,
    required String spotName,
  }) {
    return [
      for (final c in checkIns)
        if (checkInMatchesSpot(c, spotId: spotId, spotName: spotName)) c,
    ];
  }

  /// Keeps check-ins that match any of [spotIds] / [spotNames] (case-insensitive).
  /// Deduplicates by check-in `id` when present so merged fetches cannot double-count.
  static List<Map<String, dynamic>> filterCheckInsForSpots(
    List<Map<String, dynamic>> checkIns, {
    required Iterable<String> spotIds,
    required Iterable<String> spotNames,
  }) {
    final ids = {
      for (final id in spotIds)
        if (id.trim().isNotEmpty) id.trim().toLowerCase(),
    };
    final names = {
      for (final n in spotNames)
        if (n.trim().isNotEmpty) n.trim().toLowerCase(),
    };
    if (ids.isEmpty && names.isEmpty) return const [];

    final out = <Map<String, dynamic>>[];
    final seenIds = <String>{};
    for (final c in checkIns) {
      final cid = (c['id'] ?? '').toString().trim();
      if (cid.isNotEmpty && !seenIds.add(cid)) continue;

      final spotId = (c['spotId'] ??
              c['spot_id'] ??
              c['attractionId'] ??
              '')
          .toString()
          .trim()
          .toLowerCase();
      if (spotId.isNotEmpty && ids.contains(spotId)) {
        out.add(c);
        continue;
      }
      final spotName = (c['spot_name'] ??
              c['spotName'] ??
              c['attractionName'] ??
              '')
          .toString()
          .trim()
          .toLowerCase();
      if (spotName.isNotEmpty && names.contains(spotName)) {
        out.add(c);
      }
    }
    return out;
  }

  static String _displayName(String municipalityId) {
    final id = normalizeMunicipalityId(municipalityId);
    for (final m in getMisamisOccidentalMunicipalities()) {
      if (normalizeMunicipalityId(m.id) == id) return m.name;
    }
    return id;
  }

  static List<Map<String, dynamic>> filterCheckInsForMunicipality(
    List<Map<String, dynamic>> checkIns, {
    required String municipalityId,
  }) {
    final mid = normalizeMunicipalityId(municipalityId);
    if (mid.isEmpty) return checkIns;
    final aliases = municipalityIdsForQuery(mid).map((e) => e.toLowerCase()).toSet();
    final display = _displayName(mid).toLowerCase();
    return [
      for (final c in checkIns)
        if (_checkInInMunicipality(c, aliases, display)) c,
    ];
  }

  static bool _checkInInMunicipality(
    Map<String, dynamic> c,
    Set<String> aliases,
    String displayName,
  ) {
    final id = normalizeMunicipalityId(
      (c['municipalityId'] ?? c['lguId'] ?? '').toString(),
    );
    if (id.isNotEmpty && aliases.contains(id)) return true;
    final mun = (c['municipality'] ?? '').toString().trim().toLowerCase();
    if (displayName.isNotEmpty && mun == displayName) return true;
    return false;
  }

  static String _safeSlugPart(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  static String slugFor({
    required String baseSlug,
    required DotReportEntityKind kind,
    String? entityId,
    String? municipalityId,
  }) {
    final base = baseSlug.trim().isEmpty ? 'scope' : baseSlug.trim();
    if (kind == DotReportEntityKind.municipalitySpots) {
      final mun = _safeSlugPart(municipalityId ?? '');
      if (mun.isEmpty) return '${base}_mun_spots';
      return '${base}_mun_spots_$mun';
    }
    if (kind == DotReportEntityKind.all ||
        entityId == null ||
        entityId.trim().isEmpty) {
      return base;
    }
    final safe = _safeSlugPart(entityId);
    final prefix = kind == DotReportEntityKind.spot ? 'spot' : 'ae';
    return '${base}_${prefix}_$safe';
  }

  static String labelFor({
    required String baseLabel,
    required DotReportEntityKind kind,
    DotReportEntityOption? entity,
    String? municipalityName,
  }) {
    if (kind == DotReportEntityKind.municipalitySpots) {
      final mun = (municipalityName ?? '').trim();
      if (mun.isEmpty) return 'All tourist spots · $baseLabel';
      return 'All tourist spots: $mun · $baseLabel';
    }
    if (kind == DotReportEntityKind.all || entity == null) return baseLabel;
    final kindLabel =
        kind == DotReportEntityKind.spot ? 'Spot' : 'Establishment';
    return '$kindLabel: ${entity.name} · $baseLabel';
  }

  /// Display name for a Misamis Occidental municipality id.
  static String municipalityDisplayName(String municipalityId) {
    return _displayName(municipalityId);
  }
}
