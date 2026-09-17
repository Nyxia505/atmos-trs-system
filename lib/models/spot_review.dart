import 'package:cloud_firestore/cloud_firestore.dart';

/// A visitor review for a tourist spot (stored in Firestore `spot_reviews`).
class SpotReview {
  const SpotReview({
    required this.id,
    required this.spotId,
    required this.userId,
    required this.authorName,
    required this.rating,
    required this.comment,
    required this.createdAt,
    this.updatedAt,
    this.spotName = '',
  });

  final String id;
  final String spotId;
  final String userId;
  final String authorName;
  final double rating;
  final String comment;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String spotName;

  String get displaySpotName {
    final name = spotName.trim();
    if (name.isNotEmpty) return name;
    final id = spotId.trim();
    if (id.isEmpty) return 'Destination';
    return id.replaceAll('_', ' ');
  }

  String get dateLabel => _formatDateLabel(createdAt);

  factory SpotReview.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return SpotReview(
      id: doc.id,
      spotId: data['spotId']?.toString() ?? '',
      userId: data['userId']?.toString() ?? '',
      authorName: data['authorName']?.toString().trim().isNotEmpty == true
          ? data['authorName'].toString().trim()
          : 'Visitor',
      rating: (data['rating'] as num?)?.toDouble().clamp(1.0, 5.0) ?? 5.0,
      comment: data['comment']?.toString().trim() ?? '',
      createdAt: _readTimestamp(data['createdAt']) ?? DateTime.now(),
      updatedAt: _readTimestamp(data['updatedAt']),
      spotName: data['spotName']?.toString().trim() ?? '',
    );
  }

  Map<String, dynamic> toFirestore({required bool isUpdate}) {
    return {
      'spotId': spotId,
      'userId': userId,
      'authorName': authorName,
      'rating': rating,
      'comment': comment,
      if (!isUpdate) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static DateTime? _readTimestamp(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw?.toString() ?? '');
  }

  static String _formatDateLabel(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()} weeks ago';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class SpotReviewSummary {
  const SpotReviewSummary({
    required this.reviews,
    required this.averageRating,
    required this.reviewCount,
  });

  final List<SpotReview> reviews;
  final double averageRating;
  final int reviewCount;

  static const empty = SpotReviewSummary(
    reviews: [],
    averageRating: 0,
    reviewCount: 0,
  );
}
