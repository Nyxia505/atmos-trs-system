import 'package:flutter_test/flutter_test.dart';
import 'package:trip_plan/data.dart';
import 'package:trip_plan/municipality_performance.dart';
import 'package:trip_plan/utils/trip_planner_analytics.dart';

TouristSpot _spot({
  required String location,
  String name = 'Cotta Fort',
}) {
  return TouristSpot(
    name: name,
    priceRange: '',
    imagePath: '',
    location: location,
    rating: 4,
    description: '',
    type: 'Culture',
  );
}

Municipality _muni(String name) {
  return municipalities.firstWhere((m) => m.name == name);
}

void main() {
  test('Ozamis / Ozamiz aliases map to Ozamiz City', () {
    final oz = _muni('Ozamiz City');
    expect(touristSpotBelongsToMunicipality(_spot(location: 'Ozamiz City'), oz), isTrue);
    expect(touristSpotBelongsToMunicipality(_spot(location: 'Ozamis City'), oz), isTrue);
    expect(touristSpotBelongsToMunicipality(_spot(location: 'ozamiz'), oz), isTrue);
    expect(
      touristSpotBelongsToMunicipality(
        _spot(location: '', name: 'Cotta Beach – Ozamis City'),
        oz,
      ),
      isTrue,
    );
    expect(
      touristSpotBelongsToMunicipality(_spot(location: 'Oroquieta City'), oz),
      isFalse,
    );
  });

  test('Oroquieta provincial capital alias matches short name', () {
    final oro = _muni('Oroquieta City (Provincial Capital)');
    expect(
      touristSpotBelongsToMunicipality(_spot(location: 'Oroquieta City'), oro),
      isTrue,
    );
    expect(
      touristSpotBelongsToMunicipality(_spot(location: 'Jimenez'), oro),
      isFalse,
    );
  });

  test('each municipality keeps its own spots', () {
    for (final municipality in municipalities) {
      final own = _spot(location: municipality.shortName);
      expect(
        touristSpotBelongsToMunicipality(own, municipality),
        isTrue,
        reason: municipality.name,
      );
    }
  });

  test('monthly window fills twelve buckets including zeros', () {
    final window = TripTrendWindow.monthly(2026);
    final series = fillTrendSeries(
      savedAt: [DateTime(2026, 10, 8, 10), DateTime(2026, 10, 9, 12)],
      window: window,
    );
    expect(series, hasLength(12));
    expect(series[9].count, 2);
    expect(series.where((p) => p.count == 0).length, 11);
  });

  test('daily window keeps actual day counts, not a lumped month total', () {
    final window = TripTrendWindow.daily(2026, 10);
    final series = fillTrendSeries(
      savedAt: [
        DateTime(2026, 10, 1, 8),
        DateTime(2026, 10, 1, 18),
        DateTime(2026, 10, 15, 9),
      ],
      window: window,
    );
    expect(series.length, 31);
    expect(series[0].count, 2);
    expect(series[14].count, 1);
    expect(series.fold<int>(0, (sum, p) => sum + p.count), 3);
  });

  test('arrival municipality aliases resolve Ozamis to Ozamiz City', () {
    final arrival = RecordedArrival(
      at: DateTime(2026, 10, 1),
      municipalityName: 'Ozamis City',
      spotName: 'Cotta',
    );
    expect(
      arrivalBelongsToMunicipality(arrival, _muni('Ozamiz City')),
      isTrue,
    );
    expect(
      arrivalBelongsToMunicipality(arrival, _muni('Oroquieta City (Provincial Capital)')),
      isFalse,
    );
  });
}
