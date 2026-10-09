import 'package:atmos_trs_system/config/dae_residence_catalog.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/utils/ae_register_calculator.dart';

/// How much recommendation text to trust, by filled register days.
enum AeInsightsDssLevel { locked, soft, full }

enum AeInsightTone { positive, info, warning, action }

class AeInsightHint {
  const AeInsightHint(this.title, this.body, {this.tone = AeInsightTone.info});

  final String title;
  final String body;
  final AeInsightTone tone;
}

/// One month on the history charts (from saved header totals).
class AeMonthPoint {
  const AeMonthPoint({
    required this.year,
    required this.month,
    required this.totals,
    required this.totalRooms,
    required this.days,
  });

  final int year;
  final int month;
  final AeMonthTotals totals;
  final int totalRooms;
  final int days;

  static const _abbr = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String get label => _abbr[(month - 1) % 12];
  String get longLabel => '$label $year';

  double? get occupancyPct =>
      totals.occupancyRate == null ? null : totals.occupancyRate! * 100;

  /// Average daily rate: room revenue ÷ rooms occupied.
  double? get adr =>
      totals.roomsOccupied > 0 && totals.totalSales > 0 ? totals.totalSales / totals.roomsOccupied : null;

  /// Revenue per available room: room revenue ÷ (rooms × days).
  double? get revpar =>
      totalRooms > 0 && days > 0 && totals.totalSales > 0 ? totals.totalSales / (totalRooms * days) : null;
}

class AeRoomUsage {
  const AeRoomUsage({
    required this.roomNo,
    required this.nights,
    required this.guestNights,
    required this.revenue,
  });

  final String roomNo;
  final int nights;
  final int guestNights;
  final double revenue;

  double? get adr => nights > 0 && revenue > 0 ? revenue / nights : null;
}

class AeRankedOrigin {
  const AeRankedOrigin(this.label, this.totals);

  final String label;
  final AeCountryTotals totals;
}

class AeRegisterInsights {
  const AeRegisterInsights({
    required this.year,
    required this.month,
    required this.totals,
    required this.totalRooms,
    required this.days,
    required this.daysElapsed,
    required this.daily,
    required this.weekdayOccupancyPct,
    required this.weekdayGuests,
    required this.history,
    required this.previous,
    required this.lastYear,
    required this.rooms,
    required this.topForeign,
    required this.topRegions,
    required this.historyFilledDays,
    required this.dss,
    required this.hints,
    required this.negativeCheckOutDays,
  });

  final int year;
  final int month;
  final AeMonthTotals totals;
  final int totalRooms;
  final int days;

  /// Days counted for month-to-date rates (full month when in the past).
  final int daysElapsed;
  final List<AeDailyRecordLine> daily;

  /// Mon..Sun average occupancy % (null entries when rooms unknown).
  final List<double> weekdayOccupancyPct;

  /// Mon..Sun average guests in-house.
  final List<double> weekdayGuests;

  /// Up to 12 months ending at the selected month (oldest first).
  final List<AeMonthPoint> history;
  final AeMonthPoint? previous;
  final AeMonthPoint? lastYear;

  /// All rooms 1..N (lodging), most used first.
  final List<AeRoomUsage> rooms;
  final List<AeRankedOrigin> topForeign;
  final List<AeRankedOrigin> topRegions;
  final int historyFilledDays;
  final AeInsightsDssLevel dss;
  final List<AeInsightHint> hints;
  final int negativeCheckOutDays;

  bool get isCurrentMonth => daysElapsed < days;
  int get filledDays => daily.where((d) => d.isFilled).length;
  double get completeness => daysElapsed <= 0 ? 0 : (filledDays / daysElapsed).clamp(0.0, 1.0);

  /// Month-to-date occupancy % (full month when the month is over).
  double? get occupancyPct =>
      totalRooms > 0 && daysElapsed > 0 ? totals.roomsOccupied / (totalRooms * daysElapsed) * 100 : null;

  double? get adr =>
      totals.roomsOccupied > 0 && totals.totalSales > 0 ? totals.totalSales / totals.roomsOccupied : null;

