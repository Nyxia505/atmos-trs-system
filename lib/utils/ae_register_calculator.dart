import 'package:atmos_trs_system/config/dae_residence_catalog.dart';
import 'package:atmos_trs_system/models/ae_register.dart';

/// One MonthlyRecord sheet line (per calendar day).
class AeDailyRecordLine {
  const AeDailyRecordLine({
    required this.day,
    required this.date,
    required this.checkIns,
    required this.checkOuts,
    required this.guestNights,
    required this.roomsOccupied,
    required this.occupancyRate,
    required this.guestsPerRoom,
    required this.hasRows,
    required this.markedZero,
  });

  final int day;
  final DateTime date;
  final int checkIns;

  /// Previous day's guests + today's check-ins − today's guests (workbook formula).
  /// Negative means guests were entered without a checked-in day.
  final int checkOuts;
  final int guestNights;
  final int roomsOccupied;

  /// 0..1; null when total rooms is unknown.
  final double? occupancyRate;
  final double guestsPerRoom;
  final bool hasRows;
  final bool markedZero;

  bool get isFilled => hasRows || markedZero;
}

enum AeMatrixLineKind { section, region, subregion, country, subtotal, total, grand, breakdown }

/// One line of the DAE-1B "by Country (Sum)" table.
class AeCountryMatrixLine {
  const AeCountryMatrixLine({
    required this.kind,
    required this.label,
    this.totals,
  });

  final AeMatrixLineKind kind;
  final String label;

  /// Null for header lines.
  final AeCountryTotals? totals;

  double? get alos {
    final t = totals;
    if (t == null || t.arrivals <= 0 || t.nights <= 0) return null;
    return t.nights / t.arrivals;
  }

  /// Sex disaggregation check (female + male = arrivals).
  bool get ok {
    final t = totals;
    if (t == null) return true;
    return t.female + t.male == t.arrivals;
  }
}

/// One DAE2_Auto summary item (1)–(18).
class AeDae2Item {
  const AeDae2Item(this.no, this.label, this.value, {this.kpi = false, this.input = false});

  final int no;
  final String label;
  final String value;

  /// Items (8), (17), (18): key business performance indicators.
  final bool kpi;

  /// Items (5)–(7): totals sourced straight from the register.
  final bool input;
}

class AeRegisterIssue {
  const AeRegisterIssue(this.rowId, this.message);

  /// Empty for month-level issues.
  final String rowId;
  final String message;
}

/// Pure DAE-1B workbook math. Mirrors MonthlyRecord / DAE2_Auto / By Country.
abstract final class AeRegisterCalculator {
  static List<AeRegisterRow> rowsInMonth(
    Iterable<AeRegisterRow> rows,
    int year,
    int month,
  ) =>
      rows
          .where((r) => r.date.year == year && r.date.month == month)
          .toList()
        ..sort((a, b) {
          final c = a.date.compareTo(b.date);
          if (c != 0) return c;
          return _roomSortKey(a.roomNo).compareTo(_roomSortKey(b.roomNo));
        });

  static int _roomSortKey(String room) => int.tryParse(room.trim()) ?? 1 << 20;

  static int daysIn(int year, int month) => DateTime(year, month + 1, 0).day;

  static int _arrivals(AeRegisterRow r) => r.checkedInDay ? r.guests : 0;

  static List<AeDailyRecordLine> dailyTable({
    required Iterable<AeRegisterRow> rows,
    required int year,
    required int month,
    required int totalRooms,
    int prevMonthLastDayGuests = 0,
    Iterable<int> zeroDays = const [],
  }) {
    final monthRows = rowsInMonth(rows, year, month);
    final days = daysIn(year, month);
    final zero = zeroDays.toSet();
    final byDay = <int, List<AeRegisterRow>>{};
    for (final r in monthRows) {
      byDay.putIfAbsent(r.day, () => []).add(r);
    }
    final out = <AeDailyRecordLine>[];
    var prevGuests = prevMonthLastDayGuests;
    for (var d = 1; d <= days; d++) {
      final list = byDay[d] ?? const <AeRegisterRow>[];
      final checkIns = list.fold<int>(0, (s, r) => s + _arrivals(r));
      final guestNights = list.fold<int>(0, (s, r) => s + r.guests);
      final rooms = list.length;
      out.add(AeDailyRecordLine(
        day: d,
        date: DateTime(year, month, d),
        checkIns: checkIns,
        checkOuts: prevGuests + checkIns - guestNights,
        guestNights: guestNights,
        roomsOccupied: rooms,
        occupancyRate: totalRooms > 0 ? rooms / totalRooms : null,
        guestsPerRoom: rooms > 0 ? guestNights / rooms : 0,
        hasRows: list.isNotEmpty,
        markedZero: zero.contains(d),
      ));
      prevGuests = guestNights;
    }
    return out;
  }

