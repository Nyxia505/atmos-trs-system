import 'package:atmos_trs_system/models/visit_origin_breakdown.dart';
import 'package:atmos_trs_system/utils/visit_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('check-in origin counts drive gender, residence, and rankings', () {
    final origin = VisitOriginBreakdown(
      spotMunicipality: 'Oroquieta City',
      thisMunicipalityMale: 2,
      thisMunicipalityFemale: 1,
      foreign: const [
        OriginPlaceCount(place: 'Japan', male: 1, female: 0),
      ],
    );
    final now = DateTime(2026, 10, 16, 15);
    final stats = VisitAnalyticsSnapshot.build(
      now: now,
      range: 'This Week',
      checkIns: [
        {
          'userId': 'scanner',
          'municipality': 'Oroquieta City',
          'spot_name': 'Cotta Fort',
          'spotCategory': 'Historical',
          'timestamp': DateTime(2026, 10, 16, 14),
          'visitorCount': 4,
          'originBreakdown': origin.toMap(),
        },
        {
          'userId': 'no-origin',
          'municipality': 'Ozamis City',
          'spot_name': 'Plaza',
          'timestamp': DateTime(2026, 10, 16, 9),
          'visitorCount': 1,
        },
        {
          'userId': 'kid',
          'municipality': 'Jimenez',
          'spot_name': 'Falls',
          'timestamp': DateTime(2026, 10, 16, 11),
          'visitorCount': 1,
          'touristProfile': {
            'sex': 'Male',
            'dateOfBirth': '2012-01-01',
            'city': 'Jimenez',
            'isLocal': true,
            'localOrForeign': 'Local',
          },
        },
      ],
    );

    expect(stats.male, 4);
    expect(stats.female, 1);
    expect(stats.local, 4);
    expect(stats.foreign, 1);
    expect(stats.topOrigin, 'Oroquieta City');
    expect(stats.municipalities.first.name, 'Oroquieta City');
    expect(stats.municipalities.first.count, 4);
    expect(stats.spots.first.name, 'Cotta Fort');
    expect(stats.categories.first.name, 'Historical');
    expect(stats.peakHour, '2-3 PM');
    expect(stats.dailyAverage, 6);

    final under18 = stats.ageSeries.firstWhere((row) => row.label == '0-17');
    final adults = stats.ageSeries.firstWhere((row) => row.label == '18-24');
    expect(under18.male, 1);
    expect(adults.male, 0);
  });

  test('a profile without residence is not counted as foreign', () {
    final stats = VisitAnalyticsSnapshot.build(
      now: DateTime(2026, 10, 16),
      checkIns: const [
        {
          'visitorCount': 1,
          'timestamp': '2026-10-16T10:00:00',
          'municipality': 'Tangub City',
          'spot_name': 'Park',
        },
      ],
    );

    expect(stats.foreign, 0);
    expect(stats.local, 0);
  });

  test('categories come from the tourist spot when the check-in has none', () {
    final now = DateTime(2026, 10, 19, 12);
    final stats = VisitAnalyticsSnapshot.build(
      now: now,
      range: 'This Month',
      categoryBySpotId: const {
        'spot-beach': 'Beach',
        'spot-park': 'park',
      },
      categoryNamesByKey: const {
        'beach': 'Beach',
        'park': 'Park',
      },
      checkIns: [
        {
          'spotId': 'spot-beach',
          'timestamp': DateTime(2026, 10, 2, 9),
          'visitorCount': 3,
        },
        {
          'spotId': 'spot-park',
          'categoryId': 'park',
          'timestamp': DateTime(2026, 10, 3, 9),
          'visitorCount': 1,
        },
        {
          'spotId': 'missing',
          'timestamp': DateTime(2026, 10, 4, 9),
          'visitorCount': 1,
        },
        {
          'spotId': 'spot-beach',
          'spotCategory': 'Beach',
          'timestamp': DateTime(2026, 9, 30, 9),
          'visitorCount': 9,
        },
      ],
    );

    expect(stats.categories.map((row) => row.name).toList(), [
      'Beach',
      'Park',
      'Other',
    ]);
    expect(stats.categories.map((row) => row.count).toList(), [3, 1, 1]);
    expect(
      stats.categories.fold<int>(0, (sum, row) => sum + row.count),
      5,
    );
  });

  test('no visits in the selected period leaves categories empty', () {
    final stats = VisitAnalyticsSnapshot.build(
      now: DateTime(2026, 10, 19),
      range: 'This Month',
      checkIns: const [
        {
          'spotCategory': 'Beach',
          'timestamp': '2026-08-01T10:00:00',
          'visitorCount': 4,
        },
      ],
    );

    expect(stats.categories, isEmpty);
    expect(stats.spots, isEmpty);
    expect(stats.municipalities, isEmpty);
    expect(stats.periodVisitorCount, 0);
  });

  test('This Month arrivals use Manila dates and party headcount', () {
    final now = DateTime.utc(2026, 11, 1, 4); // 12:00 Asia/Manila
    final stats = VisitAnalyticsSnapshot.build(
      now: now,
      range: 'This Month',
      checkIns: [
        {
          'timestamp': DateTime.utc(2026, 10, 31, 16, 30), // Nov 1 00:30 Manila
          'visitorCount': 3,
          'municipality': 'Oroquieta City',
        },
        {
          'timestamp': DateTime.utc(2026, 10, 31, 15, 59), // Oct 31 23:59 Manila
          'visitorCount': 9,
          'municipality': 'Ozamis City',
        },
        {
          'checkedInAt': {
            '_seconds': DateTime.utc(2026, 11, 1, 3).millisecondsSinceEpoch ~/
                1000,
            '_nanoseconds': 0,
          },
          'visitorCount': 2,
          'municipality': 'Tangub City',
        },
      ],
    );

    expect(stats.arrivals.length, 30);
    expect(stats.arrivalLabels.first, '1');
    expect(stats.arrivals[0], 5);
    expect(stats.arrivals.fold<double>(0, (sum, v) => sum + v), 5);
    expect(stats.periodVisitorCount, 5);
    expect(
      stats.municipalities.map((row) => row.count).fold<int>(0, (a, b) => a + b),
      5,
    );
    expect(stats.unparsedCheckIns, 0);
  });

  test('This Year arrival labels match the rolling 12 months', () {
    final stats = VisitAnalyticsSnapshot.build(
      now: DateTime(2026, 11, 1, 12),
      range: 'This Year',
      checkIns: [
        {
          'timestamp': DateTime(2026, 10, 7, 9),
          'visitorCount': 4,
        },
      ],
    );

    expect(stats.arrivalLabels, [
      'Dec',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
    ]);
    expect(stats.arrivals[10], 4);
    expect(stats.arrivals[11], 0);
  });

  test('This Week includes late October when today is 1 Nov; This Month does not', () {
    final now = DateTime.utc(2026, 11, 1, 12); // 20:00 Asia/Manila 1 Nov
    final checkIns = [
      {
        'timestamp': DateTime.utc(2026, 10, 31, 8), // 16:00 Manila 31 Oct
        'visitorCount': 4,
      },
      {
        'timestamp': DateTime.utc(2026, 11, 1, 3), // 11:00 Manila 1 Nov
        'visitorCount': 2,
      },
    ];

    final week = VisitAnalyticsSnapshot.build(
      now: now,
      range: 'This Week',
      checkIns: checkIns,
    );
    final month = VisitAnalyticsSnapshot.build(
      now: now,
      range: 'This Month',
      checkIns: checkIns,
    );
    final year = VisitAnalyticsSnapshot.build(
      now: now,
      range: 'This Year',
      checkIns: checkIns,
    );

    expect(week.arrivals.fold<double>(0, (s, v) => s + v), 6);
    expect(month.arrivals.length, 30);
    expect(month.arrivals[0], 2);
    expect(month.arrivals.fold<double>(0, (s, v) => s + v), 2);
    expect(year.arrivals.fold<double>(0, (s, v) => s + v), 6);
    expect(month.arrivalPeriodLabel, contains('Nov 2026'));
  });

  test('This Month includes every day of a 31-day month and December-January', () {
    final october = VisitAnalyticsSnapshot.build(
      now: DateTime.utc(2026, 10, 16, 4),
      range: 'This Month',
      checkIns: [
        {
          'timestamp': DateTime.utc(2026, 10, 1, 16, 30), // 2 Oct 00:30 Manila
          'visitorCount': 1,
        },
        {
          'timestamp': DateTime.utc(2026, 10, 31, 15, 59), // 31 Oct 23:59 Manila
          'visitorCount': 3,
        },
      ],
    );
    expect(october.arrivals.length, 31);
    expect(october.arrivals[1], 1);
    expect(october.arrivals[30], 3);

    final january = VisitAnalyticsSnapshot.build(
      now: DateTime.utc(2027, 1, 1, 4),
      range: 'This Month',
      checkIns: [
        {
          'timestamp': DateTime.utc(2026, 12, 31, 16, 30), // 1 Jan 00:30 Manila
          'visitorCount': 5,
        },
        {
          'timestamp': DateTime.utc(2026, 12, 31, 15, 59), // 31 Dec 23:59 Manila
          'visitorCount': 9,
        },
      ],
    );
    expect(january.arrivals.length, 31);
    expect(january.arrivals[0], 5);
    expect(january.arrivals.fold<double>(0, (s, v) => s + v), 5);
  });
}
