import 'package:atmos_trs_system/utils/provincial_report_builder.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildMunicipalityCheckInSummary groups by municipality', () {
    final checkIns = [
      {
        'municipalityId': 'oroquieta',
        'userId': 'u1',
        'timestamp': Timestamp.fromDate(DateTime(2026, 3, 1)),
      },
      {
        'municipalityId': 'oroquieta',
        'userId': 'u2',
        'timestamp': Timestamp.fromDate(DateTime(2026, 3, 2)),
      },
      {
        'municipalityId': 'ozamiz',
        'userId': 'u1',
        'timestamp': Timestamp.fromDate(DateTime(2026, 3, 3)),
      },
    ];

    final result = buildMunicipalityCheckInSummary(checkIns: checkIns);

    expect(result.textSummary, contains('Oroquieta City'));
    expect(result.textSummary, contains('Ozamis City'));
    expect(result.textSummary, contains('GRAND TOTAL: 3 check-ins'));
    expect(result.csv, contains('Oroquieta City,2,2'));
  });

  test('buildProvincialAtmosReport includes provincial scope', () {
    final built = buildProvincialAtmosReport(
      allCheckIns: const [],
      tourists: const [],
      spots: const [],
      activeSpots: 0,
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 1, 31),
      reportType: 'Summary by Municipality',
      period: 'monthly',
    );

    expect(built.reportText, contains('PROVINCIAL REPORT'));
    expect(built.reportText, contains('Misamis Occidental'));
    expect(built.municipalityCsv, isNotNull);
  });
}
