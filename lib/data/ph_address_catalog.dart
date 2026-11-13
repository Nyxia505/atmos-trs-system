import 'dart:convert';

import 'package:flutter/services.dart';

import 'package:atmos_trs_system/data/misamis_occidental_barangays.dart';

/// Province, city, and barangay lists for a Philippine residence.
///
/// Misamis Occidental keeps [kMisamisOccidentalSignupCities] and
/// [kMisamisOccidentalBarangaysByCity]. Every other province is loaded from
/// assets/ph_address, generated from the PSGC mirror.
class PhilippineAddressCatalog {
  PhilippineAddressCatalog._();

  static const misamisOccidental = 'Misamis Occidental';
  static const other = 'Other';

  static List<_PhProvinceRecord>? _provinces;
  static String? loadError;
  static Future<void>? _citiesLoad;
  static final Map<String, Map<String, List<String>>> _barangaysByProvince = {};

  static bool get citiesReady => _provinces != null;

  static Future<void> ensureCitiesLoaded() {
    return _citiesLoad ??= _loadCities();
  }

  static Future<void> _loadCities() async {
    try {
      final raw = await rootBundle.loadString(
        'assets/ph_address/cities_by_province.json',
      );
      final decoded = jsonDecode(raw) as List<dynamic>;
      _provinces = [
        for (final rawItem in decoded)
          _provinceRecord(rawItem as Map<String, dynamic>),
      ];
      loadError = null;
    } catch (e) {
      _provinces = const [];
      loadError = e.toString();
    }
  }

  /// Misamis Occidental first, then the other provinces A–Z, then Other.
  static List<String> signupProvinces() {
    return philippineSignupProvinceOrder(
      _provinces?.map((province) => province.name) ?? const <String>[],
    );
  }

  static List<String> citiesFor(String? province) {
    if (province == null || province == other) return const [];
    if (province == misamisOccidental) {
      return List<String>.from(kMisamisOccidentalSignupCities);
    }
    for (final record in _provinces ?? const <_PhProvinceRecord>[]) {
      if (record.name == province) return List<String>.from(record.cities);
    }
    return const [];
  }

  static Future<List<String>> barangaysFor(String province, String city) async {
    if (province == misamisOccidental) {
      return barangaysForMisamisOccidentalCity(city);
    }
    final byCity = await _barangaysForProvince(province);
    return List<String>.from(byCity[city] ?? const <String>[]);
  }

  static Future<Map<String, List<String>>> _barangaysForProvince(
    String province,
  ) async {
    final cached = _barangaysByProvince[province];
    if (cached != null) return cached;
    final record = _recordNamed(province);
    if (record == null) return const {};
    try {
      final raw = await rootBundle.loadString(
        'assets/ph_address/barangays/${record.slug}.json',
      );
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final map = <String, List<String>>{
        for (final entry in decoded.entries)
          entry.key: [
            for (final name in entry.value as List<dynamic>) name as String,
          ],
      };
      _barangaysByProvince[province] = map;
      return map;
    } catch (_) {
      return const {};
    }
  }

  static _PhProvinceRecord? _recordNamed(String province) {
    for (final record in _provinces ?? const <_PhProvinceRecord>[]) {
      if (record.name == province) return record;
    }
    return null;
  }
}

_PhProvinceRecord _provinceRecord(Map<String, dynamic> item) {
  return _PhProvinceRecord(
    name: item['name'] as String,
    slug: item['slug'] as String,
    cities: [
      for (final city in item['cities'] as List<dynamic>) city as String,
    ],
  );
}

/// [catalogNames] are provinces other than Misamis Occidental.
List<String> philippineSignupProvinceOrder(Iterable<String> catalogNames) {
  final rest = <String>{
    for (final name in catalogNames)
      if (name != PhilippineAddressCatalog.misamisOccidental &&
          name != PhilippineAddressCatalog.other &&
          name.trim().isNotEmpty)
        name.trim(),
  }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return [
    PhilippineAddressCatalog.misamisOccidental,
    ...rest,
    PhilippineAddressCatalog.other,
  ];
}

class _PhProvinceRecord {
  const _PhProvinceRecord({
    required this.name,
    required this.slug,
    required this.cities,
  });

  final String name;
  final String slug;
  final List<String> cities;
}
