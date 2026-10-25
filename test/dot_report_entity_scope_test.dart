import 'package:flutter_test/flutter_test.dart';

import 'package:atmos_trs_system/utils/dot_report_entity_scope.dart';
import 'package:atmos_trs_system/utils/dot_var2_visitor_record_report.dart';

void main() {
  group('DotReportEntityScope.filterCheckInsForSpots', () {
    test('matches by spotId or name and dedupes by check-in id', () {
      final checkIns = [
        {'id': 'c1', 'spotId': 'spot_a', 'spot_name': 'Alpha Falls'},
        {'id': 'c1', 'spotId': 'spot_a', 'spot_name': 'Alpha Falls'}, // dup
        {'id': 'c2', 'spotId': 'spot_b', 'spot_name': 'Beta Beach'},
        {'id': 'c3', 'spotId': 'other', 'spot_name': 'Elsewhere'},
        {'id': 'c4', 'spot_name': 'Alpha Falls'}, // name-only match
      ];

      final filtered = DotReportEntityScope.filterCheckInsForSpots(
        checkIns,
        spotIds: ['spot_a', 'spot_b'],
        spotNames: ['Alpha Falls', 'Beta Beach'],
      );

      expect(filtered.map((c) => c['id']), ['c1', 'c2', 'c4']);
    });

    test('returns empty when no spot ids or names', () {
      final filtered = DotReportEntityScope.filterCheckInsForSpots(
        [
          {'id': 'c1', 'spotId': 'spot_a'},
        ],
        spotIds: const [],
        spotNames: const [],
      );
      expect(filtered, isEmpty);
    });
  });

  group('DotVar2SpotCatalogEntry eligibility', () {
    test('inactive/closed spots are not eligible', () {
      expect(
        const DotVar2SpotCatalogEntry(
          spotId: '1',
          name: 'Closed Spot',
          status: 'inactive',
        ).isEligibleForVar2,
        isFalse,
      );
      expect(
        const DotVar2SpotCatalogEntry(
          spotId: '2',
          name: 'Open Spot',
          status: 'Active',
        ).isEligibleForVar2,
        isTrue,
      );
      expect(
        const DotVar2SpotCatalogEntry(
          spotId: '3',
          name: 'No status',
        ).isEligibleForVar2,
        isTrue,
      );
    });
  });

  group('municipalitySpots slug/label', () {
    test('slug and label include municipality', () {
      expect(
        DotReportEntityScope.slugFor(
          baseSlug: 'misamis_occidental_optaca',
          kind: DotReportEntityKind.municipalitySpots,
          municipalityId: 'oroquieta',
        ),
        'misamis_occidental_optaca_mun_spots_oroquieta',
      );
      expect(
        DotReportEntityScope.labelFor(
          baseLabel: 'Misamis Occidental (OPTACA)',
          kind: DotReportEntityKind.municipalitySpots,
          municipalityName: 'Oroquieta City',
        ),
        'All tourist spots: Oroquieta City · Misamis Occidental (OPTACA)',
      );
    });
  });

  group('filterCheckInsForMunicipality', () {
    test('keeps only Oroquieta check-ins', () {
      final filtered = DotReportEntityScope.filterCheckInsForMunicipality(
        [
          {'id': '1', 'municipalityId': 'oroquieta', 'spotId': 'a'},
          {'id': '2', 'municipalityId': 'ozamiz', 'spotId': 'b'},
          {'id': '3', 'municipality': 'Oroquieta City', 'spotId': 'c'},
        ],
        municipalityId: 'oroquieta',
      );
      expect(filtered.map((c) => c['id']), ['1', '3']);
    });
  });
}
