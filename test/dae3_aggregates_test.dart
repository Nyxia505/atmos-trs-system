import 'package:flutter_test/flutter_test.dart';
import 'package:atmos_trs_system/utils/dae3_aggregates.dart';

void main() {
  group('aggregateDae3FromCheckIns', () {
    test('counts guests per AE × month and excludes Google Form URLs', () {
      final rows = aggregateDae3FromCheckIns(
        scopeLabel: 'Oroquieta City',
        checkIns: [
          {
            'id': '1',
            'municipality': 'Oroquieta City',
            'spot_name': 'City Plaza',
            'timestamp': DateTime(2026, 9, 10, 12),
          },
          {
            'id': '2',
            'municipality': 'Oroquieta City',
            'spot_name': 'City Plaza',
            'timestamp': DateTime(2026, 9, 11, 12),
          },
          {
            'id': '3',
            'municipality': 'Oroquieta City',
            'spot_name':
                'https://docs.google.com/forms/d/1I3Al-cwgGMzewe0s728Wdq3oDesc7pHz93euYH7Ts/edit',
            'timestamp': DateTime(2026, 9, 12, 12),
          },
          {
            'id': '4',
            'municipality': 'Oroquieta City',
            'spot_name': 'LGU visit — Oroquieta City',
            'timestamp': DateTime(2026, 9, 13, 12),
          },
        ],
        parseTimestamp: (c) => c['timestamp'] as DateTime?,
      );

      expect(rows.length, 2);
      final plaza = rows.firstWhere((r) => r.aeId == 'City Plaza');
      expect(plaza.guestsCheckedIn, 2);
      expect(plaza.month, 9);
      expect(plaza.province, 'Misamis Occidental');
      expect(
        rows.any((r) => r.aeId.contains('docs.google.com')),
        isFalse,
      );
      expect(
        rows.any((r) => r.aeId.startsWith('LGU visit')),
        isTrue,
      );
    });
  });
}
