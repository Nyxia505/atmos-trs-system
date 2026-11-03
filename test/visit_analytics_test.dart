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
  });
}
