import 'dart:convert';
import 'dart:io';

import 'package:atmos_trs_system/data/ph_address_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Misamis Occidental stays first and is not the only province', () {
    final names = philippineSignupProvinceOrder(const [
      'Bukidnon',
      'Abra',
      'Zamboanga del Norte',
    ]);
    expect(names.first, 'Misamis Occidental');
    expect(names.last, 'Other');
    expect(names, contains('Bukidnon'));
    expect(names.indexOf('Abra'), lessThan(names.indexOf('Bukidnon')));
  });

  test('generated lists cover Bukidnon and leave Misamis Occidental in Dart', () {
    final file = File('assets/ph_address/cities_by_province.json');
    final rows = jsonDecode(file.readAsStringSync()) as List<dynamic>;
    final names = [
      for (final row in rows) (row as Map<String, dynamic>)['name'] as String,
    ];
    expect(names, isNot(contains('Misamis Occidental')));
    final bukidnon = rows.cast<Map<String, dynamic>>().firstWhere(
      (row) => row['name'] == 'Bukidnon',
    );
    final cities = (bukidnon['cities'] as List<dynamic>).cast<String>();
    expect(cities, contains('Malaybalay City'));

    final slug = bukidnon['slug'] as String;
    final barangays = jsonDecode(
      File('assets/ph_address/barangays/$slug.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect((barangays['Malaybalay City'] as List).isNotEmpty, isTrue);
  });
}
