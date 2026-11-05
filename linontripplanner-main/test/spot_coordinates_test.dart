import 'package:flutter_test/flutter_test.dart';
import 'package:trip_plan/utils/spot_coordinates.dart';

void main() {
  test('accepts finite WGS84 coordinates', () {
    expect(isValidSpotCoordinate(8.1485, 123.8412), isTrue);
    expect(isValidSpotCoordinate(-90, -180), isTrue);
    expect(isValidSpotCoordinate(90, 180), isTrue);
  });

  test('rejects missing, non-finite, or out-of-range coordinates', () {
    expect(isValidSpotCoordinate(null, 123.84), isFalse);
    expect(isValidSpotCoordinate(8.14, null), isFalse);
    expect(isValidSpotCoordinate(91, 123), isFalse);
    expect(isValidSpotCoordinate(8, 181), isFalse);
    expect(isValidSpotCoordinate(double.nan, 123), isFalse);
    expect(isValidSpotCoordinate(8, double.infinity), isFalse);
  });

  test('picker center prefers saved coordinates over municipality', () {
    final center = initialSpotPickerCenter(
      latitude: 8.1485,
      longitude: 123.8412,
      municipalityName: 'Ozamiz City',
    );
    expect(center.latitude, closeTo(8.1485, 1e-9));
    expect(center.longitude, closeTo(123.8412, 1e-9));
    expect(initialSpotPickerZoom(latitude: 8.1485, longitude: 123.8412), 15);
  });

  test('picker center uses municipality when no saved coordinates', () {
    final center = initialSpotPickerCenter(municipalityName: 'Ozamiz City');
    expect(center.latitude, isNot(8.45));
    expect(center.longitude, inInclusiveRange(123.25, 123.95));
    expect(initialSpotPickerZoom(municipalityName: 'Ozamiz City'), 13);
  });

  test('picker center falls back to Misamis Occidental', () {
    final center = initialSpotPickerCenter();
    final fallback = misamisOccidentalOsmCenter();
    expect(center.latitude, fallback.latitude);
    expect(center.longitude, fallback.longitude);
    expect(initialSpotPickerZoom(), 9);
  });
}
