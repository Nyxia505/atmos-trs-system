import 'package:atmos_trs_system/config/vr_tour_config.dart';
import 'package:atmos_trs_system/data/tourist_spot_image_catalog.dart';
import 'package:atmos_trs_system/features/explore/explore_data.dart' show TouristSpot;
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/maps_directions_launcher.dart';

/// A nearby place card (restaurant, hotel, café, attraction).
class NearbyPlaceCard {
  const NearbyPlaceCard({
    required this.name,
    required this.category,
    this.rating = 4.5,
    this.distanceKm = 1.2,
    this.driveMinutes,
    this.priceRange = '₱₱',
    this.imageUrl,
    this.address,
    this.description,
  });

  final String name;
  final String category;
  final double rating;
  final double distanceKm;
  final double? driveMinutes;
  final String priceRange;
  final String? imageUrl;
  final String? address;
  final String? description;

  String get directionsLabel => MapsDirectionsLauncher.placeLabel(
        name: name,
        address: address,
      );
}

/// Sample visitor review for the reviews section.
class VisitorReview {
  const VisitorReview({
    required this.author,
    required this.comment,
    required this.rating,
    this.dateLabel = 'Recent visit',
  });

  final String author;
  final String comment;
  final double rating;
  final String dateLabel;
}

/// Full destination payload for [TouristDestinationDetailScreen].
class TouristDestinationDetail {
  const TouristDestinationDetail({
    required this.spotId,
    required this.name,
    required this.municipality,
    required this.category,
    required this.rating,
    required this.reviewCount,
    required this.shortDescription,
    required this.fullDescription,
    required this.imageUrls,
    required this.openingHours,
    required this.entranceFee,
    required this.address,
    this.contactNumber,
    this.bestTimeToVisit,
    this.latitude = 0,
    this.longitude = 0,
    this.vrLink,
    this.vrPanoramaUrl,
    this.prefersQrCheckIn = true,
    this.nearbyRestaurants = const [],
    this.nearbyHotels = const [],
    this.nearbyCafes = const [],
    this.nearbyAttractions = const [],
    this.reviews = const [],
  });

  final String spotId;
  final String name;
  final String municipality;
  final String category;
  final double rating;
  final int reviewCount;
  final String shortDescription;
  final String fullDescription;
  final List<String> imageUrls;
  final String openingHours;
  final String entranceFee;
  final String address;
  final String? contactNumber;
  final String? bestTimeToVisit;
  final double latitude;
  final double longitude;
  final String? vrLink;
  final String? vrPanoramaUrl;
  final bool prefersQrCheckIn;
  final List<NearbyPlaceCard> nearbyRestaurants;
  final List<NearbyPlaceCard> nearbyHotels;
  final List<NearbyPlaceCard> nearbyCafes;
  final List<NearbyPlaceCard> nearbyAttractions;
  final List<VisitorReview> reviews;

  bool get hasCoordinates => latitude != 0 || longitude != 0;

  bool get hasVrTour =>
      resolveVrTourUrl(vrLink: vrLink, spotId: spotId, spotName: name) !=
          null ||
      (vrPanoramaUrl?.trim().isNotEmpty ?? false);

  String? get resolvedVrUrl =>
      resolveVrTourUrl(vrLink: vrLink, spotId: spotId, spotName: name) ??
      vrLink?.trim();

  String get primaryImage =>
      imageUrls.isNotEmpty ? imageUrls.first : TouristSpotImageCatalog.kDefaultAsset;

