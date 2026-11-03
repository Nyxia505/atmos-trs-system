import '../data.dart';
import '../services/saved_trip_store.dart';

/// Chart grouping for saved itineraries (by save date, not travel date).
enum TripTrendGrain { daily, weekly, monthly, yearly }

/// One saved plan plus the timestamp used for trend grouping.
class AnalyticTripPlan {
  const AnalyticTripPlan({required this.plan, this.savedAt});

  final SavedTripPlan plan;
  final DateTime? savedAt;
}

class TripTrendPoint {
  const TripTrendPoint({
    required this.key,
    required this.label,
    required this.count,
    this.fullLabel = '',
  });

  final String key;
  final String label;
  final String fullLabel;
  final int count;

  String get tooltipLabel => fullLabel.isEmpty ? label : fullLabel;
}

/// Calendar shortcuts for the analytics date picker.
enum TripDatePreset { today, last7, last30, thisMonth, thisYear, custom }

class TripRankRow {
  const TripRankRow({
    required this.id,
    required this.label,
    required this.count,
    this.detail = '',
  });

  final String id;
  final String label;
  final String detail;
  final int count;

  /// Inclusion rate among [total] saved plans, 0–100.
  int percentOf(int total) => inclusionPercent(count, total);

  /// Progress-bar fraction among [total] saved plans, 0–1.
  double barOf(int total) => inclusionBar(count, total);
}

/// Selected Daily / Weekly / Monthly / Yearly range. Always a complete axis.
class TripTrendWindow {
  const TripTrendWindow._({
    required this.grain,
    required this.start,
    required this.end,
    required this.label,
    this.preset,
  });

  final TripTrendGrain grain;

  /// Inclusive local start of the window.
  final DateTime start;

  /// Exclusive local end of the window.
  final DateTime end;
  final String label;
  final TripDatePreset? preset;

  DateTime get inclusiveEnd => end.subtract(const Duration(days: 1));

  int get selectedDayCount {
    final days = inclusiveEnd.difference(DateTime(start.year, start.month, start.day)).inDays + 1;
    return days < 1 ? 1 : days;
  }

  factory TripTrendWindow.current(TripTrendGrain grain, {DateTime? now}) {
    final n = (now ?? DateTime.now()).toLocal();
    return switch (grain) {
      TripTrendGrain.daily => TripTrendWindow.daily(n.year, n.month),
      TripTrendGrain.weekly => TripTrendWindow.weekly(mondayOnOrBefore(n)),
      TripTrendGrain.monthly => TripTrendWindow.monthly(n.year),
      TripTrendGrain.yearly => TripTrendWindow.yearly(n.year - 4),
    };
  }

  factory TripTrendWindow.preset(
    TripDatePreset preset,
    TripTrendGrain grain, {
    DateTime? now,
  }) {
    final n = (now ?? DateTime.now()).toLocal();
    final today = DateTime(n.year, n.month, n.day);
    switch (preset) {
      case TripDatePreset.today:
        return TripTrendWindow.fromRange(
          grain: grain,
          startInclusive: today,
          endInclusive: today,
          preset: preset,
        );
      case TripDatePreset.last7:
        return TripTrendWindow.fromRange(
          grain: grain,
          startInclusive: today.subtract(const Duration(days: 6)),
          endInclusive: today,
          preset: preset,
        );
      case TripDatePreset.last30:
        return TripTrendWindow.fromRange(
          grain: grain,
          startInclusive: today.subtract(const Duration(days: 29)),
          endInclusive: today,
          preset: preset,
        );
      case TripDatePreset.thisMonth:
        return TripTrendWindow.fromRange(
          grain: grain,
          startInclusive: DateTime(n.year, n.month, 1),
          endInclusive: DateTime(n.year, n.month + 1, 0),
          preset: preset,
        );
      case TripDatePreset.thisYear:
        return TripTrendWindow.fromRange(
          grain: grain,
          startInclusive: DateTime(n.year, 1, 1),
          endInclusive: DateTime(n.year, 12, 31),
          preset: preset,
        );
      case TripDatePreset.custom:
        return TripTrendWindow.fromRange(
          grain: grain,
          startInclusive: DateTime(n.year, n.month, 1),
          endInclusive: today,
          preset: preset,
        );
    }
  }

