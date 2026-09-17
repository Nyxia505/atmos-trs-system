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
        '191-hectare highland eco-tourism park in Barangay Hoyohoy. Themed international gardens and Panguil Bay views. Daily 6:00 AM–6:00 PM; weekdays ₱50, weekends ₱100.',
  ),
  QrTouristSpot(
    id: 'SPOT002',
    name: 'AMORAP — Asenso Misamis Occidental Resort and Aquamarine Park',
    municipality: 'Sinacaban',
    qrCodeValue: _deepLinkFor('SPOT002'),
    deepLink: _deepLinkFor('SPOT002'),
    image: 'assets/images/Amorap.png',
    description:
        'Barangay Libertad Bajo, Sinacaban. Resort grounds and all-day dining generally open daily; entrance fees vary by activity or accommodation.',
  ),
  QrTouristSpot(
    id: 'SPOT003',
    name: 'Asenso Ozamiz Wellness Park',
    municipality: 'Ozamis City',
    qrCodeValue: _deepLinkFor('SPOT003'),
    deepLink: _deepLinkFor('SPOT003'),
    image: 'assets/images/ozamis city.webp',
    description:
        'Port Road wellness park in Barangay Baybay Triunfo, near Ozamiz Port. Free admission; playground ₱20, mini-gym ₱50. Night cafés Fri–Sun 5:00 PM–11:30 PM.',
  ),
  QrTouristSpot(
    id: 'SPOT008',
    name: 'Cotta Fort & Shrine',
    municipality: 'Ozamis City',
    qrCodeValue: _deepLinkFor('SPOT008'),
    deepLink: _deepLinkFor('SPOT008'),
    image: "assets/images/Cotta Fort & Shrine.jpg",
    description:
        'Historic stone fort (1755) and Cotta Shrine in Barangay Baybay Triunfo. Free admission; typically open daily 8:00 AM–5:00 PM. Dress modestly.',
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
    name: 'Oroquieta City Plaza',
    municipality: 'Oroquieta City',
    qrCodeValue: _deepLinkFor('SPOT005'),
    deepLink: _deepLinkFor('SPOT005'),
    image: 'assets/images/oroquieta City plaza.jpeg',
    description:
        'Public open space with Iligan Bay views, playground, bandstand, and Rizal monument. Open 24 hours; free.',
  ),
  QrTouristSpot(
    id: 'SPOT006',
    name: 'St. John the Baptist Church',
    municipality: 'Jimenez',
    qrCodeValue: _deepLinkFor('SPOT006'),
    deepLink: _deepLinkFor('SPOT006'),
    image: 'assets/images/Jimenez.png',
    description:
        'Church of St. John the Baptist (Jimenez Church), Barangay Poblacion. National Cultural Treasure with painted wooden ceilings and coral stone facade. Free; typically open daily 6:00 AM–5:00 PM.',
  ),
  QrTouristSpot(
    id: 'SPOT007',
    name: 'Bless Amare Sunrise Beach',
    municipality: 'Baliangao',
    qrCodeValue: _deepLinkFor('SPOT007'),
    deepLink: _deepLinkFor('SPOT007'),
    image: 'assets/images/Baliangao.png',
    description:
        'Baliangao Beach, Barangay Tugas. Day use 6 AM–5 PM. Cottages and tables for rent. Overnight accommodations 24 hours.',
  ),
];

QrTouristSpot? findMockSpotById(String spotId) {
  try {
    return mockQrTouristSpots.firstWhere((s) => s.id == spotId);
  } catch (_) {
    return null;
  }
}

