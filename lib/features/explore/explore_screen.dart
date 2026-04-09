import 'package:flutter/material.dart';

export 'explore_map_screen.dart' show ExploreScreen;

const Color kPrimaryOrange = Color(0xFFF97316);
const Color kPinBlue = Color(0xFF3B82F6);
const Color kTextDark = Color(0xFF1F2937);
const Color kTextMuted = Color(0xFF6B7280);

const String kHeroMapImage = 'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?w=800&q=80';

class CategoryItem {
  final String label;
  final IconData icon;
  const CategoryItem({required this.label, required this.icon});
}

const List<CategoryItem> kCategories = [
  CategoryItem(label: 'Beach', icon: Icons.beach_access),
  CategoryItem(label: 'Falls', icon: Icons.water_drop),
  CategoryItem(label: 'Historical', icon: Icons.account_balance),
  CategoryItem(label: 'Mountain', icon: Icons.terrain),
  CategoryItem(label: 'Resort', icon: Icons.pool),
  CategoryItem(label: 'Park', icon: Icons.park),
  CategoryItem(label: 'Church', icon: Icons.church),
  CategoryItem(label: 'All', icon: Icons.apps),
];

class TouristSpot {
  final String id;
  final String name;
  final String category;
  final String imageUrl;
  final double distance;
  final double rating;
  final int reviewCount;
  final String description;
  final String city;
  final String? vrLink;
  final String? vrPanoramaUrl;
  final double latitude;
  final double longitude;
  final bool hasVR;
  bool isSaved;

  TouristSpot({
    required this.id,
    required this.name,
    required this.category,
    required this.imageUrl,
    required this.distance,
    required this.rating,
    this.reviewCount = 0,
    this.description = '',
    this.city = '',
    this.vrLink,
    this.vrPanoramaUrl,
    this.latitude = 0,
    this.longitude = 0,
    this.hasVR = false,
    this.isSaved = false,
  });

  factory TouristSpot.fromFirestore(Map<String, dynamic> data, String docId) {
    final vrLinkRaw = data['vrLink'] ?? data['vr_link'];
    final panoRaw = data['vrPanoramaUrl'] ?? data['vr_panorama_url'];
    final vrLinkStr = vrLinkRaw?.toString();
    final panoStr = panoRaw?.toString();
    return TouristSpot(
      id: docId,
      name: data['name'] ?? 'Unknown',
      category: data['category'] ?? 'Beach',
      imageUrl: data['imageUrl'] ?? data['image'] ?? '',
      distance: (data['distance'] ?? 0).toDouble(),
      rating: (data['rating'] ?? 4.5).toDouble(),
      reviewCount: (data['reviewCount'] ?? 0) as int,
      description: data['description'] ?? '',
      city: data['city'] ?? '',
      vrLink: vrLinkStr != null && vrLinkStr.isNotEmpty ? vrLinkStr : null,
      vrPanoramaUrl: panoStr != null && panoStr.isNotEmpty ? panoStr : null,
      latitude: (data['latitude'] ?? 0).toDouble(),
      longitude: (data['longitude'] ?? 0).toDouble(),
      hasVR: data['hasVR'] == true ||
          (vrLinkStr != null && vrLinkStr.isNotEmpty) ||
          (panoStr != null && panoStr.isNotEmpty),
    );
  }
}