  /// Inclusive calendar dates, grouped by [grain].
  factory TripTrendWindow.fromRange({
    required TripTrendGrain grain,
    required DateTime startInclusive,
    required DateTime endInclusive,
    TripDatePreset? preset,
  }) {
    var start = DateTime(
      startInclusive.year,
      startInclusive.month,
      startInclusive.day,
    );
    var last = DateTime(
      endInclusive.year,
      endInclusive.month,
      endInclusive.day,
    );
    if (last.isBefore(start)) {
      final swap = start;
      start = last;
      last = swap;
    }
    return TripTrendWindow._(
      grain: grain,
      start: start,
      end: last.add(const Duration(days: 1)),
      label: _windowLabel(preset, start, last),
      preset: preset,
    );
  }

  TripTrendWindow withGrain(TripTrendGrain grain) {
    if (grain == this.grain) return this;
    return TripTrendWindow.fromRange(
      grain: grain,
      startInclusive: start,
      endInclusive: inclusiveEnd,
      preset: preset,
    );
  }

  /// One calendar day. Header: `October 26, 2026`.
  factory TripTrendWindow.day(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    return TripTrendWindow.fromRange(
      grain: TripTrendGrain.daily,
      startInclusive: d,
      endInclusive: d,
      preset: TripDatePreset.custom,
    );
  }

  /// Monday–Sunday week containing [day], charted as seven daily points.
  factory TripTrendWindow.weekOf(DateTime day) {
    final monday = mondayOnOrBefore(day);
    final sunday = monday.add(const Duration(days: 6));
    return TripTrendWindow._(
      grain: TripTrendGrain.daily,
      start: monday,
      end: sunday.add(const Duration(days: 1)),
      label: _weekFull(monday),
      preset: TripDatePreset.custom,
    );
  }

  /// Calendar month of daily buckets. Header: `October 2026`.
  factory TripTrendWindow.daily(int year, int month) {
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    return TripTrendWindow._(
      grain: TripTrendGrain.daily,
      start: start,
      end: end,
      label: '${_monthLong[month - 1]} $year',
      preset: TripDatePreset.thisMonth,
    );
  }

  /// 12 Monday-aligned weeks ending at [lastMonday] (inclusive week).
  factory TripTrendWindow.weekly(DateTime lastMonday) {
    final last = mondayOnOrBefore(lastMonday);
    final start = last.subtract(const Duration(days: 11 * 7));
    final end = last.add(const Duration(days: 7));
    return TripTrendWindow._(
      grain: TripTrendGrain.weekly,
      start: start,
      end: end,
      label: _rangeLabel(start, end.subtract(const Duration(days: 1))),
    );
  }

  /// January–December of [year].
  factory TripTrendWindow.monthly(int year) {
    return TripTrendWindow._(
      grain: TripTrendGrain.monthly,
      start: DateTime(year, 1, 1),
      end: DateTime(year + 1, 1, 1),
      label: 'January–December $year',
      preset: TripDatePreset.thisYear,
    );
  }

  /// Five calendar years beginning at [firstYear].
  factory TripTrendWindow.yearly(int firstYear) {
    return TripTrendWindow._(
      grain: TripTrendGrain.yearly,
      start: DateTime(firstYear, 1, 1),
      end: DateTime(firstYear + 5, 1, 1),
      label: '$firstYear–${firstYear + 4}',
    );
  }

  bool contains(DateTime at) {
    final t = at.toLocal();
    return !t.isBefore(start) && t.isBefore(end);
  }

  TripTrendWindow previous() {
    switch (preset) {
      case TripDatePreset.thisYear:
        return TripTrendWindow.preset(
          TripDatePreset.thisYear,
          grain,
          now: DateTime(start.year - 1, 6, 1),
        );
      case TripDatePreset.thisMonth:
        return TripTrendWindow.preset(
          TripDatePreset.thisMonth,
          grain,
          now: DateTime(start.year, start.month - 1, 15),
        );
      case TripDatePreset.today:
      case TripDatePreset.last7:
      case TripDatePreset.last30:
      case TripDatePreset.custom:
      case null:
        break;
    }
    return switch (grain) {
      TripTrendGrain.daily => _isFullCalendarMonth
          ? (start.month == 1
              ? TripTrendWindow.daily(start.year - 1, 12)
              : TripTrendWindow.daily(start.year, start.month - 1))
          : _shiftByDays(-selectedDayCount),
      TripTrendGrain.weekly => _shiftByDays(-selectedDayCount),
      TripTrendGrain.monthly => _isFullCalendarYear
          ? TripTrendWindow.monthly(start.year - 1)
          : _shiftByDays(-selectedDayCount),
      TripTrendGrain.yearly => TripTrendWindow.yearly(start.year - 5),
    };
  }

