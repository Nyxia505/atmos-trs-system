import 'package:flutter_test/flutter_test.dart';
import 'package:trip_plan/tourist_plan/tourist_travel_estimates.dart';

void main() {
  test('walking, motorcycle, and car times differ for the same road distance', () {
    const km = 10.0;
    final walk = travelMinutesForKm(km, 'Walking');
    final motorcycle = travelMinutesForKm(km, 'Motorcycle');
    final car = travelMinutesForKm(km, 'Car');

    expect(walk, greaterThan(motorcycle));
    expect(motorcycle, greaterThanOrEqualTo(car));
    expect(walk, closeTo(120, 1));
    expect(formatHoursMinutes(walk), contains('hr'));
    expect(formatHoursMinutes(car), contains('min'));
  });
}