// ============================================================================
// VR TOUR ENABLED SPOTS — 360° VR tours (see also kMockSpots for image-only pins)
// VR Implementation Options:
// 1. vrPanoramaUrl - Direct panoramic image URL for in-app 360Â° viewer
// 2. vrLink - External link to Marzipano/TinyHost hosted tours
// When vrPanoramaUrl is set, the in-app viewer is used (preferred)
// When only vrLink is set, it opens in external browser
// ============================================================================
final List<TouristSpot> kVRTourSpots = [
  TouristSpot(
    id: 'vr-1',
    name: 'Asenso Global Gardens',
    category: 'Park',
    imageUrl: 'assets/images/Asenso Global Garden 1.png',
    distance: 18.5,
    rating: 4.8,
    description: 'A beautiful botanical garden featuring diverse plant species, scenic walkways, and relaxing green spaces. Perfect for nature lovers and family outings.',
    city: 'Tangub City',
    vrPanoramaUrl: 'assets/images/Asenso Global Garden 1.png',
    vrLink: '',
    hasVR: true,
    latitude: 8.0656,
    longitude: 123.7564,
  ),
  TouristSpot(
    id: 'vr-2',
    name: 'Asenso Misamis Occidental Aquamarine Park',
    category: 'Park',
    imageUrl: 'assets/images/sinacaban.jpg',
    distance: 25.3,
    rating: 4.7,
    description: 'A stunning aquamarine park featuring water attractions, marine exhibits, and recreational facilities for the whole family.',
    city: 'Sinacaban',
    vrPanoramaUrl: 'assets/images/sinacaban.jpg',
    vrLink: '',
    hasVR: true,
    latitude: 8.2847,
    longitude: 123.8456,
  ),
  TouristSpot(
    id: 'vr-3',
    name: 'Asenso Ozamiz Wellness Park, Cotta Fort & Shrine',
    category: 'Historical',
    imageUrl: 'assets/images/ozamis city.webp',
    distance: 12.8,
    rating: 4.9,
    description: 'A historic landmark featuring the famous Cotta Fort, a wellness park, and religious shrine. Experience history, spirituality, and relaxation in one destination.',
    city: 'Ozamis City',
    vrPanoramaUrl: 'assets/images/ozamis city.webp',
    vrLink: '',
    hasVR: true,
    latitude: 8.1481,
    longitude: 123.8411,
  ),
  TouristSpot(
    id: 'vr-4',
    name: 'Tudela Highland Resort & Eco Park',
    category: 'Resort',
    imageUrl: 'assets/images/Tudela Village.webp',
    distance: 35.6,
    rating: 4.6,
    description: 'A highland resort and eco-park offering breathtaking mountain views, cool climate, nature trails, and eco-friendly accommodations.',
    city: 'Tudela',
    vrPanoramaUrl: 'assets/images/Tudela Village.webp',
    vrLink: '',
    hasVR: true,
    latitude: 8.1833,
    longitude: 123.8667,
  ),
  TouristSpot(
    id: 'vr-6',
    name: 'St. John The Baptist Church',
    category: 'Church',
    imageUrl: 'assets/images/Jimenez - St. John the Baptist Church.jpg',
    distance: 42.1,
    rating: 4.4,
    description: 'A historic Spanish-colonial era church dedicated to St. John the Baptist. Features beautiful religious architecture and rich cultural heritage.',
    city: 'Jimenez',
    vrPanoramaUrl: 'assets/images/Jimenez - St. John the Baptist Church.jpg',
    vrLink: '',
    hasVR: true,
    latitude: 8.3347,
    longitude: 123.8408,
  ),
  TouristSpot(
    id: 'vr-7',
    name: 'Sapang Dalaga Floating Cottages',
    category: 'Resort',
    imageUrl: 'assets/images/Sapang Dalaga.png',
    distance: 32.1,
    rating: 4.9,
    description: 'Experience the stunning Sapang Dalaga with its iconic Cristo Redentor statue overlooking the bay. Features floating cottages, inflatable water playground, and breathtaking sunset views. A must-visit destination in Misamis Occidental!',
    city: 'Sapang Dalaga',
    vrPanoramaUrl: 'assets/images/Sapang Dalaga.png',
    vrLink: '',
    hasVR: true,
    latitude: 8.2833,
    longitude: 123.6167,
  ),
];

