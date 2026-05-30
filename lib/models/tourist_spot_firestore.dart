/// Tourist spot from Firestore "tourist_spots" collection.
/// Fields: id, name, category, latitude, longitude, image, rating, description, vr_link, municipality, municipalityId
/// Optional: qrValue, qr_payload, createdAt (see [TouristSpot]).
class TouristSpotFirestore {
  const TouristSpotFirestore({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    this.image,
    this.rating = 0.0,
    this.description = '',
    this.vrLink,
    this.municipality = '',
    this.municipalityId = '',
    this.qrValue = '',
    this.qrPayload,
  });

  final String id;
  final String name;
  final String category;
  final double latitude;
  final double longitude;
  final String? image;
  final double rating;
  final String description;
  final String? vrLink;
  final String municipality;
  /// Municipality ID (e.g. oroquieta, ozamiz) for QR payload and filtering.
  final String municipalityId;

  final String qrValue;
  final String? qrPayload;

  factory TouristSpotFirestore.fromFirestore(Map<String, dynamic> data, String id) {
    final lat = data['latitude'];
    final lng = data['longitude'];
    final ratingData = data['rating'];
    final municipalityId = data['municipalityId'] as String? ?? '';
    final municipality = data['municipality'] as String? ?? '';
    final qv =
        (data['qrValue'] as String? ?? data['qr_value'] as String? ?? '').trim();
    final qp = data['qr_payload'] as String? ?? data['qrPayload'] as String?;
    return TouristSpotFirestore(
      id: id,
      name: data['name'] as String? ?? '',
      category: data['category'] as String? ?? 'Spot',
      latitude: (lat is num) ? lat.toDouble() : 0.0,
      longitude: (lng is num) ? lng.toDouble() : 0.0,
      image: data['image'] as String?,
      rating: (ratingData is num) ? ratingData.toDouble() : 0.0,
      description: data['description'] as String? ?? '',
      vrLink: data['vr_link'] as String? ?? data['vrTourUrl'] as String?,
      municipality: municipality,
      municipalityId: municipalityId,
      qrValue: qv.isNotEmpty ? qv : id,
      qrPayload: qp?.trim().isNotEmpty == true ? qp : null,
    );
  }
}