  /// Guests in-house on the month's last day (next month's "previous day" value).
  static int lastDayGuests(Iterable<AeRegisterRow> rows, int year, int month) {
    final last = daysIn(year, month);
    return rowsInMonth(rows, year, month)
        .where((r) => r.day == last)
        .fold<int>(0, (s, r) => s + r.guests);
  }

  static AeMonthTotals totals({
    required Iterable<AeRegisterRow> rows,
    required int year,
    required int month,
    required int totalRooms,
    int prevMonthLastDayGuests = 0,
    Iterable<int> zeroDays = const [],
  }) {
    final monthRows = rowsInMonth(rows, year, month);
    final daily = dailyTable(
      rows: monthRows,
      year: year,
      month: month,
      totalRooms: totalRooms,
      prevMonthLastDayGuests: prevMonthLastDayGuests,
      zeroDays: zeroDays,
    );
    final days = daysIn(year, month);

    var checkIns = 0, guestNights = 0;
    var domA = 0, domN = 0, forA = 0, forN = 0, ofwA = 0, ofwN = 0, unkA = 0, unkN = 0;
    var female = 0, male = 0, filNat = 0;
    var sales = 0.0, chA = 0.0, chB = 0.0;
    final byCountry = <String, AeCountryTotals>{};
    final byRegion = <String, AeCountryTotals>{};

    for (final r in monthRows) {
      final a = _arrivals(r);
      checkIns += a;
      guestNights += r.guests;
      final f = r.checkedInDay ? r.female : 0;
      final m = r.checkedInDay ? r.male : 0;
      female += f;
      male += m;
      sales += r.rate;
      chA += r.chargesA;
      chB += r.chargesB;
      if (r.checkedInDay && DaeResidenceCatalog.isFilipinoNational(r.residence)) {
        filNat += a;
      }
      switch (DaeResidenceCatalog.bucketFor(r.residence)) {
        case DaeResidenceBucket.philippineResident:
          domA += a;
          domN += r.guests;
        case DaeResidenceBucket.foreign:
          forA += a;
          forN += r.guests;
        case DaeResidenceBucket.overseasFilipino:
          ofwA += a;
          ofwN += r.guests;
        case DaeResidenceBucket.unspecified:
          unkA += a;
          unkN += r.guests;
      }
      final entry = AeCountryTotals(arrivals: a, nights: r.guests, female: f, male: m);
      final key = r.residence.trim().isEmpty ? DaeResidenceCatalog.unspecified : r.residence.trim();
      byCountry[key] = (byCountry[key] ?? const AeCountryTotals()) + entry;
      if (r.phRegion.trim().isNotEmpty &&
          DaeResidenceCatalog.bucketFor(r.residence) ==
              DaeResidenceBucket.philippineResident) {
        final rk = r.phRegion.trim();
        byRegion[rk] = (byRegion[rk] ?? const AeCountryTotals()) + entry;
      }
    }

    final roomsOccupied = monthRows.length;
    final filled = daily.where((d) => d.isFilled).length;
    return AeMonthTotals(
      checkIns: checkIns,
      checkOuts: daily.fold<int>(0, (s, d) => s + d.checkOuts),
      guestNights: guestNights,
      roomsOccupied: roomsOccupied,
      occupancyRate: totalRooms > 0 && days > 0 ? roomsOccupied / (totalRooms * days) : null,
      alos: checkIns > 0 ? guestNights / checkIns : null,
      avgPersonsPerRoom: roomsOccupied > 0 ? guestNights / roomsOccupied : null,
      domesticArrivals: domA,
      domesticNights: domN,
      foreignArrivals: forA,
      foreignNights: forN,
      overseasFilipinoArrivals: ofwA,
      overseasFilipinoNights: ofwN,
      unknownArrivals: unkA,
      unknownNights: unkN,
      femaleArrivals: female,
      maleArrivals: male,
      filipinoNationalArrivals: filNat,
      totalSales: sales,
      chargesA: chA,
      chargesB: chB,
      rowCount: monthRows.length,
      filledDays: filled,
      byCountry: byCountry,
      byRegion: byRegion,
    );
  }

