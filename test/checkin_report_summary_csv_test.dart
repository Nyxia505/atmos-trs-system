import 'package:flutter_test/flutter_test.dart';
import 'package:atmos_trs_system/utils/checkin_report_summary_csv.dart';

void main() {
  group('buildCheckInSummaryReport', () {
    List<Map<String, dynamic>> sampleCheckIns() => [
      {
        'spotId': 'oroquieta_city_plaza',
        'spot_name': 'Oroquieta City Plaza',
        'municipality': 'Oroquieta City',
        'userId': 'user_a',
        'timestamp': DateTime(2026, 1, 10, 12),
      },
      {
        'spotId': 'oroquieta_city_plaza',
        'spot_name': 'Oroquieta City Plaza',
        'municipality': 'Oroquieta City',
        'userId': 'user_b',
        'timestamp': DateTime(2026, 2, 5, 12),
      },
      {
        'spotId': 'el_triunfo_beach',
        'spot_name': 'El Triunfo Beach',
        'municipality': 'Oroquieta City',
        'userId': 'user_a',
        'timestamp': DateTime(2026, 1, 20, 12),
      },
    ];

    test('annual layout uses January–December with totals', () {
      final result = buildCheckInSummaryReport(
        checkIns: sampleCheckIns(),
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 12, 31),
        period: 'annual',
        parseTimestamp: (c) => c['timestamp'] as DateTime?,
      );

      expect(result.columnHeaders.first, 'January');
      expect(result.columnHeaders.last, 'December');
      expect(result.grandTotalCheckIns, 3);
      expect(result.csv, contains('GRAND TOTAL'));
      expect(result.csv, contains('oroquieta_city_plaza'));
      expect(result.csv, contains(',TOTAL'));
    });

    test('daily layout counts check-ins and unique visitors per spot', () {
      final result = buildCheckInSummaryReport(
        checkIns: [
          sampleCheckIns().first,
          {
            ...sampleCheckIns().first,
            'userId': 'user_b',
          },
        ],
        startDate: DateTime(2026, 1, 10),
        endDate: DateTime(2026, 1, 10),
        period: 'daily',
        parseTimestamp: (c) => c['timestamp'] as DateTime?,
      );

      expect(result.layoutKind, CheckInSummaryLayoutKind.daily);
      expect(result.csv, contains('Unique visitors'));
      expect(result.grandTotalCheckIns, 2);
    });

    test('weekly layout creates one column per day in range', () {
      final result = buildCheckInSummaryReport(
        checkIns: sampleCheckIns(),
        startDate: DateTime(2026, 1, 9),
        endDate: DateTime(2026, 1, 11),
        period: 'weekly',
        parseTimestamp: (c) => c['timestamp'] as DateTime?,
      );

      expect(result.columnHeaders.length, 3);
      expect(result.grandTotalCheckIns, 1);
    });
  });
}
