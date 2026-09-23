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

  group('aggregateDae3FromConfirmedStays', () {
    test('sums party, nights, rooms per AE × month', () {
      final rows = aggregateDae3FromConfirmedStays(
        scopeLabel: 'Oroquieta City',
        stayEvents: [
          {
            'status': 'confirmed',
            'municipality': 'Oroquieta City',
            'establishmentName': 'Hoten Hotel',
            'establishmentCategory': 'Hotel',
            'roomsAvailable': 20,
            'partySize': 2,
            'nightsStayed': 3,
            'roomsOccupied': 1,
            'timestamp': DateTime(2026, 9, 10, 12),
          },
          {
            'status': 'confirmed',
            'municipality': 'Oroquieta City',
            'establishmentName': 'Hoten Hotel',
            'establishmentCategory': 'Hotel',
            'roomsAvailable': 20,
            'partySize': 1,
            'nightsStayed': 2,
            'roomsOccupied': 1,
            'timestamp': DateTime(2026, 9, 12, 12),
          },
          {
            'status': 'pending',
            'municipality': 'Oroquieta City',
            'establishmentName': 'Hoten Hotel',
            'partySize': 9,
            'timestamp': DateTime(2026, 9, 11, 12),
          },
        ],
      );

      expect(rows.length, 1);
      final hoten = rows.single;
      expect(hoten.aeId, 'Hoten Hotel');
      expect(hoten.guestsCheckedIn, 3);
      expect(hoten.guestNights, 2 * 3 + 1 * 2);
      expect(hoten.roomsOccupied, 2);
      expect(hoten.typeClass, 'Hotel');
      expect(hoten.roomsAvailable, 20);
      expect(hoten.fromConfirmedStays, isTrue);
    });

    test('preferring stays falls back to check-ins when empty', () {
      final rows = aggregateDae3PreferringStays(
        scopeLabel: 'Oroquieta City',
        stayEvents: const [],
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
      expect(rows.single.fromConfirmedStays, isFalse);
    });
  });
}
