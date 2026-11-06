import 'package:atmos_trs_system/config/vr_tour_config.dart';
import 'package:atmos_trs_system/data/tourist_spots_by_municipality.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Jimenez Explore spot resolves Clear Pano VR URL', () {
    final jimenez = getMisamisOccidentalMunicipalities()
        .firstWhere((m) => m.id == 'jimenez');
    final spots = getTouristSpotsForMunicipality(jimenez);
    final church = spots.firstWhere(
      (s) =>
          s.id == 'jimenez_st_john_the_baptist_church' ||
          s.name.toLowerCase().contains('baptist'),
    );

    expect(church.hasVR, isTrue);
    expect(church.vrLink, kJimenezChurchVrUrl);
    expect(
      resolveVrTourUrl(
        vrLink: church.vrLink,
        spotId: church.id,
        spotName: church.name,
      ),
      kJimenezChurchVrUrl,
    );
    expect(
      isJimenezChurchSpot(spotId: church.id, spotName: church.name),
      isTrue,
    );
  });

  test('Legacy St John name without Jimenez still maps to church VR', () {
    expect(
      isJimenezChurchSpot(
        spotId: 'vr-6',
        spotName: 'St. John The Baptist Church',
      ),
      isTrue,
    );
    expect(
      vrUrlForSpotId('vr-6', spotName: 'St. John The Baptist Church'),
      kJimenezChurchVrUrl,
    );
  });
}
