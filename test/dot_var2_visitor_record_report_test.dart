import 'package:flutter_test/flutter_test.dart';
import 'package:atmos_trs_system/utils/dot_var2_visitor_record_report.dart';

void main() {
  group('buildDotVar2VisitorRecordReport', () {
    final catalog = [
      const DotVar2SpotCatalogEntry(
        spotId: 'st_john',
        name: 'St. John Church',
        dotAttractionCode: '202',
      ),
      const DotVar2SpotCatalogEntry(
        spotId: 'sperm_sandbar',
        name: 'Sperm Sandbar',
        dotAttractionCode: '108',
      ),
    ];

    test('classifies sex and residence into VAR 2 columns', () {
      final result = buildDotVar2VisitorRecordReport(
        checkIns: [
          {
            'spotId': 'st_john',
            'spot_name': 'St. John Church',
            'touristProfile': {
              'sex': 'Male',
              'city': 'Jimenez',
              'province': 'Misamis Occidental',
              'country': 'Philippines',
              'isLocal': true,
              'localOrForeign': 'Local',
            },
          },
          {
            'spotId': 'st_john',
            'spot_name': 'St. John Church',
            'touristProfile': {
              'sex': 'Female',
              'city': 'Oroquieta City',
              'province': 'Misamis Occidental',
              'country': 'Philippines',
              'isLocal': true,
            },
          },
          {
            'spotId': 'sperm_sandbar',
            'spot_name': 'Sperm Sandbar',
            'touristProfile': {
              'sex': 'Male',
              'city': 'Cebu City',
              'province': 'Cebu',
              'country': 'Philippines',
              'isLocal': true,
            },
          },
          {
            'spotId': 'sperm_sandbar',
            'spot_name': 'Sperm Sandbar',
            'touristProfile': {
              'sex': 'Female',
              'country': 'Japan',
              'localOrForeign': 'Foreign',
            },
          },
          {
            'spotId': 'st_john',
            'spot_name': 'St. John Church',
          },
        ],
        catalogSpots: catalog,
        municipalityName: 'Jimenez, Misamis Occidental',
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 31),
      );

      expect(result.monthYearLabel, 'Mar-26');
      expect(result.checkInsProcessed, 5);

      final church = result.rows.firstWhere((r) => r.spotId == 'st_john');
      expect(church.thisMunicipality.male, 1);
      expect(church.thisProvince.female, 1);
      expect(church.grandTotal.total, 3);

      final sandbar = result.rows.firstWhere((r) => r.spotId == 'sperm_sandbar');
      expect(sandbar.otherProvince.male, 1);
      expect(sandbar.foreign.female, 1);
      expect(sandbar.grandTotal.total, 2);

      expect(result.footerTotals.grandTotal.total, 5);
      expect(result.csv, contains('St. John Church'));
      expect(result.csv, contains('Total of this Month ****'));
      expect(result.xlsxBytes.isNotEmpty, isTrue);
    });

    test('includes zero-visit catalog spots', () {
      final result = buildDotVar2VisitorRecordReport(
        checkIns: const [],
        catalogSpots: catalog,
        municipalityName: 'Jimenez, Misamis Occidental',
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 31),
      );

      expect(result.rows.length, 2);
      expect(result.footerTotals.grandTotal.total, 0);
    });
  });

  group('classifyVar2Residence', () {
    test('detects foreign visitors', () {
      expect(
        classifyVar2Residence(
          profile: {'country': 'Japan', 'localOrForeign': 'Foreign'},
          reportingMunicipalityName: 'Jimenez, Misamis Occidental',
        ),
        Var2ResidenceBucket.foreign,
      );
    });

    test('detects this municipality', () {
      expect(
        classifyVar2Residence(
          profile: {
            'city': 'Jimenez',
            'province': 'Misamis Occidental',
            'country': 'Philippines',
          },
          reportingMunicipalityName: 'Jimenez, Misamis Occidental',
        ),
        Var2ResidenceBucket.thisMunicipality,
      );
    });
  });
}
