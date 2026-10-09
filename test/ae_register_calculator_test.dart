import 'package:flutter_test/flutter_test.dart';
import 'package:atmos_trs_system/config/dae_residence_catalog.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/utils/ae_register_calculator.dart';

/// Rows from the client's DOT_ET_DAE1Bv10c.xlsm sample (NAY MORENA, Jan 2024).
List<AeRegisterRow> _sample() => [
      AeRegisterRow(
        id: 'a',
        date: DateTime(2024, 1, 1),
        roomNo: '1',
        residence: "Cote D'Ivoire",
        guests: 1,
        female: 1,
        rate: 950,
        chargesA: 200,
        chargesB: 300,
      ),
      AeRegisterRow(
        id: 'b',
        date: DateTime(2024, 1, 1),
        roomNo: '4',
        residence: 'Cyprus',
        guests: 2,
        female: 1,
        male: 1,
        rate: 950,
        chargesA: 200,
        chargesB: 300,
      ),
      AeRegisterRow(
        id: 'c',
        date: DateTime(2024, 1, 15),
        roomNo: '2',
        residence: 'United Kingdom',
        guests: 2,
        female: 1,
        male: 1,
        rate: 950,
        chargesA: 200,
        chargesB: 300,
      ),
      AeRegisterRow(
        id: 'd',
        date: DateTime(2024, 1, 11),
        roomNo: '4',
        residence: 'Uruguay',
        guests: 2,
        female: 1,
        male: 1,
        checkedInDay: true,
        rate: 950,
        chargesA: 200,
        chargesB: 300,
      ),
    ];

void main() {
  group('AeRegisterCalculator — DAE-1B sample', () {
    final t = AeRegisterCalculator.totals(
      rows: _sample(),
      year: 2024,
      month: 1,
      totalRooms: 5,
      prevMonthLastDayGuests: 15,
    );

    test('DAE2_Auto items 5–8, 17, 18 match the workbook', () {
      expect(t.checkIns, 2);
      expect(t.guestNights, 7);
      expect(t.roomsOccupied, 4);
      expect((t.occupancyRate! * 100).toStringAsFixed(2), '2.58');
      expect(t.alos, 3.5);
      expect(t.avgPersonsPerRoom, 1.75);
    });

    test('residence split (items 9–16) and sex disaggregation', () {
      expect(t.domesticArrivals, 0);
      expect(t.foreignArrivals, 2);
      expect(t.foreignNights, 7);
      expect(t.overseasFilipinoArrivals, 0);
      expect(t.unknownArrivals, 0);
      expect(t.femaleArrivals, 1);
      expect(t.maleArrivals, 1);
    });

    test('sales totals', () {
      expect(t.totalSales, 3800);
      expect(t.chargesA, 800);
      expect(t.chargesB, 1200);
    });

    test('by Country (Sum): others vs listed countries', () {
      final lines = AeRegisterCalculator.countryMatrix(t.byCountry);
      AeCountryMatrixLine line(String label) =>
          lines.firstWhere((l) => l.label == label);
      final others = line('OTHERS AND UNSPECIFIED FOREIGN RESIDENCES');
      expect(others.totals!.arrivals, 2);
      expect(others.totals!.nights, 5);
      expect(others.alos, 2.5);
      expect(line('UNITED KINGDOM').totals!.nights, 2);
      final nonPh = line('TOTAL NON-PHILIPPINE RESIDENTS');
      expect(nonPh.totals!.arrivals, 2);
      expect(nonPh.totals!.nights, 7);
      expect(nonPh.alos, 3.5);
      expect(line('GRAND TOTAL GUEST ARRIVALS').ok, isTrue);
    });

    test('MonthlyRecord daily lines', () {
      final daily = AeRegisterCalculator.dailyTable(
        rows: _sample(),
        year: 2024,
        month: 1,
        totalRooms: 5,
        prevMonthLastDayGuests: 15,
      );
      expect(daily.length, 31);
      expect(daily[0].guestNights, 3);
      expect(daily[0].roomsOccupied, 2);
      expect(daily[0].occupancyRate, 0.4);
      expect(daily[0].guestsPerRoom, 1.5);
      expect(daily[1].checkOuts, 3);
      expect(daily[10].checkIns, 2);
    });
  });

  test('expandStay creates one row per night, first flagged checked-in', () {
    final rows = AeRegisterCalculator.expandStay(
      checkIn: DateTime(2026, 1, 30),
      nights: 4,
      roomNo: '3',
      residence: DaeResidenceCatalog.phFilipino,
      guests: 3,
      female: 2,
      male: 1,
    );
    expect(rows.length, 4);
    expect(rows.first.checkedInDay, isTrue);
    expect(rows.where((r) => r.checkedInDay).length, 1);
    expect(rows.last.date, DateTime(2026, 2, 2));
    final jan = AeRegisterCalculator.totals(
      rows: rows,
      year: 2026,
      month: 1,
      totalRooms: 10,
    );
    expect(jan.guestNights, 6);
    expect(jan.checkIns, 3);
    expect(jan.domesticArrivals, 3);
  });

  test('validate flags sex mismatch and double-booked rooms', () {
    final issues = AeRegisterCalculator.validate(
      rows: [
        AeRegisterRow(id: 'x', date: DateTime(2026, 3, 1), roomNo: '1', residence: 'Japan', guests: 2, female: 1),
        AeRegisterRow(id: 'y', date: DateTime(2026, 3, 1), roomNo: '1', residence: 'Japan', guests: 1, male: 1),
        AeRegisterRow(id: 'z', date: DateTime(2026, 3, 2), roomNo: '9', residence: 'Japan', guests: 1, male: 1),
      ],
      year: 2026,
      month: 3,
      totalRooms: 5,
      tracksRooms: true,
    );
    expect(issues.any((i) => i.rowId == 'x' && i.message.contains('Female')), isTrue);
    expect(issues.any((i) => i.rowId == 'y' && i.message.contains('already used')), isTrue);
    expect(issues.any((i) => i.rowId == 'z' && i.message.contains('outside')), isTrue);
  });
}