  TripTrendWindow next() {
    switch (preset) {
      case TripDatePreset.thisYear:
        return TripTrendWindow.preset(
          TripDatePreset.thisYear,
          grain,
          now: DateTime(start.year + 1, 6, 1),
        );
      case TripDatePreset.thisMonth:
        return TripTrendWindow.preset(
          TripDatePreset.thisMonth,
          grain,
          now: DateTime(start.year, start.month + 1, 15),
        );
      case TripDatePreset.today:
      case TripDatePreset.last7:
      case TripDatePreset.last30:
      case TripDatePreset.custom:
      case null:
        break;
    }
    return switch (grain) {
      TripTrendGrain.daily => _isFullCalendarMonth
          ? TripTrendWindow.daily(end.year, end.month)
          : _shiftByDays(selectedDayCount),
      TripTrendGrain.weekly => _shiftByDays(selectedDayCount),
      TripTrendGrain.monthly => _isFullCalendarYear
          ? TripTrendWindow.monthly(start.year + 1)
          : _shiftByDays(selectedDayCount),
      TripTrendGrain.yearly => TripTrendWindow.yearly(start.year + 5),
    };
  }

  bool get _isFullCalendarYear =>
      start.month == 1 &&
      start.day == 1 &&
      end.month == 1 &&
      end.day == 1 &&
      end.year == start.year + 1;

  bool get _isFullCalendarMonth =>
      start.day == 1 &&
      end.day == 1 &&
      DateTime(start.year, start.month + 1, 1) == end;

  TripTrendWindow _shiftByDays(int days) {
    final shiftedStart = start.add(Duration(days: days));
    if (grain == TripTrendGrain.daily && selectedDayCount == 1) {
      return TripTrendWindow.day(shiftedStart);
    }
    if (grain == TripTrendGrain.daily &&
        selectedDayCount == 7 &&
        start == mondayOnOrBefore(start)) {
      return TripTrendWindow.weekOf(shiftedStart);
    }
    return TripTrendWindow.fromRange(
      grain: grain,
      startInclusive: shiftedStart,
      endInclusive: inclusiveEnd.add(Duration(days: days)),
      preset: preset == TripDatePreset.thisYear ||
              preset == TripDatePreset.thisMonth
          ? preset
          : TripDatePreset.custom,
    );
  }

  /// Next is disabled once the window reaches the current period.
  bool get canGoNext => canGoNextAt(DateTime.now());

  bool canGoNextAt(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return !next().start.isAfter(today);
  }

  List<TripTrendPoint> emptyBuckets() {
    return switch (grain) {
      TripTrendGrain.daily => [
          for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1)))
            TripTrendPoint(
              key: _dayKey(d),
              label: _sameMonthWindow
                  ? '${d.day}'
                  : '${_monthShort[d.month - 1]} ${d.day}',
              fullLabel: '${_monthLong[d.month - 1]} ${d.day}, ${d.year}',
              count: 0,
            ),
        ],
      TripTrendGrain.weekly => [
          for (var w = _firstMonday; !w.isAfter(_lastMonday); w = w.add(const Duration(days: 7)))
            TripTrendPoint(
              key: _dayKey(w),
              label: _weekTick(w),
              fullLabel: _weekFull(w),
              count: 0,
            ),
        ],
      TripTrendGrain.monthly => [
          for (var m = DateTime(start.year, start.month, 1);
              m.isBefore(end);
              m = DateTime(m.year, m.month + 1, 1))
            TripTrendPoint(
              key: '${m.year}-${m.month}',
              label: _sameYearWindow
                  ? _monthShort[m.month - 1]
                  : '${_monthShort[m.month - 1]} ${m.year}',
              fullLabel: '${_monthLong[m.month - 1]} ${m.year}',
              count: 0,
            ),
        ],
      TripTrendGrain.yearly => [
          for (var y = start.year; y <= inclusiveEnd.year; y++)
            TripTrendPoint(
              key: '$y',
              label: '$y',
              fullLabel: '$y',
              count: 0,
            ),
        ],
    };
  }

  bool get _sameMonthWindow =>
      start.year == inclusiveEnd.year && start.month == inclusiveEnd.month;

  bool get _sameYearWindow => start.year == inclusiveEnd.year;

  DateTime get _firstMonday => mondayOnOrBefore(start);

  DateTime get _lastMonday => mondayOnOrBefore(inclusiveEnd);
}

