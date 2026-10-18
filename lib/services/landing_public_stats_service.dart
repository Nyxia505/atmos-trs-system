import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class LandingPublicStats {
  const LandingPublicStats({
    this.registeredTourists,
    this.touristSpots,
    this.vrTours,
  });

  final int? registeredTourists;
  final int? touristSpots;
  final int? vrTours;
}

class LandingSpotCounts {
  const LandingSpotCounts({required this.touristSpots, required this.vrTours});

  final int touristSpots;
  final int vrTours;
}

/// Public counts for the landing page; guests cannot read `tourists` directly,
/// so registered tourists come from the `getLandingPublicStats` function.
class LandingPublicStatsService {
  LandingPublicStatsService._();

  static LandingPublicStats? _cached;

  static final DocumentReference<Map<String, dynamic>> landingStatsRef =
      FirebaseFirestore.instance.doc('public_stats/landing');

  /// Live spot and VR totals from the same public `tourist_spots` records.
  static Stream<LandingSpotCounts> watchSpotCounts() {
    return FirebaseFirestore.instance
        .collection('tourist_spots')
        .snapshots()
        .map((snap) => countsFromSpotDocs(snap.docs));
  }

  static bool isCountableSpot(Map<String, dynamic> data) {
    final status = data['status']?.toString().trim().toLowerCase();
    return status != 'deleted' && status != 'removed' && status != 'archived';
  }

  static bool hasPublicVrTour(Map<String, dynamic> data) {
    if (data['hasVR'] == true) return true;
    final link = (data['vr_link'] ?? data['vrLink'])?.toString().trim() ?? '';
    return link.isNotEmpty;
  }

  static LandingSpotCounts countsFromSpotDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var spots = 0;
    var vrTours = 0;
    for (final doc in docs) {
      final data = doc.data();
      if (!isCountableSpot(data)) continue;
      spots++;
      if (hasPublicVrTour(data)) vrTours++;
    }
    return LandingSpotCounts(touristSpots: spots, vrTours: vrTours);
  }
  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchRegisteredTourists() {
    return landingStatsRef.snapshots();
  }

  /// Builds the public count from existing tourist accounts when it is missing.
  static Future<int?> ensureRegisteredTouristCount() async {
    try {
      final result = await FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('getLandingPublicStats').call<Map<String, dynamic>>();
      final data = Map<String, dynamic>.from(result.data);
      return (data['registeredTourists'] as num?)?.toInt();
    } catch (e) {
      debugPrint('[LandingPublicStats] ensure count failed: $e');
      return null;
    }
  }

  static Future<LandingPublicStats> load() async {
    final cached = _cached;
    if (cached != null) return cached;

    int? tourists;
    int? spots;
    int? vrTours;
    try {
      final result = await FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('getLandingPublicStats').call<Map<String, dynamic>>();
      final data = Map<String, dynamic>.from(result.data);
      tourists = (data['registeredTourists'] as num?)?.toInt();
      spots = (data['touristSpots'] as num?)?.toInt();
      vrTours = (data['vrTours'] as num?)?.toInt();
    } catch (e) {
      debugPrint('[LandingPublicStats] function failed: $e');
    }

    if (spots == null || vrTours == null) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('tourist_spots')
            .get();
        final counted = countsFromSpotDocs(snap.docs);
        spots ??= counted.touristSpots;
        vrTours ??= counted.vrTours;
      } catch (e) {
        debugPrint('[LandingPublicStats] tourist_spots fallback failed: $e');
      }
    }

    final stats = LandingPublicStats(
      registeredTourists: tourists,
      touristSpots: spots,
      vrTours: vrTours,
    );
    if (tourists != null && spots != null && vrTours != null) _cached = stats;
    return stats;
  }
}
