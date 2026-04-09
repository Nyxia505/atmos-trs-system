import 'package:atmos_trs_system/models/qr_tourist_spot.dart';

const String _baseDeepLink = 'https://myapp.com/checkin';

String _deepLinkFor(String spotId) => '$_baseDeepLink?spot_id=$spotId';

final List<QrTouristSpot> mockQrTouristSpots = [
  QrTouristSpot(
    id: 'SPOT001',
    name: 'Asenso Global Gardens',
    municipality: 'Tangub City',
    qrCodeValue: _deepLinkFor('SPOT001'),
    deepLink: _deepLinkFor('SPOT001'),
    image: 'assets/images/Asenso Global Garden 1.png',
    description:
        'A beautiful botanical garden featuring diverse plant species and scenic walkways.',
  ),
  QrTouristSpot(
    id: 'SPOT002',
    name: 'Asenso Misamis Occidental Aquamarine Park',
    municipality: 'Sinacaban',
    qrCodeValue: _deepLinkFor('SPOT002'),
    deepLink: _deepLinkFor('SPOT002'),
    image: 'assets/images/sinacaban.jpg',
    description:
        'Aquamarine park with water attractions, marine exhibits, and coastal views.',
  ),
  QrTouristSpot(
    id: 'SPOT003',
    name: 'Asenso Ozamiz Wellness Park, Cotta Fort & Shrine',
    municipality: 'Ozamis City',
    qrCodeValue: _deepLinkFor('SPOT003'),
    deepLink: _deepLinkFor('SPOT003'),
    image: 'assets/images/ozamis city.webp',
    description:
        'Historic Cotta Fort, wellness park, and religious shrine in one destination.',
  ),
  QrTouristSpot(
    id: 'SPOT004',
    name: 'Tudela Highland Resort & Eco Park',
    municipality: 'Tudela',
    qrCodeValue: _deepLinkFor('SPOT004'),
    deepLink: _deepLinkFor('SPOT004'),
    image: 'assets/images/Tudela Village.webp',
    description:
        'Highland resort and eco-park with panoramic mountain views and nature trails.',
  ),
  QrTouristSpot(
    id: 'SPOT005',
    name: 'Oroquieta City Boulevard and People’s Park',
    municipality: 'Oroquieta City',
    qrCodeValue: _deepLinkFor('SPOT005'),
    deepLink: _deepLinkFor('SPOT005'),
    image: 'assets/images/oroquieta city.jpg',
    description:
        'Seaside boulevard and central park popular for walks and community events.',
  ),
  QrTouristSpot(
    id: 'SPOT006',
    name: 'St. John the Baptist Church',
    municipality: 'Jimenez',
    qrCodeValue: _deepLinkFor('SPOT006'),
    deepLink: _deepLinkFor('SPOT006'),
    image: 'assets/images/Jimenez - St. John the Baptist Church.jpg',
    description:
        'Spanish-era church known for its heritage architecture and religious significance.',
  ),
  QrTouristSpot(
    id: 'SPOT007',
    name: 'Baliangao Tourist Spot',
    municipality: 'Baliangao',
    qrCodeValue: _deepLinkFor('SPOT007'),
    deepLink: _deepLinkFor('SPOT007'),
    image: 'assets/images/Baliangao - Cabgan Island.jpg',
    description:
        'Coastal destination featuring beaches and nearby marine sanctuaries.',
  ),
];

QrTouristSpot? findMockSpotById(String spotId) {
  try {
    return mockQrTouristSpots.firstWhere((s) => s.id == spotId);
  } catch (_) {
    return null;
  }
}