class TripPlannerAnalyticsSnapshot {
  TripPlannerAnalyticsSnapshot._({
    required this.scoped,
    required this.series,
    required this.destinations,
    required this.municipalityRanks,
    required this.starts,
    required this.ends,
    required this.routes,
    required this.durations,
    required this.distinctDestinations,
    required this.distinctMunicipalities,
    required this.averageDays,
    required this.coastal,
    required this.highland,
    required this.routeTypeMissing,
    required this.skippedMissingTimestamp,
  });

  final List<AnalyticTripPlan> scoped;
  final List<TripTrendPoint> series;
  final List<TripRankRow> destinations;
  final List<TripRankRow> municipalityRanks;
  final List<TripRankRow> starts;
  final List<TripRankRow> ends;
  final List<TripRankRow> routes;
  final List<TripRankRow> durations;
  final int distinctDestinations;
  final int distinctMunicipalities;
  final double? averageDays;
  final int coastal;
  final int highland;
  final int routeTypeMissing;
  final int skippedMissingTimestamp;

  int get planCount => scoped.length;

  int get coastalPercent =>
      coastal + highland == 0 ? 0 : (coastal / (coastal + highland) * 100).round();
  int get highlandPercent =>
      coastal + highland == 0 ? 0 : (highland / (coastal + highland) * 100).round();

  factory TripPlannerAnalyticsSnapshot.compute({
    required List<AnalyticTripPlan> plans,
    required TripTrendWindow window,
  }) {
    var skipped = 0;
    final scoped = <AnalyticTripPlan>[];
    for (final row in plans) {
      final at = row.savedAt;
      if (at == null) {
        skipped++;
        continue;
      }
      if (window.contains(at)) scoped.add(row);
    }

    final destCounts = <String, int>{};
    final destLabel = <String, String>{};
    final destMuni = <String, String>{};
    final muniCounts = <String, int>{};
    final muniLabel = <String, String>{};
    final startCounts = <String, int>{};
    final endCounts = <String, int>{};
    final routeCounts = <String, int>{};
    final durationCounts = <String, int>{
      for (final label in const [
        '1-day trips',
        '2-day trips',
        '3-day trips',
        '4–5-day trips',
        '6–7-day trips',
        '8 or more days',
      ])
        label: 0,
    };
    var daySum = 0;
    var dayPlans = 0;
    var coastalCount = 0;
    var highlandCount = 0;
    var missingRoute = 0;

    for (final row in scoped) {
      final plan = row.plan;
      final spots = destinationEntries(plan);
      for (final spot in spots) {
        destCounts[spot.id] = (destCounts[spot.id] ?? 0) + 1;
        destLabel[spot.id] = spot.label;
        if (spot.detail.isNotEmpty) destMuni[spot.id] = spot.detail;
      }
      final munis = municipalityEntries(plan);
      for (final muni in munis) {
        muniCounts[muni.id] = (muniCounts[muni.id] ?? 0) + 1;
        muniLabel[muni.id] = muni.label;
      }
      final start = plan.startName.trim();
      final end = plan.endName.trim();
      if (start.isNotEmpty) startCounts[start] = (startCounts[start] ?? 0) + 1;
      if (end.isNotEmpty) endCounts[end] = (endCounts[end] ?? 0) + 1;
      if (start.isNotEmpty && end.isNotEmpty) {
        final pair = '$start → $end';
        routeCounts[pair] = (routeCounts[pair] ?? 0) + 1;
      }
      final label = durationLabel(plan);
      if (label != null) {
        durationCounts[label] = (durationCounts[label] ?? 0) + 1;
        daySum += dayCount(plan);
        dayPlans++;
      }
      if (plan.routeType == 'coastal') {
        coastalCount++;
      } else if (plan.routeType == 'highland') {
        highlandCount++;
      } else {
        missingRoute++;
      }
    }

    return TripPlannerAnalyticsSnapshot._(
      scoped: scoped,
      series: fillTrendSeries(savedAt: [
        for (final row in scoped)
          if (row.savedAt != null) row.savedAt!,
      ], window: window),
      destinations: _rank(destCounts, (id) => destLabel[id] ?? id, destMuni),
      municipalityRanks: _rank(muniCounts, (id) => muniLabel[id] ?? id, const {}),
      starts: _rank(startCounts, (id) => id, const {}),
      ends: _rank(endCounts, (id) => id, const {}),
      routes: _rank(routeCounts, (id) => id, const {}),
      durations: [
        for (final entry in durationCounts.entries)
          TripRankRow(id: entry.key, label: entry.key, count: entry.value),
      ],
      distinctDestinations: destCounts.length,
      distinctMunicipalities: muniCounts.length,
      averageDays: dayPlans == 0 ? null : daySum / dayPlans,
      coastal: coastalCount,
      highland: highlandCount,
      routeTypeMissing: missingRoute,
      skippedMissingTimestamp: skipped,
    );
  }
}