  /// Sums several months / establishments (LGU, OPTACA, Governor roll-ups).
  static AeMonthTotals combine(Iterable<AeMonthTotals> list) {
    var t = const AeMonthTotals();
    var checkIns = 0, checkOuts = 0, gn = 0, ro = 0;
    var domA = 0, domN = 0, forA = 0, forN = 0, ofwA = 0, ofwN = 0, unkA = 0, unkN = 0;
    var fem = 0, mal = 0, fil = 0, rows = 0, filled = 0;
    var sales = 0.0, a = 0.0, b = 0.0;
    final byCountry = <String, AeCountryTotals>{};
    final byRegion = <String, AeCountryTotals>{};
    for (final x in list) {
      checkIns += x.checkIns;
      checkOuts += x.checkOuts;
      gn += x.guestNights;
      ro += x.roomsOccupied;
      domA += x.domesticArrivals;
      domN += x.domesticNights;
      forA += x.foreignArrivals;
      forN += x.foreignNights;
      ofwA += x.overseasFilipinoArrivals;
      ofwN += x.overseasFilipinoNights;
      unkA += x.unknownArrivals;
      unkN += x.unknownNights;
      fem += x.femaleArrivals;
      mal += x.maleArrivals;
      fil += x.filipinoNationalArrivals;
      rows += x.rowCount;
      filled += x.filledDays;
      sales += x.totalSales;
      a += x.chargesA;
      b += x.chargesB;
      x.byCountry.forEach((k, v) => byCountry[k] = (byCountry[k] ?? const AeCountryTotals()) + v);
      x.byRegion.forEach((k, v) => byRegion[k] = (byRegion[k] ?? const AeCountryTotals()) + v);
    }
    t = AeMonthTotals(
      checkIns: checkIns,
      checkOuts: checkOuts,
      guestNights: gn,
      roomsOccupied: ro,
      alos: checkIns > 0 ? gn / checkIns : null,
      avgPersonsPerRoom: ro > 0 ? gn / ro : null,
      domesticArrivals: domA,
      domesticNights: domN,
      foreignArrivals: forA,
      foreignNights: forN,
      overseasFilipinoArrivals: ofwA,
      overseasFilipinoNights: ofwN,
      unknownArrivals: unkA,
      unknownNights: unkN,
      femaleArrivals: fem,
      maleArrivals: mal,
      filipinoNationalArrivals: fil,
      totalSales: sales,
      chargesA: a,
      chargesB: b,
      rowCount: rows,
      filledDays: filled,
      byCountry: byCountry,
      byRegion: byRegion,
    );
    return t;
  }

  /// Occupancy across reports: Σ rooms occupied ÷ Σ (rooms × days).
  static double? combinedOccupancy(Iterable<AeMonthlyReport> reports) {
    var occ = 0, avail = 0;
    for (final r in reports) {
      if (r.totalRooms <= 0) continue;
      occ += r.totals.roomsOccupied;
      avail += r.totalRooms * r.days;
    }
    return avail > 0 ? occ / avail : null;
  }

  static String pct(double? rate, {int digits = 2}) =>
      rate == null ? '—' : '${(rate * 100).toStringAsFixed(digits)}%';

  static String dec(double? v, {int digits = 2}) =>
      v == null ? '—' : v.toStringAsFixed(digits);

