import 'package:atmos_trs_system/utils/spot_route_destination.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:trip_plan/municipality_coordinates.dart';

void main() {
  test('usable coordinates reject zeros and non-finite values', () {
    expect(isUsableMapCoordinate(0, 0), isFalse);
    expect(isUsableMapCoordinate(null, 123.8), isFalse);
    expect(isUsableMapCoordinate(double.nan, 123.8), isFalse);
    expect(isUsableMapCoordinate(8.3347, 123.8408), isTrue);
  });

  test('each catalog spot keeps its own coordinates', () {
    final jimenez = spotMapPointFromLocalCatalogs(
      spotId: 'jimenez_st_john_the_baptist_church',
      name: 'St. John the Baptist Church',
    );
    final baliangao = spotMapPointFromLocalCatalogs(
      spotId: 'bless_amare_sunrise_beach',
      name: 'Bless Amare Sunrise Beach',
    );
    final oroquieta = spotMapPointFromLocalCatalogs(
      spotId: 'oroquieta_city_boulevard_and_peoples_park',
      name: 'Oroquieta City Boulevard',
    );

    expect(jimenez, isNotNull);
    expect(baliangao, isNotNull);
    expect(oroquieta, isNotNull);
    expect(jimenez!.latitude, closeTo(8.3347, 0.001));
    expect(baliangao!.latitude, closeTo(8.6167, 0.001));
    expect(oroquieta!.latitude, closeTo(8.4845, 0.001));
    expect(jimenez.latitude, isNot(closeTo(baliangao.latitude, 0.01)));
    expect(jimenez.longitude, isNot(closeTo(oroquieta.longitude, 0.01)));
  });

  test('known screen coordinates are used without waiting on the network', () {
    final cotta = spotMapPointFromKnownSources(
      spotId: 'ozamiz_cotta_fort_shrine',
      name: 'Cotta Fort & Shrine',
      municipality: 'Ozamiz City',
      latitude: 8.1456,
      longitude: 123.8425,
    );
    expect(cotta, isNotNull);
    expect(cotta!.latitude, closeTo(8.1456, 0.0001));
    expect(cotta.longitude, closeTo(123.8425, 0.0001));
    expect(cotta.spotId, 'ozamiz_cotta_fort_shrine');
  });

  test('route lists start, towns along the way, and the destination', () {
    final dest = spotMapPointFromKnownSources(
      spotId: 'ozamiz_cotta_fort_shrine',
      name: 'Cotta Fort & Shrine',
      municipality: 'Ozamiz City',
      latitude: 8.1456,
      longitude: 123.8425,
    )!;
    final oroquieta = tripMunicipalityFor(name: 'Oroquieta City');
    final origin = getMunicipalityCoordinates(oroquieta);
    expect(origin, isNotNull);
    final places = placesAlongSpotRoute(
      originLabel: 'Your location (near Oroquieta City)',
      origin: origin!,
      dest: dest,
    );

    expect(places.startLabel, contains('Oroquieta'));
    expect(places.endLabel, 'Cotta Fort & Shrine');
    expect(places.startTown.toLowerCase(), contains('oroquieta'));
    expect(places.allTowns, isNotEmpty);
    expect(places.allTowns.first.toLowerCase(), contains('oroquieta'));
    expect(places.allTowns.last.toLowerCase(), contains('ozamiz'));
    expect(places.viaTowns, isNotEmpty);
    expect(
      places.viaTowns.map((t) => t.toLowerCase()),
      isNot(contains(places.startTown.toLowerCase())),
    );
  });

  test('same-town route has a start and end without extra via towns', () {
    final dest = SpotMapPoint(
      spotId: 'ozamiz_cotta_fort_shrine',
      name: 'Cotta Fort & Shrine',
      latitude: 8.1456,
      longitude: 123.8425,
      municipality: 'Ozamiz City',
    );
    final places = placesAlongSpotRoute(
      originLabel: 'Your location',
      origin: const LatLng(8.1482, 123.8405),
      dest: dest,
    );
    expect(places.hasViaTowns, isFalse);
    expect(places.endLabel, 'Cotta Fort & Shrine');
    expect(places.allTowns, isNotEmpty);
  });

  test('trip municipalities resolve by name, not a hardcoded town', () {
    expect(tripMunicipalityFor(name: 'Jimenez').shortName, 'Jimenez');
    expect(tripMunicipalityFor(name: 'Baliangao').shortName, 'Baliangao');
    expect(
      tripMunicipalityFor(name: 'Ozamiz City').shortName.toLowerCase(),
      contains('ozamiz'),
    );
    final nearOzamiz = nearestTripMunicipality(const LatLng(8.1482, 123.8405));
    expect(nearOzamiz.shortName.toLowerCase(), contains('ozamiz'));
  });
}
