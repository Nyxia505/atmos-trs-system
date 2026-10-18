import 'dart:convert';

import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';

/// One place inside an origin bin, with its own male and female counts.
class OriginPlaceCount {
  const OriginPlaceCount({
    required this.place,
    this.male = 0,
    this.female = 0,
  });

  final String place;
  final int male;
  final int female;

  int get total => male + female;

  Map<String, dynamic> toMap() => {
        'place': place.trim(),
        'male': male,
        'female': female,
      };

  factory OriginPlaceCount.fromMap(Map<String, dynamic> m) {
    return OriginPlaceCount(
      place: m['place']?.toString().trim() ?? '',
      male: _n(m['male']),
      female: _n(m['female']),
    );
  }
}

/// Saved residence split for one QR visit (or for companions only).
///
/// Bins are mutually exclusive. This Municipality is the spot's municipality.
/// This Province is other cities and towns in Misamis Occidental.
class VisitOriginBreakdown {
  const VisitOriginBreakdown({
    required this.spotMunicipality,
    this.spotProvince = 'Misamis Occidental',
    this.thisMunicipalityMale = 0,
    this.thisMunicipalityFemale = 0,
    this.thisProvince = const [],
    this.otherProvinces = const [],
    this.foreign = const [],
  });

  final String spotMunicipality;
  final String spotProvince;
  final int thisMunicipalityMale;
  final int thisMunicipalityFemale;
  final List<OriginPlaceCount> thisProvince;
  final List<OriginPlaceCount> otherProvinces;
  final List<OriginPlaceCount> foreign;

  int get thisMunicipalityTotal =>
      thisMunicipalityMale + thisMunicipalityFemale;

  int get male =>
      thisMunicipalityMale +
      _sum((p) => p.male, thisProvince) +
      _sum((p) => p.male, otherProvinces) +
      _sum((p) => p.male, foreign);

  int get female =>
      thisMunicipalityFemale +
      _sum((p) => p.female, thisProvince) +
      _sum((p) => p.female, otherProvinces) +
      _sum((p) => p.female, foreign);

  int get total => male + female;

  int get domestic =>
      thisMunicipalityTotal +
      _sum((p) => p.total, thisProvince) +
      _sum((p) => p.total, otherProvinces);

  int get foreignTotal => _sum((p) => p.total, foreign);

  bool get isEmpty => total == 0;

