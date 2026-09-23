import 'package:cloud_firestore/cloud_firestore.dart';

/// Guest review for a completed establishment stay (`establishment_stay_reviews`).
class EstablishmentStayReview {
  const EstablishmentStayReview({
    required this.id,
    required this.stayRequestId,
    required this.establishmentId,
    required this.touristId,
    required this.hotelRating,
    required this.roomRating,
    required this.comment,
    required this.createdAt,
    this.authorName = '',
    this.establishmentName = '',
    this.roomNumbers = const [],
  });

  final String id;
  final String stayRequestId;
  final String establishmentId;
  final String touristId;
  final String authorName;
  final String establishmentName;
  final List<String> roomNumbers;
  final double hotelRating;
  final double roomRating;
  final String comment;
  final DateTime createdAt;

  double get averageRating => (hotelRating + roomRating) / 2;

  factory EstablishmentStayReview.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const {};
    return EstablishmentStayReview(
      id: doc.id,
      stayRequestId: (data['stayRequestId'] ?? '').toString(),
      establishmentId: (data['establishmentId'] ?? '').toString(),
      touristId: (data['touristId'] ?? data['userId'] ?? '').toString(),
      authorName: (data['authorName'] ?? 'Guest').toString().trim().isEmpty
          ? 'Guest'
          : (data['authorName'] ?? 'Guest').toString().trim(),
      establishmentName: (data['establishmentName'] ?? '').toString(),
      roomNumbers: _asStringList(data['roomNumbers']),
      hotelRating: _asRating(data['hotelRating']),
      roomRating: _asRating(data['roomRating']),
      comment: (data['comment'] ?? '').toString().trim(),
      createdAt: _readTimestamp(data['createdAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'stayRequestId': stayRequestId,
        'establishmentId': establishmentId,
        'touristId': touristId,
        'userId': touristId,
        'authorName': authorName,
        'establishmentName': establishmentName,
        'roomNumbers': roomNumbers,
        'hotelRating': hotelRating,
        'roomRating': roomRating,
        'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
      };

  static double _asRating(dynamic raw) {
    if (raw is num) return raw.toDouble().clamp(1.0, 5.0);
    return double.tryParse(raw?.toString() ?? '')?.clamp(1.0, 5.0) ?? 5.0;
  }

  static List<String> _asStringList(dynamic v) {
    if (v is! List) return const [];
    return v
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static DateTime? _readTimestamp(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.tryParse(raw?.toString() ?? '');
  }
}

class EstablishmentStayReviewSummary {
  const EstablishmentStayReviewSummary({
    required this.reviews,
    required this.averageHotelRating,
    required this.averageRoomRating,
    required this.reviewCount,
  });

  final List<EstablishmentStayReview> reviews;
  final double averageHotelRating;
  final double averageRoomRating;
  final int reviewCount;

  double get averageOverall =>
      reviewCount == 0 ? 0 : (averageHotelRating + averageRoomRating) / 2;

  static const empty = EstablishmentStayReviewSummary(
    reviews: [],
    averageHotelRating: 0,
    averageRoomRating: 0,
    reviewCount: 0,
  );
}