  double? get revpar =>
      totalRooms > 0 && daysElapsed > 0 && totals.totalSales > 0
          ? totals.totalSales / (totalRooms * daysElapsed)
          : null;

  /// Spend per arriving guest (non-lodging packs).
  double? get spendPerGuest =>
      totals.checkIns > 0 && totals.grandTotalSales > 0 ? totals.grandTotalSales / totals.checkIns : null;

  int get roomNightsTotal => rooms.fold<int>(0, (s, r) => s + r.nights);
  bool get hasData => totals.rowCount > 0;

  AeRegisterInsights _withHints(List<AeInsightHint> next) => AeRegisterInsights(
        year: year,
        month: month,
        totals: totals,
        totalRooms: totalRooms,
        days: days,
        daysElapsed: daysElapsed,
        daily: daily,
        weekdayOccupancyPct: weekdayOccupancyPct,
        weekdayGuests: weekdayGuests,
        history: history,
        previous: previous,
        lastYear: lastYear,
        rooms: rooms,
        topForeign: topForeign,
        topRegions: topRegions,
        historyFilledDays: historyFilledDays,
        dss: dss,
        hints: next,
        negativeCheckOutDays: negativeCheckOutDays,
      );
}

abstract final class AeRegisterInsightsBuilder {
  static const softDays = 7;
  static const fullDays = 30;
  static const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static AeRegisterInsights build({
    required List<AeMonthlyReport> reports,
    required List<AeRegisterRow> rows,
    required int year,
    required int month,
    required int totalRooms,
    required bool tracksRooms,
    DateTime? now,
  }) {
    final n = now ?? DateTime.now();
    final days = AeRegisterCalculator.daysIn(year, month);
    final isCurrent = n.year == year && n.month == month;
    final isFuture = year * 100 + month > n.year * 100 + n.month;
    final daysElapsed = isFuture ? 0 : (isCurrent ? n.day : days);

    AeMonthlyReport? findReport(int y, int m) {
      for (final r in reports) {
        if (r.year == y && r.month == m) return r;
      }
      return null;
    }

    final report = findReport(year, month);
    final rooms = tracksRooms ? totalRooms : 0;
    final totals = AeRegisterCalculator.totals(
      rows: rows,
      year: year,
      month: month,
      totalRooms: rooms,
      prevMonthLastDayGuests: report?.prevMonthLastDayGuests ?? 0,
      zeroDays: report?.zeroDays ?? const [],
    );
    final daily = AeRegisterCalculator.dailyTable(
      rows: rows,
      year: year,
      month: month,
      totalRooms: rooms,
      prevMonthLastDayGuests: report?.prevMonthLastDayGuests ?? 0,
      zeroDays: report?.zeroDays ?? const [],
    );

    final elapsedDaily = daily.take(daysElapsed).toList();
    final wdRooms = List<int>.filled(7, 0);
    final wdGuests = List<int>.filled(7, 0);
    final wdCount = List<int>.filled(7, 0);
    for (final d in elapsedDaily) {
      final i = d.date.weekday - 1;
      wdRooms[i] += d.roomsOccupied;
      wdGuests[i] += d.guestNights;
      wdCount[i]++;
    }
    final weekdayOcc = [
      for (var i = 0; i < 7; i++)
        rooms > 0 && wdCount[i] > 0 ? wdRooms[i] / (rooms * wdCount[i]) * 100 : 0.0,
    ];
    final weekdayGuests = [
      for (var i = 0; i < 7; i++) wdCount[i] > 0 ? wdGuests[i] / wdCount[i] : 0.0,
    ];

    AeMonthPoint point(AeMonthlyReport r) {
      final isSel = r.year == year && r.month == month;
      return AeMonthPoint(
        year: r.year,
        month: r.month,
        totals: isSel ? totals : r.totals,
        totalRooms: rooms > 0 ? (isSel ? rooms : (r.totalRooms > 0 ? r.totalRooms : rooms)) : 0,
        days: r.days,
      );
    }

    final selKey = year * 100 + month;
    final history = <AeMonthPoint>[];
    for (var back = 11; back >= 0; back--) {
      final d = DateTime(year, month - back);
      final r = findReport(d.year, d.month);
      if (r != null) {
        history.add(point(r));
      } else if (back == 0) {
        history.add(AeMonthPoint(year: year, month: month, totals: totals, totalRooms: rooms, days: days));
      }
    }
    final prevDate = DateTime(year, month - 1);
    final prevReport = findReport(prevDate.year, prevDate.month);
    final lyReport = findReport(year - 1, month);

    final nightsByRoom = <String, int>{};
    final guestsByRoom = <String, int>{};
    final revenueByRoom = <String, double>{};
    for (final r in AeRegisterCalculator.rowsInMonth(rows, year, month)) {
      final id = r.roomNo.trim();
      if (id.isEmpty) continue;
      nightsByRoom[id] = (nightsByRoom[id] ?? 0) + 1;
      guestsByRoom[id] = (guestsByRoom[id] ?? 0) + r.guests;
      revenueByRoom[id] = (revenueByRoom[id] ?? 0) + r.rate;
    }
    final roomIds = <String>{
      if (rooms > 0) for (var i = 1; i <= rooms; i++) '$i',
      ...nightsByRoom.keys,
    };
    final roomUsage = [
      for (final id in roomIds)
        AeRoomUsage(
          roomNo: id,
          nights: nightsByRoom[id] ?? 0,
          guestNights: guestsByRoom[id] ?? 0,
          revenue: revenueByRoom[id] ?? 0,
        ),
    ]..sort((a, b) {
        final c = b.nights.compareTo(a.nights);
        if (c != 0) return c;
        return (int.tryParse(a.roomNo) ?? 1 << 20).compareTo(int.tryParse(b.roomNo) ?? 1 << 20);
      });

    final topForeign = <AeRankedOrigin>[
      for (final e in totals.byCountry.entries)
        if (e.value.arrivals > 0 &&
            DaeResidenceCatalog.bucketFor(e.key) == DaeResidenceBucket.foreign)
          AeRankedOrigin(e.key, e.value),
    ]..sort((a, b) => b.totals.arrivals.compareTo(a.totals.arrivals));
    final topRegions = <AeRankedOrigin>[
      for (final e in totals.byRegion.entries)
        if (e.value.arrivals > 0) AeRankedOrigin(e.key, e.value),
    ]..sort((a, b) => b.totals.arrivals.compareTo(a.totals.arrivals));

    final historyFilled = reports
        .where((r) => r.year * 100 + r.month <= selKey && !(r.year == year && r.month == month))
        .fold<int>(0, (s, r) => s + r.totals.filledDays) +
        elapsedDaily.where((d) => d.isFilled).length;
    final dss = historyFilled >= fullDays
        ? AeInsightsDssLevel.full
        : historyFilled >= softDays
            ? AeInsightsDssLevel.soft
            : AeInsightsDssLevel.locked;

    final negative = elapsedDaily.where((d) => d.checkOuts < 0).length;

    final base = AeRegisterInsights(
      year: year,
      month: month,
      totals: totals,
      totalRooms: rooms,
      days: days,
      daysElapsed: daysElapsed,
      daily: daily,
      weekdayOccupancyPct: weekdayOcc,
      weekdayGuests: weekdayGuests,
      history: history,
      previous: prevReport == null ? null : point(prevReport),
      lastYear: lyReport == null ? null : point(lyReport),
      rooms: roomUsage,
      topForeign: topForeign,
      topRegions: topRegions,
      historyFilledDays: historyFilled,
      dss: dss,
      hints: const [],
      negativeCheckOutDays: negative,
    );
    return base._withHints(_hints(base, tracksRooms: tracksRooms));
  }

