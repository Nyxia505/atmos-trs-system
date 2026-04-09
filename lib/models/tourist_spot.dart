/// Tourist spot model for Firestore "tourist_spots" collection.
/// Fields in Firestore: name, category, municipality, description, rating,
/// latitude, longitude, image_url, vr_link. Optional: status, visitors, municipalityId.
class TouristSpot {
  const TouristSpot({
    required this.id,
    required this.name,
    required this.category,
    required this.municipality,
    required this.description,
    required this.rating,
    required this.latitude,
    required this.longitude,
    this.imageUrl,
    this.vrLink,
    this.status = 'Active',
    this.visitors = 0,
    this.municipalityId = '',
  });

  final String id;
  final String name;
  final String category;
  final String municipality;
  final String description;
  final double rating;
  final double latitude;
  final double longitude;
  final String? imageUrl;
  final String? vrLink;
  final String status;
  final int visitors;
  /// Municipality ID for QR payload and filtering (e.g. oroquieta, ozamiz).
  final String municipalityId;

  /// Alias for [vrLink] for compatibility with code that expects vrTourUrl.
  String? get vrTourUrl => vrLink;

  factory TouristSpot.fromFirestore(Map<String, dynamic> data, String docId) {
    final lat = data['latitude'];
    final lng = data['longitude'];
    final ratingData = data['rating'];
    final image = data['image_url'] as String? ?? data['image'] as String?;
    final vr = data['vr_link'] as String? ?? data['vrLink'] as String?;
    final statusVal = data['status'] as String? ?? 'Active';
    final visitorsVal = data['visitors'];
    final municipalityIdVal = data['municipalityId'] as String? ?? '';

    return TouristSpot(
      id: docId,
      name: data['name'] as String? ?? '',
      category: data['category'] as String? ?? 'Spot',
      municipality: data['municipality'] as String? ?? '',
      description: data['description'] as String? ?? '',
      rating: (ratingData is num) ? ratingData.toDouble() : 0.0,
      latitude: (lat is num) ? lat.toDouble() : 0.0,
      longitude: (lng is num) ? lng.toDouble() : 0.0,
      imageUrl: image?.isNotEmpty == true ? image : null,
      vrLink: vr?.isNotEmpty == true ? vr : null,
      status: statusVal,
      visitors: visitorsVal is int
          ? visitorsVal
          : (visitorsVal is num ? visitorsVal.toInt() : 0),
      municipalityId: municipalityIdVal,
    );
  }

  /// For Firestore add/update: document fields (without id).
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'category': category,
      'municipality': municipality,
      'description': description,
      'rating': rating,
      'latitude': latitude,
      'longitude': longitude,
      if (imageUrl != null && imageUrl!.isNotEmpty) 'image_url': imageUrl,
      if (vrLink != null && vrLink!.isNotEmpty) 'vr_link': vrLink,
      'status': status,
      'visitors': visitors,
      if (municipalityId.isNotEmpty) 'municipalityId': municipalityId,
    };
  }
}
