import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// What the DOT export panel is scoped to.
enum DotReportEntityKind {
  /// Whole LGU (municipal staff) or whole province (OPTACA / Governor).
  all,

  /// One tourist attraction / spot (VAR family).
  spot,

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

  static String slugFor({
    required String baseSlug,
    required DotReportEntityKind kind,
    String? entityId,
  }) {
    final base = baseSlug.trim().isEmpty ? 'scope' : baseSlug.trim();
    if (kind == DotReportEntityKind.all ||
        entityId == null ||
        entityId.trim().isEmpty) {
      return base;
    }
    final safe = entityId
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final prefix = kind == DotReportEntityKind.spot ? 'spot' : 'ae';
    return '${base}_${prefix}_$safe';
  }

  static String labelFor({
    required String baseLabel,
    required DotReportEntityKind kind,
    DotReportEntityOption? entity,
  }) {
    if (kind == DotReportEntityKind.all || entity == null) return baseLabel;
    final kindLabel =
        kind == DotReportEntityKind.spot ? 'Spot' : 'Establishment';
    return '$kindLabel: ${entity.name} · $baseLabel';
  }
}