// ============================================================================
// OTHER TOURIST SPOTS - Regular spots without VR tours (yet)
// ============================================================================
final List<TouristSpot> kMockSpots = [
  // VR-enabled spots first
  ...kVRTourSpots,
  // Other tourist spots (with coordinates so they show as pins on municipality map)
  TouristSpot(id: '1', name: 'Baliangao Protected Landscape', category: 'Beach', imageUrl: 'assets/images/Baliangao - Cabgan Island.jpg', distance: 45.2, rating: 4.8, description: 'Beautiful protected marine sanctuary with pristine white sand beaches and diverse marine life.', city: 'Baliangao', latitude: 8.6682, longitude: 123.6002, vrPanoramaUrl: 'assets/images/Baliangao - Cabgan Island.jpg', hasVR: true),
  TouristSpot(id: '2', name: 'Sapang Dalaga Water Park', category: 'Resort', imageUrl: 'assets/images/Sapang Dalaga.png', distance: 32.1, rating: 4.8, description: 'Exciting inflatable water playground featuring obstacle courses, trampolines, slides, and more! Perfect for adventure seekers and families.', city: 'Sapang Dalaga', latitude: 8.2833, longitude: 123.6167, vrPanoramaUrl: 'assets/images/Sapang Dalaga.png', hasVR: true),
  TouristSpot(id: '2b', name: 'Sapang Dalaga Beach Activities', category: 'Beach', imageUrl: 'assets/images/Sapang Dalaga.png', distance: 32.1, rating: 4.6, description: 'Enjoy fun beach activities including unicorn floats, paddle boats, and swimming in the crystal-clear waters of Sapang Dalaga bay.', city: 'Sapang Dalaga', latitude: 8.2833, longitude: 123.6167, vrPanoramaUrl: 'assets/images/SaPang Dalaga - Caluya Bay with Floating Playground.jpg', hasVR: true),
  TouristSpot(id: '3', name: 'Mount Malindang Range Natural Park', category: 'Mountain', imageUrl: 'assets/images/Piduan Falls Donvic.jpg', distance: 55.8, rating: 4.6, description: 'Highest peak in Misamis Occidental with diverse wildlife and endemic species.', city: 'Don Victoriano Chiongbian', latitude: 8.2542, longitude: 123.5642, vrPanoramaUrl: 'assets/images/Piduan Falls Donvic.jpg', hasVR: true),
  TouristSpot(id: '4', name: 'Hoyohoy Highland Stone Chapel', category: 'Historical', imageUrl: 'assets/images/Asenso Global Garden 1.png', distance: 18.3, rating: 4.5, description: 'Scenic highlands with panoramic views and a beautiful stone chapel.', city: 'Tangub City', latitude: 8.0656, longitude: 123.7564, vrPanoramaUrl: 'assets/images/Asenso Global Garden 1.png', hasVR: true),
  TouristSpot(id: '5', name: 'Duka Bay Beach Resort', category: 'Beach', imageUrl: 'https://images.unsplash.com/photo-1510414842594-a61c69b5ae57?w=400', distance: 22.7, rating: 4.4, description: 'Quiet beach perfect for relaxation, snorkeling, and water activities.', city: 'Medina'),
  TouristSpot(id: '6', name: 'Immaculate Conception Cathedral', category: 'Church', imageUrl: 'assets/images/ozamis city.webp', distance: 12.4, rating: 4.2, description: 'Historic Spanish-era cathedral with beautiful religious architecture.', city: 'Ozamis City', latitude: 8.1481, longitude: 123.8411, vrPanoramaUrl: 'assets/images/ozamis city.webp', hasVR: true),
  TouristSpot(id: '7', name: 'Lake Duminagat', category: 'Mountain', imageUrl: 'assets/images/clarin.jpg', distance: 48.5, rating: 4.3, description: 'A serene crater lake nestled in the mountains, perfect for hiking and nature appreciation.', city: 'Clarin', latitude: 8.2024, longitude: 123.8582, vrPanoramaUrl: 'assets/images/clarin.jpg', hasVR: true),
  TouristSpot(id: '9', name: 'Aloran Viewpoint', category: 'Mountain', imageUrl: 'assets/images/AMORAP.jpg', distance: 20.0, rating: 4.5, description: 'Scenic landscapes and welcoming communities in Aloran.', city: 'Aloran', latitude: 8.4146, longitude: 123.8222, vrPanoramaUrl: 'assets/images/AMORAP.jpg', hasVR: true),
  TouristSpot(id: '10', name: 'Calamba Green Hills', category: 'Mountain', imageUrl: 'assets/images/CALAMBA.jpg', distance: 22.0, rating: 4.5, description: 'Rolling forested hills and palm trees in Calamba.', city: 'Calamba', latitude: 8.5587, longitude: 123.6422, vrPanoramaUrl: 'assets/images/CALAMBA.jpg', hasVR: true),
  TouristSpot(id: '11', name: 'Concepcion Falls', category: 'Falls', imageUrl: 'assets/images/conception.png', distance: 30.0, rating: 4.6, description: 'Multi-tiered waterfalls and rocky rivers surrounded by jungle.', city: 'Concepcion', latitude: 8.3254, longitude: 123.6842, vrPanoramaUrl: 'assets/images/conception.png', hasVR: true),
  TouristSpot(id: '12', name: 'Plaridel Resort', category: 'Resort', imageUrl: 'assets/images/PLARIDEL.jpg', distance: 35.0, rating: 4.4, description: 'Tropical pool resort with thatched bridges and clear blue waters.', city: 'Plaridel', latitude: 8.6224, longitude: 123.7122, vrPanoramaUrl: 'assets/images/PLARIDEL.jpg', hasVR: true),
  TouristSpot(id: '13', name: 'Lopez Jaena Beachfront', category: 'Beach', imageUrl: 'assets/images/Panaon.webp', distance: 40.0, rating: 4.3, description: 'Coastal living and beaches in Lopez Jaena.', city: 'Lopez Jaena', latitude: 8.5524, longitude: 123.7652, vrPanoramaUrl: 'assets/images/Panaon.webp', hasVR: true),
  TouristSpot(id: '14', name: 'Panaon Seaside', category: 'Beach', imageUrl: 'assets/images/Panaon.webp', distance: 42.0, rating: 4.3, description: 'Seaside town with natural attractions in Panaon.', city: 'Panaon', latitude: 8.3682, longitude: 123.8622, vrPanoramaUrl: 'assets/images/Panaon.webp', hasVR: true),
  // Oroquieta City tourist spots — pinpointed on Oroquieta City map; tap marker to open detail with image
  TouristSpot(id: 'oro-1', name: 'El Triunfo Beach', category: 'Beach', imageUrl: 'assets/images/el triunfo.png', distance: 5.2, rating: 4.6, reviewCount: 128, description: 'Pristine beach with clear waters and scenic views. Nipa huts and overwater resort.', city: 'Oroquieta City', latitude: 8.4722, longitude: 123.7988),
  TouristSpot(id: 'oro-2', name: 'Oroquieta City Capitol', category: 'Government', imageUrl: 'assets/images/capitol.webp', distance: 0.3, rating: 4.4, reviewCount: 89, description: 'Provincial capitol building and seat of the provincial government of Misamis Occidental.', city: 'Oroquieta City', latitude: 8.4861, longitude: 123.8042),
  TouristSpot(id: 'oro-3', name: 'Lumantas Riverside Garden', category: 'Park', imageUrl: 'assets/images/lumantas river side garden.webp', distance: 2.1, rating: 4.5, reviewCount: 56, description: 'Scenic riverside garden with lush greenery and peaceful ambiance.', city: 'Oroquieta City', latitude: 8.4788, longitude: 123.8012),
  TouristSpot(id: 'oro-4', name: 'Oroquieta City Plaza', category: 'Park', imageUrl: 'assets/images/oroquieta City plaza.jpeg', distance: 0.2, rating: 4.5, reviewCount: 72, description: 'Sprawling city plaza with green lawns, pathways, and waterfront promenade.', city: 'Oroquieta City', latitude: 8.4845, longitude: 123.8038, vrLink: 'https://apricot-danica-42.tiiny.site/', hasVR: true),
  TouristSpot(id: 'oro-5', name: 'Barko-Barko House', category: 'Cultural Site', imageUrl: 'assets/images/barko-barko villaflor.webp', distance: 1.5, rating: 4.7, reviewCount: 94, description: 'Heritage house showcasing local architecture and history.', city: 'Oroquieta City', latitude: 8.4840, longitude: 123.8025),
];

class MapPin {
  final double left;
  final double top;
  final Color color;
  final String? label;
  final String? spotId;
  const MapPin({required this.left, required this.top, required this.color, this.label, this.spotId});
}

const List<MapPin> kMapPins = [
  MapPin(left: 0.15, top: 0.45, color: kPrimaryOrange, label: null, spotId: '1'),
  MapPin(left: 0.55, top: 0.25, color: kPrimaryOrange, label: 'Azure Coast', spotId: '3'),
  MapPin(left: 0.35, top: 0.65, color: kPrimaryOrange, label: null, spotId: '2'),
];
