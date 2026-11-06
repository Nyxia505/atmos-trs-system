import 'package:atmos_trs_system/models/tourist_spot.dart';
import 'package:atmos_trs_system/utils/tourist_spot_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TouristSpotMetrics', () {
    test('Active status matches QR allowlist', () {
      expect(TouristSpotMetrics.isActiveStatus('Active'), isTrue);
      expect(TouristSpotMetrics.isActiveStatus('active'), isTrue);
      expect(TouristSpotMetrics.isActiveStatus('published'), isTrue);
      expect(TouristSpotMetrics.isActiveStatus(''), isTrue);
      expect(TouristSpotMetrics.isActiveStatus('Inactive'), isFalse);
      expect(TouristSpotMetrics.isActiveStatus('draft'), isFalse);
      expect(TouristSpotMetrics.isActiveStatus('closed'), isFalse);
    });

    test('province active total equals sum of LGU actives', () {
      final spots = [
        {'id': 'a', 'municipalityId': 'oroquieta', 'status': 'Active'},
        {'id': 'b', 'municipalityId': 'oroquieta', 'status': 'Inactive'},
        {'id': 'c', 'municipalityId': 'jimenez', 'status': 'published'},
        {'id': 'd', 'municipalityId': 'ozamiz', 'status': 'Active'},
        {'id': 'e', 'municipalityId': 'ozamiz', 'status': 'draft'},
      ];
      final province = TouristSpotMetrics.countMaps(
        spots,
        kind: SpotCountKind.active,
      );
      final oro = TouristSpotMetrics.countMaps(
        spots,
        kind: SpotCountKind.active,
        municipalityId: 'oroquieta',
      );
      final jim = TouristSpotMetrics.countMaps(
        spots,
        kind: SpotCountKind.active,
        municipalityId: 'jimenez',
      );
      final oza = TouristSpotMetrics.countMaps(
        spots,
        kind: SpotCountKind.active,
        municipalityId: 'ozamiz',
      );
      expect(province, 3);
      expect(oro + jim + oza, province);
    });

    test('TouristSpot models use same Active rule (no zero-active fallback)', () {
      final spots = [
        TouristSpot(
          id: '1',
          name: 'A',
          municipality: 'Jimenez',
          municipalityId: 'jimenez',
          category: 'Beach',
          description: '',
          rating: 0,
          latitude: 0,
          longitude: 0,
          status: 'inactive',
          visitors: 0,
        ),
        TouristSpot(
          id: '2',
          name: 'B',
          municipality: 'Jimenez',
          municipalityId: 'jimenez',
          category: 'Beach',
          description: '',
          rating: 0,
          latitude: 0,
          longitude: 0,
          status: 'Active',
          visitors: 0,
        ),
      ];
      expect(
        TouristSpotMetrics.countModels(spots, kind: SpotCountKind.active),
        1,
      );
      expect(
        TouristSpotMetrics.countModels(spots, kind: SpotCountKind.total),
        2,
      );
    });
  });
}