  factory TouristDestinationDetail.fromFeaturedMap(
    Map<String, dynamic> data, {
    String? resolvedImage,
  }) {
    final spotId = data['spotId']?.toString() ?? '';
    final name = data['name']?.toString() ?? 'Destination';
    final category = data['category']?.toString() ?? 'Spot';
    final rating = (data['rating'] as num?)?.toDouble() ?? 4.5;
    final short = data['description']?.toString() ?? '';
    final full = data['detail']?.toString() ?? short;
    final location = data['location']?.toString() ?? '';
    final municipality = _municipalityFromLocation(location, spotId, name);

    final explicitImage = data['image']?.toString().trim();
    final hero = resolvedImage ??
        (explicitImage != null && explicitImage.isNotEmpty
            ? explicitImage
            : TouristSpotImageCatalog.displayUrl(
                spotId: spotId,
                spotName: name,
                category: category,
              ));

    final images = <String>{
      TouristSpotImageCatalog.normalizeAssetPath(hero),
      if (data['gallery'] is List)
        ...((data['gallery'] as List).map((e) => e.toString())),
    }.where((u) => u.isNotEmpty).toList();

    final restaurants = _nearbyFromNames(
      data['nearbyRestaurants'],
      category: 'Restaurant',
      baseRating: rating,
    );
    final hotels = _nearbyFromNames(
      data['nearbyHotels'],
      category: 'Hotel',
      baseRating: rating - 0.1,
    );
    final cafes = _nearbyFromNames(
      data['nearbyCafes'] ?? _cafeNamesFromRestaurants(restaurants),
      category: 'Café',
      baseRating: 4.4,
    );
    final attractions = _nearbyFromNames(
      data['nearbyAttractions'] ?? [name, '$municipality Viewpoint'],
      category: 'Attraction',
      baseRating: rating,
    );

    return TouristDestinationDetail(
      spotId: spotId,
      name: name,
      municipality: municipality,
      category: category,
      rating: rating,
      reviewCount: 0,
      shortDescription: short,
      fullDescription: _appendCottageRates(
        full,
        data['cottageRates']?.toString(),
      ),
      imageUrls: images,
      openingHours: data['openingHours']?.toString() ?? 'Open daily',
      entranceFee: data['entranceFee']?.toString() ?? 'Varies',
      address: location,
      contactNumber: data['contactNumber']?.toString(),
      bestTimeToVisit:
          data['bestTimeToVisit']?.toString() ?? 'Dry season (Nov–May)',
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0,
      vrLink: data['vrLink']?.toString(),
      vrPanoramaUrl: data['vrPanoramaUrl']?.toString(),
      prefersQrCheckIn: data['prefersQrCheckIn'] as bool? ?? true,
      nearbyRestaurants: restaurants,
      nearbyHotels: hotels,
      nearbyCafes: cafes,
      nearbyAttractions: attractions,
      reviews: const [],
    );
  }

  static String _appendCottageRates(String full, String? cottageRates) {
    final rates = cottageRates?.trim() ?? '';
    if (rates.isEmpty) return full;
    return '$full\n\nCottages & tables: $rates';
  }

  factory TouristDestinationDetail.fromFirestoreSpot(TouristSpotFirestore spot) {
    final image = TouristSpotImageCatalog.displayUrlForSpot(spot);
    final municipality = spot.municipality.isNotEmpty
        ? spot.municipality
        : getMunicipalityIdFromName(spot.name);

    return TouristDestinationDetail(
      spotId: spot.id,
      name: spot.name,
      municipality: municipality,
      category: spot.category,
      rating: spot.rating > 0 ? spot.rating : 4.5,
      reviewCount: 0,
      shortDescription: spot.description.isNotEmpty
          ? spot.description
          : 'Explore ${spot.name} in $municipality.',
      fullDescription: spot.description.isNotEmpty
          ? spot.description
          : 'Discover ${spot.name}, a ${spot.category.toLowerCase()} destination in Misamis Occidental.',
      imageUrls: [image],
      openingHours: '8:00 AM – 5:00 PM',
      entranceFee: 'Varies by site',
      address: municipality,
      bestTimeToVisit: 'Dry season (Nov–May)',
      latitude: spot.latitude,
      longitude: spot.longitude,
      vrLink: spot.vrLink,
      prefersQrCheckIn: spot.qrValue.isNotEmpty,
      nearbyRestaurants: const [],
      nearbyHotels: const [],
      reviews: const [],
    );
  }

