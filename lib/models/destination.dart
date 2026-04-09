/// Model for a tourism destination. Structured for future Firebase integration.
class Destination {
  const Destination({
    required this.id,
    required this.name,
    required this.category,
    required this.distance,
    required this.rating,
    required this.imageUrl,
    this.saved = false,
    this.assetImagePath,
  });

  final String id;
  final String name;
  final String category;
  final String distance;
  final double rating;
  final String imageUrl;
  final bool saved;
  /// Optional local asset path (e.g. assets/images/beach.jpg) for offline use.
  final String? assetImagePath;

  /// For Firebase: fromMap from Firestore snapshot.
  factory Destination.fromMap(Map<String, dynamic> map, [String? id]) {
    return Destination(
      id: id ?? map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      category: map['category'] as String? ?? '',
      distance: map['distance'] as String? ?? '',
      rating: (map['rating'] as num?)?.toDouble() ?? 0,
      imageUrl: map['imageUrl'] as String? ?? '',
      saved: map['saved'] as bool? ?? false,
      assetImagePath: map['assetImagePath'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'distance': distance,
      'rating': rating,
      'imageUrl': imageUrl,
      'saved': saved,
      if (assetImagePath != null) 'assetImagePath': assetImagePath,
    };
  }
}
