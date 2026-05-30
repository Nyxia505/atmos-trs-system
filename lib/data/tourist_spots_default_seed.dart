/// Canonical default rows for `tourist_spots`: one flagship spot per LGU in
/// Misamis Occidental. Firestore document id is [docId] (spot slug), not the
/// municipality id. [municipalityId] matches [getMisamisOccidentalMunicipalities].
import 'package:atmos_trs_system/config/vr_tour_config.dart';
class DefaultTouristSpotSeed {
  const DefaultTouristSpotSeed({
    required this.docId,
    required this.name,
    required this.municipalityId,
    required this.municipality,
    required this.category,
    required this.latitude,
    required this.longitude,
    required this.description,
    this.rating = 4.5,
    this.imageUrl,
    this.vrLink,
  });

  final String docId;
  final String name;
  final String municipalityId;
  final String municipality;
  final String category;
  final double latitude;
  final double longitude;
  final String description;
  final double rating;
  final String? imageUrl;
  final String? vrLink;
}

/// Exactly 17 docs — one per city/municipality — aligned with app mock / VR content.
const List<DefaultTouristSpotSeed> kDefaultTouristSpotSeeds = [
  DefaultTouristSpotSeed(
    docId: 'oroquieta_city_boulevard_and_peoples_park',
    name: 'Oroquieta City Boulevard And People\u2019s Park \u2013 Oroquieta City',
    municipalityId: 'oroquieta',
    municipality: 'Oroquieta City',
    category: 'Park',
    latitude: 8.4845,
    longitude: 123.8038,
    description:
        'Waterfront boulevard and people\u2019s park with open green space, sea views, and gathering areas.',
    rating: 4.5,
    imageUrl: 'assets/images/oroquieta City plaza.jpeg',
    vrLink: kOroquietaCityPlazaVrUrl,
  ),
  DefaultTouristSpotSeed(
    docId: 'ozamiz_cotta_fort_wellness_park',
    name: 'Asenso Ozamiz Wellness Park, Cotta Fort & Shrine \u2013 Ozamis City',
    municipalityId: 'ozamiz',
    municipality: 'Ozamis City',
    category: 'Historical',
    latitude: 8.1481,
    longitude: 123.8411,
    description:
        'Historic Cotta Fort, wellness park, and religious shrine along the bay.',
    rating: 4.9,
    imageUrl: 'assets/images/ozamis city.webp',
  ),
  DefaultTouristSpotSeed(
    docId: 'tangub_asenso_global_gardens',
    name: 'Asenso Global Gardens \u2013 Tangub City',
    municipalityId: 'tangub',
    municipality: 'Tangub City',
    category: 'Park',
    latitude: 8.0656,
    longitude: 123.7564,
    description:
        'Botanical garden with diverse plants, scenic walkways, and relaxing green spaces.',
    rating: 4.8,
    imageUrl: 'assets/images/Asenso Global Garden 1.png',
  ),
  DefaultTouristSpotSeed(
    docId: 'aloran_viewpoint',
    name: 'Aloran Viewpoint',
    municipalityId: 'aloran',
    municipality: 'Aloran',
    category: 'Mountain',
    latitude: 8.4146,
    longitude: 123.8222,
    description: 'Scenic landscapes and welcoming communities in Aloran.',
    rating: 4.5,
    imageUrl:
        'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=800',
  ),
  DefaultTouristSpotSeed(
    docId: 'baliangao_protected_landscape',
    name: 'Baliangao Protected Landscape',
    municipalityId: 'baliangao',
    municipality: 'Baliangao',
    category: 'Beach',
    latitude: 8.6682,
    longitude: 123.6002,
    description:
        'Protected marine sanctuary with white sand beaches and rich marine life.',
    rating: 4.8,
    imageUrl: 'assets/images/Baliangao - Cabgan Island.jpg',
  ),
  DefaultTouristSpotSeed(
    docId: 'bonifacio_mountain_overlook',
    name: 'Bonifacio Mountain Overlook',
    municipalityId: 'bonifacio',
    municipality: 'Bonifacio',
    category: 'Mountain',
    latitude: 8.4794,
    longitude: 123.7222,
    description: 'Highland views and cool breezes overlooking Bonifacio town.',
    rating: 4.4,
    imageUrl:
        'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?w=400',
  ),
  DefaultTouristSpotSeed(
    docId: 'calamba_green_hills',
    name: 'Calamba Green Hills',
    municipalityId: 'calamba',
    municipality: 'Calamba',
    category: 'Mountain',
    latitude: 8.5587,
    longitude: 123.6422,
    description: 'Rolling forested hills and palm trees in Calamba.',
    rating: 4.5,
    imageUrl: 'assets/images/CALAMBA.jpg',
  ),
  DefaultTouristSpotSeed(
    docId: 'clarin_lake_duminagat',
    name: 'Lake Duminagat',
    municipalityId: 'clarin',
    municipality: 'Clarin',
    category: 'Mountain',
    latitude: 8.2024,
    longitude: 123.8582,
    description:
        'Serene crater lake in the mountains — hiking and nature appreciation.',
    rating: 4.3,
    imageUrl: 'assets/images/clarin.jpg',
  ),
  DefaultTouristSpotSeed(
    docId: 'concepcion_falls',
    name: 'Concepcion Falls',
    municipalityId: 'concepcion',
    municipality: 'Concepcion',
    category: 'Falls',
    latitude: 8.3254,
    longitude: 123.6842,
    description: 'Multi-tiered waterfalls and rocky rivers surrounded by jungle.',
    rating: 4.6,
    imageUrl: 'assets/images/conception.png',
  ),
  DefaultTouristSpotSeed(
    docId: 'dvc_mount_malindang_natural_park',
    name: 'Mount Malindang Range Natural Park',
    municipalityId: 'dvc',
    municipality: 'Don Victoriano Chiongbian',
    category: 'Mountain',
    latitude: 8.2542,
    longitude: 123.5642,
    description:
        'Highest peak in Misamis Occidental with diverse wildlife and endemic species.',
    rating: 4.6,
    imageUrl: 'assets/images/Piduan Falls Donvic.jpg',
  ),
  DefaultTouristSpotSeed(
    docId: 'jimenez_st_john_the_baptist_church',
    name: 'St John The Baptist Church \u2013 Jimenez',
    municipalityId: 'jimenez',
    municipality: 'Jimenez',
    category: 'Church',
    latitude: 8.3347,
    longitude: 123.8408,
    description:
        'Historic Spanish-colonial church with beautiful religious architecture.',
    rating: 4.4,
    imageUrl: 'assets/images/Jimenez - St. John the Baptist Church.jpg',
  ),
  DefaultTouristSpotSeed(
    docId: 'lopez_jaena_beachfront',
    name: 'Lopez Jaena Beachfront',
    municipalityId: 'lopezjaena',
    municipality: 'Lopez Jaena',
    category: 'Beach',
    latitude: 8.5524,
    longitude: 123.7652,
    description: 'Coastal living and beaches in Lopez Jaena.',
    rating: 4.3,
    imageUrl: 'assets/images/Panaon.webp',
  ),
  DefaultTouristSpotSeed(
    docId: 'panaon_seaside',
    name: 'Panaon Seaside',
    municipalityId: 'panaon',
    municipality: 'Panaon',
    category: 'Beach',
    latitude: 8.3682,
    longitude: 123.8622,
    description: 'Seaside town with natural attractions in Panaon.',
    rating: 4.3,
    imageUrl: 'assets/images/Panaon.webp',
  ),
  DefaultTouristSpotSeed(
    docId: 'plaridel_resort',
    name: 'Plaridel Resort',
    municipalityId: 'plaridel',
    municipality: 'Plaridel',
    category: 'Resort',
    latitude: 8.6224,
    longitude: 123.7122,
    description:
        'Tropical pool resort with thatched bridges and clear blue waters.',
    rating: 4.4,
    imageUrl: 'assets/images/PLARIDEL.jpg',
  ),
  DefaultTouristSpotSeed(
    docId: 'sapang_dalaga_floating_cottages',
    name: 'Sapang Dalaga Floating Cottages',
    municipalityId: 'sapangdalaga',
    municipality: 'Sapang Dalaga',
    category: 'Resort',
    latitude: 8.2833,
    longitude: 123.6167,
    description:
        'Floating cottages, Cristo Redentor overlook, and sunset views on the bay.',
    rating: 4.9,
    imageUrl: 'assets/images/Sapang Dalaga.png',
  ),
  DefaultTouristSpotSeed(
    docId: 'sinacaban_asenso_aquamarine_park',
    name: 'AMORAP \u2013 Asenso Misamis Occidental Recreation and Adventure Park',
    municipalityId: 'sinacaban',
    municipality: 'Sinacaban',
    category: 'Park',
    latitude: 8.2847,
    longitude: 123.8456,
    description:
        'Maldives-inspired eco-luxury destination with overwater villas, lagoons, and coastal recreation.',
    rating: 4.7,
    imageUrl: 'assets/images/AMORAP.jpg',
  ),
  DefaultTouristSpotSeed(
    docId: 'tudela_highland_resort_eco_park',
    name: 'Tudela Highland Resort & Eco Park \u2013 Tudela',
    municipalityId: 'tudela',
    municipality: 'Tudela',
    category: 'Resort',
    latitude: 8.1833,
    longitude: 123.8667,
    description:
        'Highland resort and eco-park with mountain views, trails, and cool climate.',
    rating: 4.6,
    imageUrl: 'assets/images/Tudela Village.webp',
  ),
];
