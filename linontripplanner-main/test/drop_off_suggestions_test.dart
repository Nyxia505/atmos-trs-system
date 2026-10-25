import 'package:flutter_test/flutter_test.dart';
import 'package:trip_plan/algorithms/drop_off_suggestions.dart';
import 'package:trip_plan/data.dart';
import 'package:trip_plan/services/bus_location_store.dart';

void main() {
  test('dropOffSummaryForSpot reports missing hubs when store is empty', () {
    BusLocationStore.instance.locations.clear();
    const spot = TouristSpot(
      name: 'Test Falls',
      priceRange: '',
      imagePath: '',
      location: 'Oroquieta City',
      rating: 0,
      description: '',
      type: 'Nature',
      latitude: 8.48,
      longitude: 123.80,
    );
    expect(
      dropOffSummaryForSpot(spot: spot),
      'No verified drop-off point available.',
    );
  });

  test('suggestDropOffsForSpot returns empty without coordinates', () {
    const spot = TouristSpot(
      name: 'No Coords',
      priceRange: '',
      imagePath: '',
      location: 'Jimenez',
      rating: 0,
      description: '',
      type: 'Culture',
    );
    expect(suggestDropOffsForSpot(spot: spot), isEmpty);
  });
}
