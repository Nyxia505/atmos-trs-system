import 'package:flutter_test/flutter_test.dart';
import 'package:trip_plan/services/saved_trip_store.dart';
import 'package:trip_plan/utils/trip_planner_analytics.dart';

SavedTripPlan _plan({
  required String id,
  required DateTime savedAt,
  String start = 'Ozamiz City',
  String end = 'Ozamiz City',
  List<List<String>> spots = const [
    ['Aloran Viewpoint'],
  ],
  int tripDays = 2,
}) {
  return SavedTripPlan(
    id: id,
    createdAt: savedAt,
    startName: start,
    endName: end,
    arrivalDate: null,
    departureDate: null,
    tripDays: tripDays,
    travelers: 1,
    transportMode: 'Public Transport',
    budgetPhp: 0,
    estimatedTotalPhp: 0,
    daySpotNames: spots,
  );
}

AnalyticTripPlan _row(
  String id,
  DateTime savedAt, {
  String start = 'Ozamiz City',
  String end = 'Ozamiz City',
  List<List<String>> spots = const [
    ['Aloran Viewpoint'],
  ],
  int tripDays = 2,
}) {
  return AnalyticTripPlan(
    plan: _plan(
      id: id,
      savedAt: savedAt,
      start: start,
      end: end,
      spots: spots,
      tripDays: tripDays,
    ),
    savedAt: savedAt,
  );
}