/// Unique tourist destinations in [plan] (once per itinerary).
List<({String id, String label, String detail})> destinationEntries(
  SavedTripPlan plan,
) {
  final seen = <String>{};
  final out = <({String id, String label, String detail})>[];
  for (final day in plan.daySpotNames) {
    for (final raw in day) {
      final name = raw.trim();
      if (name.isEmpty) continue;
      final spot = findTouristSpotByNameFuzzy(name);
      final id = (spot?.firestoreDocId ?? '').trim().isNotEmpty
          ? spot!.firestoreDocId!.trim()
          : normalizeTourismNameKey(spot?.name ?? name);
      if (id.isEmpty || !seen.add(id)) continue;
      final label = (spot?.displayName ?? name).trim();
      final muni = municipalityLabelOf(spot?.location ?? '');
      out.add((id: id, label: label.isEmpty ? name : label, detail: muni));
    }
  }
  return out;
}

/// Unique municipalities in [plan] (start, end, and planned spots; once).
List<({String id, String label})> municipalityEntries(SavedTripPlan plan) {
  final seen = <String>{};
  final out = <({String id, String label})>[];
  void add(String raw) {
    final resolved = resolveMunicipality(raw);
    if (resolved == null) return;
    if (!seen.add(resolved.id)) return;
    out.add(resolved);
  }

  add(plan.startName);
  add(plan.endName);
  for (final day in plan.daySpotNames) {
    for (final spotName in day) {
      final spot = findTouristSpotByNameFuzzy(spotName);
      add(spot?.location ?? spotName);
    }
  }
  return out;
}

({String id, String label})? resolveMunicipality(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  for (final municipality in municipalities) {
    if (_same(municipality.name, trimmed) ||
        _same(municipality.shortName, trimmed)) {
      final id = normalizeTourismNameKey(municipality.name);
      if (id.isEmpty) return null;
      return (id: id, label: municipality.name);
    }
  }
  final spot = findTouristSpotByNameFuzzy(trimmed);
  final location = spot?.location.trim() ?? '';
  if (location.isEmpty) return null;
  if (_same(location, trimmed)) return null;
  return resolveMunicipality(location);
}

String municipalityLabelOf(String raw) => resolveMunicipality(raw)?.label ?? '';

List<TripTrendPoint> fillTrendSeries({
  required Iterable<DateTime> savedAt,
  required TripTrendWindow window,
}) {
  final buckets = window.emptyBuckets();
  if (buckets.isEmpty) return buckets;
  final index = <String, int>{
    for (var i = 0; i < buckets.length; i++) buckets[i].key: i,
  };
  final counts = List<int>.filled(buckets.length, 0);
  for (final at in savedAt) {
    final local = at.toLocal();
    if (!window.contains(local)) continue;
    final key = switch (window.grain) {
      TripTrendGrain.daily => _dayKey(DateTime(local.year, local.month, local.day)),
      TripTrendGrain.weekly => _dayKey(mondayOnOrBefore(local)),
      TripTrendGrain.monthly => '${local.year}-${local.month}',
      TripTrendGrain.yearly => '${local.year}',
    };
    final i = index[key];
    if (i == null) continue;
    counts[i]++;
  }
  return [
    for (var i = 0; i < buckets.length; i++)
      TripTrendPoint(
        key: buckets[i].key,
        label: buckets[i].label,
        fullLabel: buckets[i].fullLabel,
        count: counts[i],
      ),
  ];
}

int? peakSeriesIndex(List<TripTrendPoint> series) {
  var max = 0;
  var index = -1;
  for (var i = 0; i < series.length; i++) {
    if (series[i].count > max) {
      max = series[i].count;
      index = i;
    }
  }
  if (index < 0 || max <= 0) return null;
  return index;
}

