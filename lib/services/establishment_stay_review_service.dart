import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:atmos_trs_system/models/establishment_stay_review.dart';
import 'package:atmos_trs_system/services/establishment_stay_service.dart';

/// Saves and loads guest reviews for establishment stays.
class EstablishmentStayReviewService {
  EstablishmentStayReviewService._();

  static const String collection = 'establishment_stay_reviews';

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(collection);

  static String docIdForStay(String stayRequestId) =>
      stayRequestId.trim().replaceAll('/', '_');

  static Stream<EstablishmentStayReviewSummary> watchForEstablishment(
    String establishmentId, {
    int limit = 40,
  }) {
    final eid = establishmentId.trim();
    if (eid.isEmpty) {
      return Stream.value(EstablishmentStayReviewSummary.empty);
    }
    return _col
        .where('establishmentId', isEqualTo: eid)
        .limit(limit)
        .snapshots()
        .map((snap) {
      final reviews = snap.docs
          .map(EstablishmentStayReview.fromFirestore)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (reviews.isEmpty) return EstablishmentStayReviewSummary.empty;
      final hotelAvg =
          reviews.map((r) => r.hotelRating).reduce((a, b) => a + b) /
              reviews.length;
      final roomAvg =
          reviews.map((r) => r.roomRating).reduce((a, b) => a + b) /
              reviews.length;
      return EstablishmentStayReviewSummary(
        reviews: reviews,
        averageHotelRating: hotelAvg,
        averageRoomRating: roomAvg,
        reviewCount: reviews.length,
      );
    });
  }

  static Future<EstablishmentStayReview?> getForStay(String stayRequestId) async {
    final id = docIdForStay(stayRequestId);
    if (id.isEmpty) return null;
    try {
      final doc = await _col.doc(id).get();
      if (!doc.exists) return null;
      return EstablishmentStayReview.fromFirestore(doc);
    } catch (e) {
      debugPrint('[EstStayReview] getForStay: $e');
      return null;
    }
  }

  static Stream<EstablishmentStayReview?> watchForStay(String stayRequestId) {
    final id = docIdForStay(stayRequestId);
    if (id.isEmpty) return Stream.value(null);
    return _col.doc(id).snapshots().map((doc) {
      if (!doc.exists) return null;
      return EstablishmentStayReview.fromFirestore(doc);
    });
  }

  static Future<void> submitReview({
    required EstablishmentStayRequest stay,
    required double hotelRating,
    required double roomRating,
    String comment = '',
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Sign in to leave a review.');
    }
    if (stay.touristId != uid) {
      throw StateError('Only the guest on this stay can review.');
    }
    if (!stay.isCheckedOut) {
      throw StateError('Check out before leaving a review.');
    }
    final hotel = hotelRating.clamp(1.0, 5.0);
    final room = roomRating.clamp(1.0, 5.0);
    final review = EstablishmentStayReview(
      id: docIdForStay(stay.id),
      stayRequestId: stay.id,
      establishmentId: stay.establishmentId,
      touristId: uid,
      authorName: stay.touristName.isNotEmpty ? stay.touristName : 'Guest',
      establishmentName: stay.establishmentName,
      roomNumbers: stay.roomNumbers,
      hotelRating: hotel,
      roomRating: room,
      comment: comment.trim(),
      createdAt: DateTime.now(),
    );
    await _col.doc(review.id).set(review.toFirestore(), SetOptions(merge: true));
    debugPrint('[EstStayReview] saved ${review.id}');
  }
}