  /// Places the user must name before check-in.
  String? validate({
    required int partySize,
    required int maleCount,
    required int femaleCount,
  }) {
    if (partySize == 0) {
      return isEmpty ? null : 'Origin counts must be 0 when party size is 0.';
    }
    if (total != partySize) {
      return 'Origin male + female ($total) must equal party size ($partySize).';
    }
    if (male != maleCount || female != femaleCount) {
      return 'Origin male ($male) and female ($female) must match the party '
          'counts ($maleCount male, $femaleCount female).';
    }
    final spot = _norm(spotMunicipality);
    for (final row in thisProvince) {
      if (row.total == 0) continue;
      if (row.place.trim().isEmpty) {
        return 'Choose the Misamis Occidental city or town for This Province.';
      }
      if (_norm(row.place) == spot) {
        return '${row.place} is this municipality. Count those visitors under '
            'This Municipality, not This Province.';
      }
    }
    for (final row in otherProvinces) {
      if (row.total == 0) continue;
      if (row.place.trim().isEmpty) {
        return 'Enter the province for Other Philippine Provinces.';
      }
      if (_isMisOcc(row.place)) {
        return '${row.place} is in Misamis Occidental. Use This Municipality '
            'or This Province.';
      }
    }
    for (final row in foreign) {
      if (row.total == 0) continue;
      if (row.place.trim().isEmpty) {
        return 'Enter the country for Foreign Residents.';
      }
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
        'spotMunicipality': spotMunicipality.trim(),
        'spotProvince': spotProvince.trim(),
        'thisMunicipality': {
          'male': thisMunicipalityMale,
          'female': thisMunicipalityFemale,
        },
        'thisProvince': [for (final p in thisProvince) p.toMap()],
        'otherProvinces': [for (final p in otherProvinces) p.toMap()],
        'foreign': [for (final p in foreign) p.toMap()],
      };

  String toJson() => jsonEncode(toMap());

  factory VisitOriginBreakdown.fromMap(Map<String, dynamic> m) {
    List<OriginPlaceCount> list(String key) {
      final raw = m[key];
      if (raw is! List) return const [];
      return [
        for (final item in raw)
          if (item is Map) OriginPlaceCount.fromMap(Map<String, dynamic>.from(item)),
      ];
    }

    final muni = m['thisMunicipality'];
    final muniMap = muni is Map ? Map<String, dynamic>.from(muni) : const {};
    return VisitOriginBreakdown(
      spotMunicipality: m['spotMunicipality']?.toString() ?? '',
      spotProvince: (m['spotProvince']?.toString().trim().isNotEmpty ?? false)
          ? m['spotProvince'].toString()
          : 'Misamis Occidental',
      thisMunicipalityMale: _n(muniMap['male']),
      thisMunicipalityFemale: _n(muniMap['female']),
      thisProvince: list('thisProvince'),
      otherProvinces: list('otherProvinces'),
      foreign: list('foreign'),
    );
  }

  static VisitOriginBreakdown? tryParse(Object? raw) {
    if (raw is Map) {
      return VisitOriginBreakdown.fromMap(Map<String, dynamic>.from(raw));
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return VisitOriginBreakdown.fromMap(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {}
    }
    return null;
  }

  /// Puts the signed-in tourist in the one bin that matches their profile.
  factory VisitOriginBreakdown.prefill({
    required String spotMunicipality,
    required Map<String, dynamic> profile,
  }) {
    final sex = (profile['sex']?.toString() ?? '').trim().toLowerCase();
    final male = sex.startsWith('m') ? 1 : 0;
    final female = sex.startsWith('f') ? 1 : 0;
    final empty = VisitOriginBreakdown(spotMunicipality: spotMunicipality);
    if (male + female != 1) return empty;

    final localOrForeign = profile['localOrForeign']?.toString().trim() ?? '';
    final country = profile['country']?.toString().trim() ?? '';
    final isForeign = localOrForeign.toLowerCase() == 'foreign' ||
        (country.isNotEmpty &&
            !_norm(country).contains('philippine') &&
            _norm(country) != 'ph' &&
            localOrForeign.toLowerCase() != 'local' &&
            profile['isLocal'] != true);
    if (isForeign) {
      final label = country.isNotEmpty
          ? country
          : (profile['nationality']?.toString().trim() ?? '');
      if (label.isEmpty) return empty;
      return VisitOriginBreakdown(
        spotMunicipality: spotMunicipality,
        foreign: [OriginPlaceCount(place: label, male: male, female: female)],
      );
    }

    final city = profile['city']?.toString().trim() ?? '';
    final province = profile['province']?.toString().trim() ?? '';
    if (_samePlace(city, spotMunicipality)) {
      return VisitOriginBreakdown(
        spotMunicipality: spotMunicipality,
        thisMunicipalityMale: male,
        thisMunicipalityFemale: female,
      );
    }
    if (_isMisOcc(province) || _knownMisOccCity(city)) {
      final place = city.isNotEmpty ? city : province;
      if (place.isEmpty || _samePlace(place, spotMunicipality)) {
        return VisitOriginBreakdown(
          spotMunicipality: spotMunicipality,
          thisMunicipalityMale: male,
          thisMunicipalityFemale: female,
        );
      }
      return VisitOriginBreakdown(
        spotMunicipality: spotMunicipality,
        thisProvince: [
          OriginPlaceCount(place: place, male: male, female: female),
        ],
      );
    }
    if (province.isNotEmpty) {
      return VisitOriginBreakdown(
        spotMunicipality: spotMunicipality,
        otherProvinces: [
          OriginPlaceCount(place: province, male: male, female: female),
        ],
      );
    }
    return empty;
  }
}

int _n(Object? v) {
  if (v is int) return v < 0 ? 0 : v;
  if (v is num) return v < 0 ? 0 : v.round();
  if (v is String) {
    final n = int.tryParse(v.trim());
    return n == null || n < 0 ? 0 : n;
  }
  return 0;
}

int _sum(int Function(OriginPlaceCount) pick, List<OriginPlaceCount> rows) {
  var n = 0;
  for (final row in rows) {
    n += pick(row);
  }
  return n;
}

String _norm(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(' city', '')
    .replaceAll(' municipality', '');

bool _samePlace(String a, String b) {
  final x = _norm(a);
  final y = _norm(b);
  if (x.isEmpty || y.isEmpty) return false;
  return x == y || x.contains(y) || y.contains(x);
}

bool _isMisOcc(String province) {
  final p = _norm(province);
  return p.contains('misamis occidental');
}

bool _knownMisOccCity(String city) {
  final c = _norm(city);
  if (c.isEmpty) return false;
  for (final m in getMisamisOccidentalMunicipalities()) {
    if (_norm(m.name) == c) return true;
  }
  return false;
}