  static String _peso(double v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '₱$b';
  }

  static List<AeInsightHint> _hints(AeRegisterInsights a, {required bool tracksRooms}) {
    final out = <AeInsightHint>[];
    final t = a.totals;

    // Data-quality hints are always shown (they affect LGU / DOT totals).
    final missing = a.daysElapsed - a.filledDays;
    if (a.daysElapsed > 0 && missing > 0) {
      out.add(AeInsightHint(
        '$missing day${missing == 1 ? '' : 's'} not filled yet',
        'Add rows or mark the day "no guests" in Monthly Record so your LGU '
            'report shows complete figures (${a.filledDays}/${a.daysElapsed} days filled).',
        tone: AeInsightTone.action,
      ));
    }
    if (a.negativeCheckOutDays > 0) {
      out.add(AeInsightHint(
        'Check-outs went negative on ${a.negativeCheckOutDays} day(s)',
        'Guests appear without a "checked-in day" row. Tick checked-in on each '
            'guest\'s first night so arrivals and ALOS are correct.',
        tone: AeInsightTone.warning,
      ));
    }
    if (tracksRooms && t.roomsOccupied > 0 && t.totalSales <= 0) {
      out.add(const AeInsightHint(
        'Room rates not entered',
        'Enter the rate on each row to unlock ADR, RevPAR and revenue trends.',
        tone: AeInsightTone.action,
      ));
    }

    if (a.dss == AeInsightsDssLevel.locked || !a.hasData) return out;
    final full = a.dss == AeInsightsDssLevel.full;

    // Weekday pattern.
    if (tracksRooms && a.totalRooms > 0 && a.daysElapsed >= 7) {
      var hi = 0, lo = 0;
      for (var i = 1; i < 7; i++) {
        if (a.weekdayOccupancyPct[i] > a.weekdayOccupancyPct[hi]) hi = i;
        if (a.weekdayOccupancyPct[i] < a.weekdayOccupancyPct[lo]) lo = i;
      }
      final hv = a.weekdayOccupancyPct[hi], lv = a.weekdayOccupancyPct[lo];
      if (hv >= 15 && hv >= lv * 1.5) {
        out.add(AeInsightHint(
          '${weekdayShort[hi]} is your busiest night, ${weekdayShort[lo]} the slowest',
          '${weekdayShort[hi]} averages ${hv.toStringAsFixed(0)}% occupancy vs '
              '${lv.toStringAsFixed(0)}% on ${weekdayShort[lo]}. Midweek promos, '
              'government / corporate rates or LGU event tie-ins can fill slow nights.',
        ));
      }
    }

    // Length of stay.
    final alos = t.alos;
    if (tracksRooms && alos != null && t.checkIns >= 5) {
      if (alos < 1.5) {
        out.add(AeInsightHint(
          'Most guests stay one night (ALOS ${alos.toStringAsFixed(2)})',
          'Bundle a 2-night package with nearby attractions (tours, island hopping, '
              'heritage sites) to raise guest-nights.',
        ));
      } else if (alos >= 3) {
        out.add(AeInsightHint(
          'Long stays (ALOS ${alos.toStringAsFixed(2)} nights)',
          'Guests stay several nights — weekly rates, laundry and meal plans can '
              'lift revenue per stay.',
          tone: AeInsightTone.positive,
        ));
      }
    }

    // Persons per room.
    final ppr = t.avgPersonsPerRoom;
    if (tracksRooms && ppr != null && t.roomsOccupied >= 10) {
      if (ppr < 1.3) {
        out.add(AeInsightHint(
          'Mostly solo travelers (${ppr.toStringAsFixed(2)} persons / room)',
          'Consider single-occupancy rates or converting some doubles for business travelers.',
        ));
      } else if (ppr >= 3) {
        out.add(AeInsightHint(
          'Groups and families (${ppr.toStringAsFixed(2)} persons / room)',
          'Family rooms, extra beds and group packages fit your current demand.',
          tone: AeInsightTone.positive,
        ));
      }
    }

    // Occupancy level + trend.
    final occ = a.occupancyPct;
    final prevOcc = a.previous?.occupancyPct;
    if (occ != null) {
      if (occ >= 80) {
        out.add(AeInsightHint(
          'Near capacity (${occ.toStringAsFixed(1)}% occupancy)',
          'Demand is strong — there is room to raise rates on peak nights.',
          tone: AeInsightTone.positive,
        ));
      } else if (occ < 30 && full) {
        final adr = a.adr;
        final prevAdr = a.previous?.adr;
        out.add(AeInsightHint(
          'Low occupancy (${occ.toStringAsFixed(1)}%)',
          adr != null && prevAdr != null && adr > prevAdr * 1.1
              ? 'Average rate rose to ${_peso(adr)} (from ${_peso(prevAdr)}) while '
                  'occupancy is low — the rate may be deterring bookings.'
              : 'List on online travel sites and coordinate with your LGU tourism office '
                  'on upcoming events and tour packages.',
          tone: AeInsightTone.warning,
        ));
      }
      if (prevOcc != null && !a.isCurrentMonth) {
        final delta = occ - prevOcc;
        if (delta.abs() >= 10) {
          out.add(AeInsightHint(
            delta > 0
                ? 'Occupancy up ${delta.toStringAsFixed(1)} pts vs ${a.previous!.label}'
                : 'Occupancy down ${(-delta).toStringAsFixed(1)} pts vs ${a.previous!.label}',
            delta > 0
                ? 'Note what drove it (events, holidays, promos) so you can repeat it.'
                : 'Check for seasonality, closed rooms or missing entries.',
            tone: delta > 0 ? AeInsightTone.positive : AeInsightTone.warning,
          ));
        }
      }
    }

    // Market mix.
    final arrivals = t.domesticArrivals + t.foreignArrivals + t.overseasFilipinoArrivals;
    if (arrivals >= 10) {
      final foreignShare = t.foreignArrivals / arrivals * 100;
      if (foreignShare >= 20 && a.topForeign.isNotEmpty) {
        final names = a.topForeign.take(3).map((o) => o.label).join(', ');
        out.add(AeInsightHint(
          'Foreign guests are ${foreignShare.toStringAsFixed(0)}% of arrivals',
          'Top markets: $names. English signage, online payment and listings on '
              'international booking sites help you keep them.',
          tone: AeInsightTone.positive,
        ));
      } else if (a.topRegions.isNotEmpty && t.domesticArrivals >= 5) {
        final top = a.topRegions.first;
        final share = t.domesticArrivals == 0 ? 0 : top.totals.arrivals / t.domesticArrivals * 100;
        if (share >= 40) {
          out.add(AeInsightHint(
            '${share.toStringAsFixed(0)}% of domestic guests come from ${top.label}',
            'Target promotions and social media ads at this region; consider partnering '
                'with travel agencies there.',
          ));
        }
      }
    }

    // Underused rooms (needs ~1 month of history).
    if (full && tracksRooms && a.rooms.length >= 3) {
      final total = a.roomNightsTotal;
      if (total >= 15) {
        final avg = total / a.rooms.length;
        final under = a.rooms.where((r) => r.nights < avg * 0.55).toList()
          ..sort((x, y) => x.nights.compareTo(y.nights));
        if (under.isNotEmpty) {
          final list = under.take(4).map((r) => 'Room ${r.roomNo} (${r.nights})').join(', ');
          out.add(AeInsightHint(
            '${under.length} room(s) used well below average',
            '$list vs ~${avg.toStringAsFixed(1)} nights per room. Check condition, '
                'pricing or desk assignment habits.',
            tone: AeInsightTone.warning,
          ));
        }
      }
    }

    // Year-over-year.
    final ly = a.lastYear;
    if (ly != null && ly.totals.guestNights > 0 && !a.isCurrentMonth) {
      final pct = (t.guestNights - ly.totals.guestNights) / ly.totals.guestNights * 100;
      if (pct.abs() >= 10) {
        out.add(AeInsightHint(
          'Guest-nights ${pct >= 0 ? 'up' : 'down'} ${pct.abs().toStringAsFixed(0)}% vs ${ly.longLabel}',
          'Same month last year: ${ly.totals.guestNights} guest-nights; now ${t.guestNights}.',
          tone: pct >= 0 ? AeInsightTone.positive : AeInsightTone.warning,
        ));
      }
    }

    return out;
  }
}
