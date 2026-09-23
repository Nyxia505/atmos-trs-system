/// Pin for an approved tourism establishment on the tourist Explore map.
class EstablishmentMapPin {
  const EstablishmentMapPin({
    required this.id,
    required this.name,
    required this.category,
    required this.latitude,
    required this.longitude,
    this.municipality = '',
    this.barangay = '',
    this.location = '',
    this.coverImageUrl = '',
    this.galleryUrls = const [],
  });

  final String id;
  final String name;
  final String category;
  final double latitude;
  final double longitude;
  final String municipality;
  final String barangay;
  final String location;
  final String coverImageUrl;
  final List<String> galleryUrls;

  bool get hasValidCoords =>
      latitude.abs() > 1e-6 || longitude.abs() > 1e-6;

  /// Cover first, then remaining gallery URLs (deduped).
  List<String> get displayImageUrls {
    final out = <String>[];
    void add(String u) {
      final t = u.trim();
      if (t.startsWith('http') && !out.contains(t)) out.add(t);
    }

    add(coverImageUrl);
    for (final u in galleryUrls) {
      add(u);
    }
    return out;
  }
}
