import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/utils/ae_register_calculator.dart';

/// One mismatch between live Daily Register math and a saved/derived view.
class AeReconcileMismatch {
  const AeReconcileMismatch({
    required this.metric,
    required this.expected,
    required this.actual,
    required this.source,
  });

  final String metric;
  final String expected;
  final String actual;

  /// e.g. `header`, `dae2`, `by_country`.
  final String source;

  @override
  String toString() => '$metric: live=$expected · $source=$actual';
}

/// Compares live row totals (single source of truth) to header / DAE-2 / By Country.
///
/// Does not mutate data. Safe for UI warnings and debug logging.
abstract final class AeRegisterReconciler {
  /// Metrics that must match for the same AE-month when definitions align.
  static List<AeReconcileMismatch> compareLiveToHeader({
    required AeMonthTotals live,
    required AeMonthTotals header,
    double salesEpsilon = 0.01,
  }) {
    final out = <AeReconcileMismatch>[];
    void i(String metric, int a, int b) {
      if (a != b) {
        out.add(AeReconcileMismatch(
          metric: metric,
          expected: '$a',
          actual: '$b',
          source: 'header',
        ));
      }
    }

    void d(String metric, double a, double b) {
      if ((a - b).abs() > salesEpsilon) {
        out.add(AeReconcileMismatch(
          metric: metric,
          expected: a.toStringAsFixed(2),
          actual: b.toStringAsFixed(2),
          source: 'header',
        ));
      }
    }

    i('checkIns', live.checkIns, header.checkIns);
    i('guestNights', live.guestNights, header.guestNights);
    i('roomsOccupied', live.roomsOccupied, header.roomsOccupied);
    i('rowCount', live.rowCount, header.rowCount);
    i('domesticArrivals', live.domesticArrivals, header.domesticArrivals);
    i('foreignArrivals', live.foreignArrivals, header.foreignArrivals);
    i('overseasFilipinoArrivals', live.overseasFilipinoArrivals,
        header.overseasFilipinoArrivals);
    i('femaleArrivals', live.femaleArrivals, header.femaleArrivals);
    i('maleArrivals', live.maleArrivals, header.maleArrivals);
    d('totalSales', live.totalSales, header.totalSales);
    d('chargesA', live.chargesA, header.chargesA);
    d('chargesB', live.chargesB, header.chargesB);
    d('grandTotalSales', live.grandTotalSales, header.grandTotalSales);

    if (!_nearRate(live.occupancyRate, header.occupancyRate)) {
      out.add(AeReconcileMismatch(
        metric: 'occupancyRate',
        expected: AeRegisterCalculator.pct(live.occupancyRate),
        actual: AeRegisterCalculator.pct(header.occupancyRate),
        source: 'header',
      ));
    }
    if (!_nearRate(live.alos, header.alos, eps: 0.005)) {
      out.add(AeReconcileMismatch(
        metric: 'alos',
        expected: AeRegisterCalculator.dec(live.alos),
        actual: AeRegisterCalculator.dec(header.alos),
        source: 'header',
      ));
    }
    return out;
  }

  /// By Country arrival sum must equal live arrivals that were classified.
  static List<AeReconcileMismatch> compareByCountry({
    required AeMonthTotals live,
  }) {
    final out = <AeReconcileMismatch>[];
    var arrivals = 0;
    var nights = 0;
    for (final t in live.byCountry.values) {
      arrivals += t.arrivals;
      nights += t.nights;
    }
    // Arrivals only count checked-in-day rows; nights count every room-night.
    if (arrivals != live.checkIns) {
      out.add(AeReconcileMismatch(
        metric: 'byCountry.arrivals',
        expected: '${live.checkIns}',
        actual: '$arrivals',
        source: 'by_country',
      ));
    }
    if (nights != live.guestNights) {
      out.add(AeReconcileMismatch(
        metric: 'byCountry.nights',
        expected: '${live.guestNights}',
        actual: '$nights',
        source: 'by_country',
      ));
    }
    final classified = live.domesticArrivals +
        live.foreignArrivals +
        live.overseasFilipinoArrivals +
        live.unknownArrivals;
    if (classified != live.checkIns) {
      out.add(AeReconcileMismatch(
        metric: 'residenceBuckets.arrivals',
        expected: '${live.checkIns}',
        actual: '$classified',
        source: 'dae2_buckets',
      ));
    }
    return out;
  }

  /// Full AE-month check: live rows ↔ saved header ↔ country matrix.
  static List<AeReconcileMismatch> reconcileMonth({
    required Iterable<AeRegisterRow> rows,
    required AeMonthlyReport report,
  }) {
    final live = AeRegisterCalculator.totals(
      rows: rows,
      year: report.year,
      month: report.month,
      totalRooms: report.totalRooms,
      prevMonthLastDayGuests: report.prevMonthLastDayGuests,
      zeroDays: report.zeroDays,
    );
    return [
      ...compareLiveToHeader(live: live, header: report.totals),
      ...compareByCountry(live: live),
    ];
  }

  static bool _nearRate(double? a, double? b, {double eps = 1e-6}) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    return (a - b).abs() <= eps;
  }

  /// Short operator-facing summary (empty when OK).
  static String? warningMessage(List<AeReconcileMismatch> mismatches) {
    if (mismatches.isEmpty) return null;
    if (mismatches.length == 1) {
      return 'Register sync warning: ${mismatches.first}. Refresh or re-save the month.';
    }
    return 'Register sync warning: ${mismatches.length} totals differ from the '
        'saved month header (e.g. ${mismatches.first.metric}). Re-open the month or re-save a row.';
  }
}