  static List<AeDae2Item> dae2Summary(AeMonthlyReport report, AeMonthTotals t) => [
        AeDae2Item(1, 'Identification of Accommodation Establishment', report.aeName),
        AeDae2Item(2, 'Type of Accommodation-Classification', report.aeType),
        AeDae2Item(3, 'Classification Code', report.classificationCode),
        AeDae2Item(4, 'Total Available Rooms', '${report.totalRooms}'),
        AeDae2Item(5, 'Total Number of Guest Checked-in', '${t.checkIns}', input: true),
        AeDae2Item(6, 'Total Guest-Nights During the Month', '${t.guestNights}', input: true),
        AeDae2Item(7, 'Total Number of Rooms Occupied During the Month', '${t.roomsOccupied}',
            input: true),
        AeDae2Item(8, 'Room Occupancy Rate', pct(t.occupancyRate), kpi: true),
        AeDae2Item(9, 'Domestic Guest Arrival', '${t.domesticArrivals}'),
        AeDae2Item(10, 'Domestic Guest Nights', '${t.domesticNights}'),
        AeDae2Item(11, 'Foreign Guest Arrival', '${t.foreignArrivals}'),
        AeDae2Item(12, 'Foreign Guest Nights', '${t.foreignNights}'),
        AeDae2Item(13, 'Overseas Filipinos Arrival', '${t.overseasFilipinoArrivals}'),
        AeDae2Item(14, 'Overseas Filipinos Guest Nights', '${t.overseasFilipinoNights}'),
        AeDae2Item(15, 'Unknown/Unspecified Guest Arrival', '${t.unknownArrivals}'),
        AeDae2Item(16, 'Unknown/Unspecified Guest Nights', '${t.unknownNights}'),
        AeDae2Item(17, 'Overall Average Length of Stay', dec(t.alos), kpi: true),
        AeDae2Item(18, 'Overall Average Persons per Room', dec(t.avgPersonsPerRoom), kpi: true),
      ];

  /// DAE-1B "by Country (Sum)" table from saved per-residence totals.
  static List<AeCountryMatrixLine> countryMatrix(Map<String, AeCountryTotals> byCountry) {
    AeCountryTotals sumWhere(bool Function(String key) test) {
      var t = const AeCountryTotals();
      byCountry.forEach((k, v) {
        if (test(k)) t = t + v;
      });
      return t;
    }

    final lines = <AeCountryMatrixLine>[];
    final phFil = sumWhere((k) => k == DaeResidenceCatalog.phFilipino ||
        (DaeResidenceCatalog.bucketFor(k) == DaeResidenceBucket.philippineResident &&
            k != DaeResidenceCatalog.phForeignNational));
    final phFor = sumWhere((k) => k == DaeResidenceCatalog.phForeignNational);
    final phTotal = phFil + phFor;
    lines
      ..add(const AeCountryMatrixLine(kind: AeMatrixLineKind.section, label: 'PHILIPPINE RESIDENTS'))
      ..add(AeCountryMatrixLine(kind: AeMatrixLineKind.country, label: 'FILIPINO NATIONALITY', totals: phFil))
      ..add(AeCountryMatrixLine(kind: AeMatrixLineKind.country, label: 'FOREIGN NATIONALITY', totals: phFor))
      ..add(AeCountryMatrixLine(kind: AeMatrixLineKind.total, label: 'TOTAL PHILIPPINE RESIDENTS', totals: phTotal))
      ..add(const AeCountryMatrixLine(kind: AeMatrixLineKind.section, label: 'NON-PHILIPPINE RESIDENTS'));

    final listedKeys = <String>{};
    var nonPh = const AeCountryTotals();
    String? lastRegion;
    for (final g in DaeResidenceCatalog.groups) {
      if (g.region != lastRegion) {
        lines.add(AeCountryMatrixLine(kind: AeMatrixLineKind.region, label: g.region));
        lastRegion = g.region;
      }
      if (g.title != g.region) {
        lines.add(AeCountryMatrixLine(kind: AeMatrixLineKind.subregion, label: g.title));
      }
      var sub = const AeCountryTotals();
      for (final c in g.countries) {
        final t = sumWhere((k) {
          if (DaeResidenceCatalog.bucketFor(k) != DaeResidenceBucket.foreign) return false;
          final match = DaeResidenceCatalog.countryFor(k);
          if (match?.key == c.key) {
            listedKeys.add(k);
            return true;
          }
          return false;
        });
        sub = sub + t;
        lines.add(AeCountryMatrixLine(kind: AeMatrixLineKind.country, label: c.label, totals: t));
      }
      nonPh = nonPh + sub;
      lines.add(AeCountryMatrixLine(kind: AeMatrixLineKind.subtotal, label: 'SUB-TOTAL', totals: sub));
    }
    final others = sumWhere((k) =>
        DaeResidenceCatalog.bucketFor(k) == DaeResidenceBucket.foreign && !listedKeys.contains(k));
    nonPh = nonPh + others;
    final ofw = sumWhere((k) => DaeResidenceCatalog.bucketFor(k) == DaeResidenceBucket.overseasFilipino);
    final unk = sumWhere((k) => DaeResidenceCatalog.bucketFor(k) == DaeResidenceBucket.unspecified);
    final grand = phTotal + nonPh + ofw + unk;
    lines
      ..add(AeCountryMatrixLine(
        kind: AeMatrixLineKind.country,
        label: 'OTHERS AND UNSPECIFIED FOREIGN RESIDENCES',
        totals: others,
      ))
      ..add(AeCountryMatrixLine(kind: AeMatrixLineKind.total, label: 'TOTAL NON-PHILIPPINE RESIDENTS', totals: nonPh))
      ..add(AeCountryMatrixLine(kind: AeMatrixLineKind.country, label: 'OVERSEAS FILIPINOS*', totals: ofw))
      ..add(AeCountryMatrixLine(kind: AeMatrixLineKind.grand, label: 'GRAND TOTAL GUEST ARRIVALS', totals: grand))
      ..add(AeCountryMatrixLine(kind: AeMatrixLineKind.breakdown, label: 'Total Philippine Residents', totals: phTotal))
      ..add(AeCountryMatrixLine(kind: AeMatrixLineKind.breakdown, label: 'Total Non-Philippine Residents', totals: nonPh))
      ..add(AeCountryMatrixLine(kind: AeMatrixLineKind.breakdown, label: 'Total Overseas Filipinos', totals: ofw))
      ..add(AeCountryMatrixLine(
        kind: AeMatrixLineKind.breakdown,
        label: 'Total Guests with Unspecified Residence',
        totals: unk,
      ));
    return lines;
  }

