import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:atmos_trs_system/data/featured_destinations.dart';
import 'package:atmos_trs_system/data/misamis_occidental_display_spots.dart';
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
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  static String _docId(String spotId, String userId) {
    final safeSpot = spotId.trim().replaceAll('/', '_');
    return '${safeSpot}__$userId';
  }

  static List<SpotReview> _sortedNewestFirst(Iterable<SpotReview> reviews) {
    return reviews.toList()
      ..sort((a, b) {
        final aTime = a.updatedAt ?? a.createdAt;
        final bTime = b.updatedAt ?? b.createdAt;
        return bTime.compareTo(aTime);
      });
  }

  static List<SpotReview> _withComments(Iterable<SpotReview> reviews) {
    return reviews.where((r) => r.comment.isNotEmpty).toList();
  }

  /// Live feed of the latest reviews from all tourists, newest first.
  static Stream<List<SpotReview>> watchRecentReviews({int limit = 15}) {
    if (!_firebaseReady) {
      return Stream.value(const []);
    }

    return _firestore
        .collection(_collectionId)
        .limit(100)
        .snapshots()
        .map((snap) {
      final reviews = _sortedNewestFirst(_withComments(
        snap.docs.map(SpotReview.fromFirestore),
      ));
      if (reviews.length <= limit) return reviews;
      return reviews.sublist(0, limit);
    });
  }

  /// Live reviews for the signed-in user, newest first.
  static Stream<List<SpotReview>> watchUserReviews() async* {
    if (!_firebaseReady) {
      yield const [];
      return;
    }
    final uid = await _uid();
    if (uid == null || uid.isEmpty) {
      yield const [];
      return;
    }

    yield* _firestore
        .collection(_collectionId)
        .where('userId', isEqualTo: uid)
        .limit(50)
        .snapshots()
        .map((snap) {
      final reviews = _sortedNewestFirst(_withComments(
        snap.docs.map(SpotReview.fromFirestore),
      ));
      return reviews;
    });
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
      final reviews = _sortedNewestFirst(_withComments(
        snap.docs.map(SpotReview.fromFirestore),
      ));
      if (reviews.isEmpty) return SpotReviewSummary.empty;
      final avg = reviews.map((r) => r.rating).reduce((a, b) => a + b) / reviews.length;
      return SpotReviewSummary(
        reviews: reviews,
        averageRating: avg,
        reviewCount: reviews.length,
      );
    });
  }

  /// Canonical destination id, so legacy / featured / municipality aliases of the
  /// same place compare equal. LGU desk visits (`lgu_*`) never alias a spot.
  static String _canonicalSpotId(String spotId) {
    final id = spotId.trim();
    if (id.isEmpty || id.toLowerCase().startsWith('lgu_')) {
      return id.toLowerCase();
    }
    final known = MisamisOccidentalDisplaySpots.findByAnyId(
      id,
      featuredDestinations: kFeaturedDestinations,
    );
    return (known?.id ?? id).trim().toLowerCase();
  }

  static bool _visitsInclude(List<VisitRecord> visits, String spotId) {
    final target = spotId.trim().toLowerCase();
    final canonicalTarget = _canonicalSpotId(spotId);
    return visits.any((v) {
      final id = v.spotId.trim().toLowerCase();
      if (id.isEmpty) return false;
      return id == target || _canonicalSpotId(id) == canonicalTarget;
    });
  }

  static final Set<String> _confirmedCheckIns = {};

  /// Whether the signed-in user checked in at [spotId] via QR.
  static Future<bool> hasCheckedInAtSpot(String spotId) async {
    if (spotId.trim().isEmpty) return false;
    final target = spotId.trim().toLowerCase();
    final canonical = _canonicalSpotId(spotId);
    if (_confirmedCheckIns.contains(target) ||
        _confirmedCheckIns.contains(canonical)) {
      return true;
    }
    final local = await UserActivityService.getVisitedSpots();
    if (_visitsInclude(local, spotId)) {
      _rememberCheckIn(spotId);
      return true;
    }
    final synced = await UserActivityService.syncVisitedSpotsFromQrCheckins();
    final checkedIn = _visitsInclude(synced, spotId);
    if (checkedIn) _rememberCheckIn(spotId);
    return checkedIn;
  }

  static void _rememberCheckIn(String spotId) {
    final target = spotId.trim().toLowerCase();
    if (target.isNotEmpty) _confirmedCheckIns.add(target);
    final canonical = _canonicalSpotId(spotId);
    if (canonical.isNotEmpty) _confirmedCheckIns.add(canonical);
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
  ///
  /// [existing] skips a read of the same document before the write.
  static Future<SpotReviewResult> submitReview({
    required String spotId,
    required String spotName,
    required double rating,
    required String comment,
    SpotReview? existing,
  }) async {
    final trimmedSpotId = spotId.trim();
    final trimmedComment = comment.trim();
    if (trimmedSpotId.isEmpty) {
      return const SpotReviewFailure('This destination cannot be reviewed yet.');
    }
    if (trimmedComment.length < 10) {
      return const SpotReviewFailure('Please write at least 10 characters.');
    }
    if (rating < 1 || rating > 5) {
      return const SpotReviewFailure('Please select a star rating.');
    }

    final uid = await _uid();
    if (uid == null || uid.isEmpty) {
      return const SpotReviewFailure('Sign in to leave a review.');
    }
    if (!_firebaseReady) {
      return const SpotReviewFailure('Reviews are unavailable offline. Try again later.');
    }

    final checkedIn = await hasCheckedInAtSpot(trimmedSpotId);
    if (!checkedIn) {
      return const SpotReviewFailure(
        'Scan the QR code at this spot to check in before leaving a review.',
      );
    }

    try {
      final docRef = _firestore.collection(_collectionId).doc(_docId(trimmedSpotId, uid));
      final isUpdate = existing != null && existing.userId == uid;
      final authorName = await _authorName();
      final review = SpotReview(
        id: docRef.id,
        spotId: trimmedSpotId,
        userId: uid,
        authorName: authorName,
        rating: rating.clamp(1.0, 5.0),
        comment: trimmedComment,
        createdAt: isUpdate ? existing.createdAt : DateTime.now(),
        updatedAt: DateTime.now(),
        spotName: spotName.trim(),
      );

      await docRef.set(
        {
          ...review.toFirestore(isUpdate: isUpdate),
          'spotName': spotName.trim(),
        },
        SetOptions(merge: true),
      );

      return SpotReviewSuccess(review);
    } catch (e) {
      debugPrint('SpotReviewService.submitReview: $e');
      return const SpotReviewFailure('Could not save review. Please try again.');
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