void main() {
  group('inclusion rate', () {
    test('matches the destination percentage table', () {
      expect(inclusionPercent(3, 20), 15);
      expect(inclusionPercent(3, 10), 30);
      expect(inclusionPercent(3, 5), 60);
      expect(inclusionPercent(3, 3), 100);
      expect(inclusionPercent(0, 20), 0);
      expect(inclusionBar(3, 20), closeTo(0.15, 0.0001));
      expect(inclusionBar(3, 3), 1);
      expect(inclusionBar(0, 20), 0);
    });

    test('guards zero totals and overflow', () {
      expect(inclusionPercent(3, 0), 0);
      expect(inclusionPercent(-1, 10), 0);
      expect(inclusionBar(4, 2), 1);
      expect(inclusionBar(1, 0), 0);
    });
  });

  group('monthly chart', () {
    test('shows all 12 months when every plan was saved in October', () {
      final window = TripTrendWindow.monthly(2026);
      final saved = [
        for (var i = 0; i < 5; i++) DateTime(2026, 10, 4 + i),
      ];
      final series = fillTrendSeries(savedAt: saved, window: window);
      expect(series.length, 12);
      expect(series.map((p) => p.label).toList(), [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ]);
      expect(series[9].count, 5);
      expect(series[9].label, 'Oct');
      expect(series.where((p) => p.label != 'Oct').every((p) => p.count == 0), isTrue);
    });
  });

  group('daily / weekly / yearly windows', () {
    test('daily fills every day of the month including zeros', () {
      final window = TripTrendWindow.daily(2026, 10);
      expect(window.label, 'October 2026');
      expect(window.emptyBuckets().length, 31);
      final series = fillTrendSeries(
        savedAt: [DateTime(2026, 10, 15, 8), DateTime(2026, 10, 15, 19)],
        window: window,
      );
      expect(series[14].count, 2);
      expect(series[14].label, '15');
      expect(series.where((p) => p.label != '15').every((p) => p.count == 0), isTrue);
    });

    test('weekly groups Monday–Sunday and keeps empty weeks', () {
      // 2026-10-19 is a Monday; 2026-10-24 is Saturday of that week.
      final lastMonday = DateTime(2026, 10, 19);
      final window = TripTrendWindow.weekly(lastMonday);
      expect(window.emptyBuckets().length, 12);
      final series = fillTrendSeries(
        savedAt: [
          DateTime(2026, 10, 19, 9),
          DateTime(2026, 10, 24, 18),
        ],
        window: window,
      );
      final week = series.firstWhere((p) => p.key == '2026-10-19');
      expect(week.count, 2);
      expect(week.label, 'Oct 19–25');
    });

    test('yearly fills a five-year axis', () {
      final window = TripTrendWindow.yearly(2024);
      expect(window.label, '2024–2028');
      final series = fillTrendSeries(
        savedAt: [DateTime(2026, 3, 1)],
        window: window,
      );
      expect(series.map((p) => p.label).toList(), [
        '2024', '2025', '2026', '2027', '2028',
      ]);
      expect(series[2].count, 1);
    });

    test('next is disabled on the current period', () {
      final now = DateTime(2026, 10, 26);
      final current = TripTrendWindow.current(
        TripTrendGrain.monthly,
        now: now,
      );
      expect(current.canGoNextAt(now), isFalse);
      expect(current.previous().canGoNextAt(now), isTrue);
      expect(current.previous().next().label, current.label);
    });

    test('custom Oct 1–25 daily has 25 days and only counts that range', () {
      final window = TripTrendWindow.fromRange(
        grain: TripTrendGrain.daily,
        startInclusive: DateTime(2026, 10, 1),
        endInclusive: DateTime(2026, 10, 25),
        preset: TripDatePreset.custom,
      );
      expect(window.selectedDayCount, 25);
      expect(window.emptyBuckets().length, 25);
      final series = fillTrendSeries(
        savedAt: [
          DateTime(2026, 10, 15),
          DateTime(2026, 10, 26),
          DateTime(2026, 9, 30),
        ],
        window: window,
      );
      expect(series.fold<int>(0, (n, p) => n + p.count), 1);
      expect(series[14].count, 1);
    });

    test('custom range with monthly grain keeps only overlapping months', () {
      final window = TripTrendWindow.fromRange(
        grain: TripTrendGrain.monthly,
        startInclusive: DateTime(2026, 10, 1),
        endInclusive: DateTime(2026, 10, 25),
        preset: TripDatePreset.custom,
      );
      final series = fillTrendSeries(
        savedAt: [
          for (var i = 0; i < 5; i++) DateTime(2026, 10, 4 + i),
          DateTime(2026, 9, 1),
        ],
        window: window,
      );
      expect(series.length, 1);
      expect(series.first.count, 5);
      expect(series.first.fullLabel, 'October 2026');
    });

    test('day window is a single date and previous moves one day', () {
      final window = TripTrendWindow.day(DateTime(2026, 10, 26));
      expect(window.label, 'October 26, 2026');
      expect(window.emptyBuckets().length, 1);
      expect(window.previous().label, 'October 25, 2026');
      expect(window.previous().next().label, window.label);
      final series = fillTrendSeries(
        savedAt: [DateTime(2026, 10, 26, 9), DateTime(2026, 10, 25)],
        window: window,
      );
      expect(series.single.count, 1);
    });

    test('weekOf snaps Saturday to Monday–Sunday and keeps seven days', () {
      final window = TripTrendWindow.weekOf(DateTime(2026, 10, 24));
      expect(window.start, DateTime(2026, 10, 19));
      expect(window.inclusiveEnd, DateTime(2026, 10, 25));
      expect(window.emptyBuckets().length, 7);
      expect(window.label, 'October 19–25, 2026');
      final series = fillTrendSeries(
        savedAt: [
          DateTime(2026, 10, 19, 9),
          DateTime(2026, 10, 24, 18),
          DateTime(2026, 10, 26),
        ],
        window: window,
      );
      expect(series.fold<int>(0, (n, p) => n + p.count), 2);
      expect(window.previous().inclusiveEnd, DateTime(2026, 10, 18));
    });

    test('month picker window is the days of that month', () {
      final window = TripTrendWindow.daily(2026, 3);
      expect(window.label, 'March 2026');
      expect(window.emptyBuckets().length, 31);
    });

    test('year picker window is January–December of that year', () {
      final window = TripTrendWindow.monthly(2025);
      expect(window.label, 'January–December 2025');
      expect(window.emptyBuckets().length, 12);
      expect(window.next().label, 'January–December 2026');
    });

    test('peakSeriesIndex is the highest real count', () {
      final series = fillTrendSeries(
        savedAt: [
          for (var i = 0; i < 5; i++) DateTime(2026, 10, 4 + i),
        ],
        window: TripTrendWindow.monthly(2026),
      );
      expect(peakSeriesIndex(series), 9);
      expect(series[peakSeriesIndex(series)!].count, 5);
    });

    test('withGrain keeps the selected dates', () {
      final window = TripTrendWindow.fromRange(
        grain: TripTrendGrain.monthly,
        startInclusive: DateTime(2026, 10, 1),
        endInclusive: DateTime(2026, 10, 25),
        preset: TripDatePreset.custom,
      );
      final daily = window.withGrain(TripTrendGrain.daily);
      expect(daily.start, window.start);
      expect(daily.inclusiveEnd, window.inclusiveEnd);
      expect(daily.emptyBuckets().length, 25);
    });
  });

  group('snapshot counting', () {
    test('counts a destination once per itinerary', () {
      final window = TripTrendWindow.monthly(2026);
      final snapshot = TripPlannerAnalyticsSnapshot.compute(
        window: window,
        plans: [
          _row(
            'a',
            DateTime(2026, 10, 2),
            spots: [
              ['Aloran Viewpoint', 'Aloran Viewpoint'],
              ['Aloran Viewpoint'],
            ],
          ),
          for (var i = 1; i < 20; i++)
            _row(
              'p$i',
              DateTime(2026, 10, 3),
              start: 'Ozamiz City',
              end: 'Ozamiz City',
              spots: const [
                ['Hoyohoy Highland'],
              ],
            ),
        ],
      );
      expect(snapshot.planCount, 20);
      final aloran = snapshot.destinations.firstWhere(
        (r) => r.label.toLowerCase().contains('aloran'),
      );
      expect(aloran.count, 1);
      expect(aloran.percentOf(20), 5);
    });

    test('uses total saved plans as the destination bar denominator', () {
      final window = TripTrendWindow.monthly(2026);
      final snapshot = TripPlannerAnalyticsSnapshot.compute(
        window: window,
        plans: [
          for (var i = 0; i < 3; i++)
            _row('hit$i', DateTime(2026, 10, 1), spots: const [
              ['Aloran Viewpoint'],
            ]),
          for (var i = 0; i < 17; i++)
            _row(
              'other$i',
              DateTime(2026, 10, 2),
              spots: const [
                ['Hoyohoy Highland'],
              ],
            ),
        ],
      );
      final aloran = snapshot.destinations.firstWhere(
        (r) => r.label.toLowerCase().contains('aloran'),
      );
      expect(snapshot.planCount, 20);
      expect(aloran.count, 3);
      expect(aloran.percentOf(snapshot.planCount), 15);
      expect(aloran.barOf(snapshot.planCount), closeTo(0.15, 0.0001));
    });

    test('counts a municipality once even when it is start and end', () {
      final window = TripTrendWindow.monthly(2026);
      final snapshot = TripPlannerAnalyticsSnapshot.compute(
        window: window,
        plans: [
          _row(
            '1',
            DateTime(2026, 10, 1),
            start: 'Don Victoriano Chiongbian',
            end: 'Don Victoriano Chiongbian',
            spots: const [
              ['Hoyohoy Highland'],
            ],
          ),
          _row(
            '2',
            DateTime(2026, 10, 1),
            start: 'Don Victoriano Chiongbian',
            end: 'Ozamiz City',
            spots: const [
              ['Hoyohoy Highland'],
            ],
          ),
          _row(
            '3',
            DateTime(2026, 10, 1),
            start: 'Don Victoriano Chiongbian',
            end: 'Ozamiz City',
            spots: const [
              ['Hoyohoy Highland'],
            ],
          ),
          _row(
            '4',
            DateTime(2026, 10, 1),
            start: 'Clarin',
            end: 'Clarin',
            spots: const [
              ['Hoyohoy Highland'],
            ],
          ),
          _row(
            '5',
            DateTime(2026, 10, 1),
            start: 'Tangub City',
            end: 'Tangub City',
            spots: const [
              ['Hoyohoy Highland'],
            ],
          ),
        ],
      );
      expect(snapshot.planCount, 5);
      int countOf(String name) => snapshot.municipalityRanks
          .firstWhere((r) => r.label == name)
          .count;
      expect(countOf('Don Victoriano Chiongbian'), 3);
      expect(
        snapshot.municipalityRanks
            .firstWhere((r) => r.label == 'Don Victoriano Chiongbian')
            .percentOf(5),
        60,
      );
      expect(countOf('Ozamiz City'), 2);
      expect(countOf('Clarin'), 1);
    });

    test('omits plans with no saved timestamp from the period', () {
      final window = TripTrendWindow.monthly(2026);
      final snapshot = TripPlannerAnalyticsSnapshot.compute(
        window: window,
        plans: [
          _row('dated', DateTime(2026, 10, 1)),
          AnalyticTripPlan(plan: _plan(id: 'bare', savedAt: DateTime(2026, 10, 1)), savedAt: null),
        ],
      );
      expect(snapshot.planCount, 1);
      expect(snapshot.skippedMissingTimestamp, 1);
    });

    test('average duration uses travel days over eligible plans', () {
      final window = TripTrendWindow.monthly(2026);
      final snapshot = TripPlannerAnalyticsSnapshot.compute(
        window: window,
        plans: [
          _row('a', DateTime(2026, 10, 1), tripDays: 2),
          _row('b', DateTime(2026, 10, 1), tripDays: 4),
        ],
      );
      expect(snapshot.averageDays, 3);
    });
  });
}
