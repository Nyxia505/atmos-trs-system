import 'package:flutter_test/flutter_test.dart';
import 'package:atmos_trs_system/config/dae_residence_catalog.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/utils/ae_register_calculator.dart';
import 'package:atmos_trs_system/utils/ae_register_reconciler.dart';
import 'package:atmos_trs_system/utils/ae_register_report_query.dart';

void main() {
  group('AeRegisterReconciler', () {
    final rows = [
      AeRegisterRow(
        id: '1',
        date: DateTime(2026, 11, 7),
        roomNo: '101',
        residence: 'Algeria',
        guests: 3,
        female: 1,
        male: 2,
        checkedInDay: true,
        rate: 5000,
        chargesA: 500,
      ),
      AeRegisterRow(
        id: '2',
        date: DateTime(2026, 11, 7),
        roomNo: '102',
        residence: 'Afghanistan',
        guests: 4,
        female: 2,
        male: 2,
        checkedInDay: true,
        rate: 10000,
        chargesB: 1289,
      ),
    ];

    test('live totals match screenshot expectations', () {
      final t = AeRegisterCalculator.totals(
        rows: rows,
        year: 2026,
        month: 11,
        totalRooms: 20,
      );
      expect(t.rowCount, 2);
      expect(t.roomsOccupied, 2);
      expect(t.guestNights, 7);
      // DOT check-ins = guests on checked-in-day rows (not row count).
      expect(t.checkIns, 7);
      expect(t.femaleArrivals, 3);
      expect(t.maleArrivals, 4);
      expect(t.foreignArrivals, 7);
      expect(t.foreignNights, 7);
      expect(t.domesticArrivals, 0);
      expect(t.grandTotalSales, 16789);
      expect(DaeResidenceCatalog.bucketFor('Algeria'), DaeResidenceBucket.foreign);
      expect(DaeResidenceCatalog.bucketFor('Afghanistan'), DaeResidenceBucket.foreign);
    });

    test('header mismatch is detected', () {
      final live = AeRegisterCalculator.totals(
        rows: rows,
        year: 2026,
        month: 11,
        totalRooms: 20,
      );
      final stale = live.copyWithCheckIns(0);
      final mismatches = AeRegisterReconciler.compareLiveToHeader(
        live: live,
        header: stale,
      );
      expect(mismatches.any((m) => m.metric == 'checkIns'), isTrue);
    });

    test('by country reconciles with live arrivals/nights', () {
      final live = AeRegisterCalculator.totals(
        rows: rows,
        year: 2026,
        month: 11,
        totalRooms: 20,
      );
      expect(AeRegisterReconciler.compareByCountry(live: live), isEmpty);
    });

    test('inclusive date filter keeps boundary days', () {
      final filtered = filterAeRowsInclusive(
        rows,
        DateTime(2026, 11, 7),
        DateTime(2026, 11, 7),
      );
      expect(filtered, hasLength(2));
      expect(
        filterAeRowsInclusive(rows, DateTime(2026, 11, 1), DateTime(2026, 11, 6)),
        isEmpty,
      );
    });
  });
}

extension on AeMonthTotals {
  AeMonthTotals copyWithCheckIns(int checkIns) => AeMonthTotals(
        checkIns: checkIns,
        checkOuts: checkOuts,
        guestNights: guestNights,
        roomsOccupied: roomsOccupied,
        occupancyRate: occupancyRate,
        alos: alos,
        avgPersonsPerRoom: avgPersonsPerRoom,
        domesticArrivals: domesticArrivals,
        domesticNights: domesticNights,
        foreignArrivals: foreignArrivals,
        foreignNights: foreignNights,
        overseasFilipinoArrivals: overseasFilipinoArrivals,
        overseasFilipinoNights: overseasFilipinoNights,
        unknownArrivals: unknownArrivals,
        unknownNights: unknownNights,
        femaleArrivals: femaleArrivals,
        maleArrivals: maleArrivals,
        filipinoNationalArrivals: filipinoNationalArrivals,
        totalSales: totalSales,
        chargesA: chargesA,
        chargesB: chargesB,
        rowCount: rowCount,
        filledDays: filledDays,
        byCountry: byCountry,
        byRegion: byRegion,
      );
}
