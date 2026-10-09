import 'package:flutter_test/flutter_test.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
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

  group('aggregateDae3FromAeReports', () {
    test('one row per AE-month from register totals; empty months skipped', () {
      final rows = aggregateDae3FromAeReports([
        const AeMonthlyReport(
          id: 'h_2026_09',
          aeId: 'h',
          year: 2026,
          month: 9,
          aeName: 'Hoten Hotel',
          municipality: 'Oroquieta City',
          totalRooms: 20,
          aeType: 'Hotel',
          classificationCode: 'HTL',
          totals: AeMonthTotals(
            checkIns: 3,
            guestNights: 8,
            roomsOccupied: 5,
            rowCount: 5,
          ),
        ),
        const AeMonthlyReport(id: 'h_2026_10', aeId: 'h', year: 2026, month: 10, aeName: 'Hoten Hotel'),
      ]);

      expect(rows.length, 1);
      final hoten = rows.single;
      expect(hoten.aeId, 'Hoten Hotel');
      expect(hoten.guestsCheckedIn, 3);
      expect(hoten.guestNights, 8);
      expect(hoten.roomsOccupied, 5);
      expect(hoten.typeClass, 'HTL');
      expect(hoten.roomsAvailable, 20);
      expect(hoten.occupancyPct!, closeTo(5 / (20 * 30) * 100, 1e-9));
      expect(hoten.fromRegister, isTrue);
    });

    test('preferring register falls back to check-ins when empty', () {
      final rows = aggregateDae3PreferringRegister(
        scopeLabel: 'Oroquieta City',
        reports: const [],
        checkIns: [
          {
            'municipality': 'Oroquieta City',
            'spot_name': 'City Plaza',
            'timestamp': DateTime(2026, 9, 10, 12),
          },
        ],
        parseCheckInTimestamp: (c) => c['timestamp'] as DateTime?,
      );
      expect(rows.single.aeId, 'City Plaza');
      expect(rows.single.fromRegister, isFalse);
    });
  });
}