  /// Row + month checks copied from the workbook validation columns.
  static List<AeRegisterIssue> validate({
    required Iterable<AeRegisterRow> rows,
    required int year,
    required int month,
    required int totalRooms,
    required bool tracksRooms,
  }) {
    final issues = <AeRegisterIssue>[];
    final seen = <String, String>{};
    for (final r in rows) {
      if (r.date.year != year || r.date.month != month) {
        issues.add(AeRegisterIssue(r.id, 'Date is outside this month.'));
      }
      if (r.guests < 1) {
        issues.add(AeRegisterIssue(r.id, 'Guests must be at least 1.'));
      }
      if (r.female + r.male != r.guests) {
        issues.add(AeRegisterIssue(r.id, 'Female + Male must equal guests (${r.guests}).'));
      }
      if (tracksRooms) {
        final room = r.roomNo.trim();
        final n = int.tryParse(room);
        if (room.isEmpty) {
          issues.add(AeRegisterIssue(r.id, 'Room number is required.'));
        } else if (n != null && totalRooms > 0 && (n < 1 || n > totalRooms)) {
          issues.add(AeRegisterIssue(r.id, 'Room $room is outside 1–$totalRooms.'));
        } else {
          final key = '${AeRegisterRow.dateKey(r.date)}|$room';
          final prior = seen[key];
          if (prior != null) {
            issues.add(AeRegisterIssue(r.id, 'Room $room is already used on this date.'));
          } else {
            seen[key] = r.id;
          }
        }
      }
    }
    return issues;
  }

  /// Expands a stay (check-in date, nights) into nightly register rows.
  /// Only the first night is flagged as the checked-in day.
  static List<AeRegisterRow> expandStay({
    required DateTime checkIn,
    required int nights,
    required String roomNo,
    required String residence,
    required int guests,
    required int female,
    required int male,
    String phRegion = '',
    double rate = 0,
    double chargesA = 0,
    double chargesB = 0,
  }) {
    final n = nights < 1 ? 1 : nights;
    final start = DateTime(checkIn.year, checkIn.month, checkIn.day);
    return [
      for (var i = 0; i < n; i++)
        AeRegisterRow(
          id: '',
          date: DateTime(start.year, start.month, start.day + i),
          roomNo: roomNo,
          residence: residence,
          phRegion: phRegion,
          guests: guests,
          female: female,
          male: male,
          checkedInDay: i == 0,
          rate: rate,
          chargesA: i == 0 ? chargesA : 0,
          chargesB: i == 0 ? chargesB : 0,
        ),
    ];
  }
}
