import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:atmos_trs_system/models/spot_review.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Saves and loads visitor reviews for tourist spots.
class SpotReviewService {
  SpotReviewService._();

  static const String _collectionId = 'spot_reviews';

  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static bool get _firebaseReady {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _uid() async {
    final cached = AuthConfig.currentUserUid?.trim();
    if (cached != null && cached.isNotEmpty) return cached;
    return FirebaseAuth.instance.currentUser?.uid;
  }

  static String _docId(String spotId, String userId) {
    final safeSpot = spotId.trim().replaceAll('/', '_');
    return '${safeSpot}__$userId';
  }

  /// Live reviews for a spot, newest first.
  static Stream<SpotReviewSummary> watchSpotReviews(String spotId) {
    if (!_firebaseReady || spotId.trim().isEmpty) {
      return Stream.value(SpotReviewSummary.empty);
    }

    return _firestore
        .collection(_collectionId)
        .where('spotId', isEqualTo: spotId.trim())
        .limit(50)
        .snapshots()
        .map((snap) {
      final reviews = snap.docs
          .map(SpotReview.fromFirestore)
          .where((r) => r.comment.isNotEmpty)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (reviews.isEmpty) return SpotReviewSummary.empty;
      final avg = reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length;
      return SpotReviewSummary(
        reviews: reviews,
        averageRating: avg,
        reviewCount: reviews.length,
      );
    });
  }

  /// Whether the signed-in user checked in at [spotId] via QR.
  static Future<bool> hasCheckedInAtSpot(String spotId) async {
    if (spotId.trim().isEmpty) return false;
    await UserActivityService.syncVisitedSpotsFromQrCheckins();
    final visits = await UserActivityService.getVisitedSpots();
    final target = spotId.trim().toLowerCase();
    return visits.any((v) => v.spotId.trim().toLowerCase() == target);
  }

  static Future<SpotReview?> getUserReview(String spotId) async {
    final uid = await _uid();
    if (uid == null || uid.isEmpty || !_firebaseReady || spotId.trim().isEmpty) {
      return null;
    }
    try {
      final doc = await _firestore
          .collection(_collectionId)
          .doc(_docId(spotId, uid))
          .get();
      if (!doc.exists) return null;
      return SpotReview.fromFirestore(doc);
    } catch (e) {
      debugPrint('SpotReviewService.getUserReview: $e');
      return null;
    }
  }

  static Future<String> _authorName() async {
    final profile = UserProfileStorage.cachedProfile ?? await UserProfileStorage.getUserProfile();
    if (profile != null) {
      final first = profile.firstName.trim();
      final last = profile.lastName.trim();
      if (first.isNotEmpty && last.isNotEmpty) return '$first ${last[0]}.';
      if (first.isNotEmpty) return first;
    }
    final authName = FirebaseAuth.instance.currentUser?.displayName?.trim();
    if (authName != null && authName.isNotEmpty) return authName;
    return 'Visitor';
  }

  /// Submit or update the current user's review (requires QR check-in).
  static Future<SpotReviewResult> submitReview({
    required String spotId,
    required String spotName,
    required double rating,
    required String comment,
  }) async {
    final uid = await _uid();
    if (uid == null || uid.isEmpty) {
      return const SpotReviewFailure('Sign in to leave a review.');
    }
    if (!_firebaseReady) {
      return const SpotReviewFailure('Reviews are unavailable offline. Try again later.');
    }
    if (spotId.trim().isEmpty) {
      return const SpotReviewFailure('This destination cannot be reviewed yet.');
    }

    final trimmedComment = comment.trim();
    if (trimmedComment.length < 10) {
      return const SpotReviewFailure('Please write at least 10 characters.');
    }
    if (rating < 1 || rating > 5) {
      return const SpotReviewFailure('Please select a star rating.');
    }

    final checkedIn = await hasCheckedInAtSpot(spotId);
    if (!checkedIn) {
      return const SpotReviewFailure(
        'Scan the QR code at this spot to check in before leaving a review.',
      );
    }

    try {
      final docRef = _firestore.collection(_collectionId).doc(_docId(spotId, uid));
      final existing = await docRef.get();
      final authorName = await _authorName();
      final review = SpotReview(
        id: docRef.id,
        spotId: spotId.trim(),
        userId: uid,
        authorName: authorName,
        rating: rating.clamp(1.0, 5.0),
        comment: trimmedComment,
        createdAt: existing.exists
            ? SpotReview.fromFirestore(existing).createdAt
            : DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await docRef.set(
        {
          ...review.toFirestore(isUpdate: existing.exists),
          'spotName': spotName.trim(),
        },
        SetOptions(merge: true),
      );

      return SpotReviewSuccess(review);
    } catch (e) {
      debugPrint('SpotReviewService.submitReview: $e');
      return SpotReviewFailure('Could not save review. Please try again.');
    }
  }
}

sealed class SpotReviewResult {
  const SpotReviewResult();
}

class SpotReviewSuccess extends SpotReviewResult {
  const SpotReviewSuccess(this.review);
  final SpotReview review;
}

class SpotReviewFailure extends SpotReviewResult {
  const SpotReviewFailure(this.message);
  final String message;
}