int inclusionPercent(int count, int total) {
  if (total <= 0 || count <= 0) return 0;
  final pct = ((count / total) * 100).round();
  if (pct < 0) return 0;
  if (pct > 100) return 100;
  return pct;
}

double inclusionBar(int count, int total) {
  if (total <= 0 || count <= 0) return 0;
  final value = count / total;
  if (value.isNaN || value.isInfinite) return 0;
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}

int dayCount(SavedTripPlan plan) {
  if (plan.tripDays > 0) return plan.tripDays;
  return plan.daySpotNames.where((day) => day.isNotEmpty).length;
}

String? durationLabel(SavedTripPlan plan) {
  final days = dayCount(plan);
  if (days <= 0) return null;
  if (days == 1) return '1-day trips';
  if (days == 2) return '2-day trips';
  if (days == 3) return '3-day trips';
  if (days <= 5) return '4–5-day trips';
  if (days <= 7) return '6–7-day trips';
  return '8 or more days';
}

DateTime mondayOnOrBefore(DateTime d) {
  final day = DateTime(d.year, d.month, d.day);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

List<TripRankRow> _rank(
  Map<String, int> counts,
  String Function(String id) label,
  Map<String, String> details,
) {
  final keys = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      if (byCount != 0) return byCount;
      return label(a).toLowerCase().compareTo(label(b).toLowerCase());
    });
  return [
    for (final key in keys)
      TripRankRow(
        id: key,
        label: label(key),
        count: counts[key]!,
        detail: details[key] ?? '',
      ),
  ];
}

bool _same(String a, String b) =>
    a.trim().toLowerCase() == b.trim().toLowerCase();

String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

String _weekTick(DateTime monday) {
  final sunday = monday.add(const Duration(days: 6));
  if (monday.month == sunday.month) {
    return '${_monthShort[monday.month - 1]} ${monday.day}–${sunday.day}';
  }
  return '${_monthShort[monday.month - 1]} ${monday.day}–${_monthShort[sunday.month - 1]} ${sunday.day}';
}

String _weekFull(DateTime monday) {
  final sunday = monday.add(const Duration(days: 6));
  if (monday.year == sunday.year && monday.month == sunday.month) {
    return '${_monthLong[monday.month - 1]} ${monday.day}–${sunday.day}, ${monday.year}';
  }
  if (monday.year == sunday.year) {
    return '${_monthLong[monday.month - 1]} ${monday.day} – ${_monthLong[sunday.month - 1]} ${sunday.day}, ${monday.year}';
  }
  return '${_monthLong[monday.month - 1]} ${monday.day}, ${monday.year} – ${_monthLong[sunday.month - 1]} ${sunday.day}, ${sunday.year}';
}

String _windowLabel(TripDatePreset? preset, DateTime start, DateTime last) {
  switch (preset) {
    case TripDatePreset.today:
      return 'Today · ${_monthLong[start.month - 1]} ${start.day}, ${start.year}';
    case TripDatePreset.last7:
      return 'Last 7 days · ${_rangeLabel(start, last)}';
    case TripDatePreset.last30:
      return 'Last 30 days · ${_rangeLabel(start, last)}';
    case TripDatePreset.thisMonth:
      return '${_monthLong[start.month - 1]} ${start.year}';
    case TripDatePreset.thisYear:
      return 'January–December ${start.year}';
    case TripDatePreset.custom:
    case null:
      if (start.year == last.year &&
          start.month == last.month &&
          start.day == last.day) {
        return '${_monthLong[start.month - 1]} ${start.day}, ${start.year}';
      }
      if (start.year == last.year &&
          start.month == 1 &&
          start.day == 1 &&
          last.month == 12 &&
          last.day == 31) {
        return 'January–December ${start.year}';
      }
      return _rangeLabel(start, last);
  }
}

String _rangeLabel(DateTime start, DateTime end) {
  if (start.year == end.year) {
    if (start.month == end.month) {
      return '${_monthShort[start.month - 1]} ${start.day}–${end.day}, ${start.year}';
    }
    return '${_monthShort[start.month - 1]} ${start.day} – ${_monthShort[end.month - 1]} ${end.day}, ${start.year}';
  }
  return '${_monthShort[start.month - 1]} ${start.day}, ${start.year} – ${_monthShort[end.month - 1]} ${end.day}, ${end.year}';
}

const _monthShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

const _monthLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