  factory TouristDestinationDetail.fromExploreSpot(TouristSpot spot) {
    final municipality = spot.city.isNotEmpty
        ? spot.city
        : getMunicipalityIdFromName(spot.name);
    final image = TouristSpotImageCatalog.displayUrl(
      preferred: spot.imageUrl,
      spotId: spot.id,
      spotName: spot.name,
      municipalityId: getMunicipalityIdFromName(spot.city),
      category: spot.category,
    );

    return TouristDestinationDetail(
      spotId: spot.id,
      name: spot.name,
      municipality: municipality,
      category: spot.category,
      rating: spot.rating,
      reviewCount: 0,
      shortDescription: spot.description.isNotEmpty
          ? spot.description
          : 'Explore ${spot.name} in $municipality.',
      fullDescription: spot.description.isNotEmpty
          ? spot.description
          : 'Discover ${spot.name} in Misamis Occidental.',
      imageUrls: [image],
      openingHours: '8:00 AM – 5:00 PM',
      entranceFee: 'Varies by site',
      address: municipality,
      bestTimeToVisit: 'Dry season (Nov–May)',
      latitude: spot.latitude,
      longitude: spot.longitude,
      vrLink: spot.vrLink,
      vrPanoramaUrl: spot.vrPanoramaUrl,
      prefersQrCheckIn: true,
      reviews: const [],
    );
  }

  static String _municipalityFromLocation(
    String location,
    String spotId,
    String name,
  ) {
    if (location.isNotEmpty) {
      final parts = location.split(',');
      if (parts.isNotEmpty) return parts.first.trim();
    }
    final mid = getMunicipalityIdFromName(spotId);
    if (mid.isNotEmpty) return mid;
    return name;
  }

  static List<String> _cafeNamesFromRestaurants(List<NearbyPlaceCard> restaurants) {
    return restaurants
        .map((r) => r.name.replaceAll('Grill', 'Café').replaceAll('Shack', 'Coffee'))
        .take(2)
        .toList();
  }

  static List<NearbyPlaceCard> _nearbyFromNames(
    dynamic raw, {
    required String category,
    required double baseRating,
  }) {
    final entries = <({String name, String? imageUrl})>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) {
          final name = item['name']?.toString().trim() ?? '';
          if (name.isEmpty) continue;
          final image = item['image']?.toString().trim() ??
              item['imageUrl']?.toString().trim();
          entries.add((
            name: name,
            imageUrl: image != null && image.isNotEmpty
                ? TouristSpotImageCatalog.normalizeAssetPath(image)
                : null,
          ));
        } else {
          final name = item.toString().trim();
          if (name.isNotEmpty) entries.add((name: name, imageUrl: null));
        }
      }
    }
    return List.generate(entries.length, (i) {
      final entry = entries[i];
      final rawItem = raw is List && i < raw.length && raw[i] is Map
          ? raw[i] as Map
          : null;
      return NearbyPlaceCard(
        name: entry.name,
        category: rawItem?['category']?.toString() ?? category,
        rating: (rawItem?['rating'] as num?)?.toDouble() ??
            (baseRating - 0.1 * i).clamp(3.8, 5.0),
        distanceKm: (rawItem?['distanceKm'] as num?)?.toDouble() ??
            (0.4 + (i * 0.35)),
        driveMinutes: (rawItem?['driveMinutes'] as num?)?.toDouble(),
        priceRange: rawItem?['priceRange']?.toString() ??
            (i.isEven ? '₱₱' : '₱₱₱'),
        imageUrl: entry.imageUrl ?? TouristSpotImageCatalog.kDefaultAsset,
        address: rawItem?['location']?.toString().trim() ??
            rawItem?['address']?.toString().trim(),
        description: rawItem?['description']?.toString().trim(),
      );
    });
  }

  static int _reviewCountForRating(double rating) => 0;

  static List<VisitorReview> _defaultReviews(String name, double rating) =>
      const [];
}
