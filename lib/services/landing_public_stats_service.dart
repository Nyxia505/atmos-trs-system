import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

class LandingPublicStats {
  const LandingPublicStats({this.registeredTourists, this.touristSpots});

  final int? registeredTourists;
  final int? touristSpots;
}

/// Public counts for the landing page; guests cannot read `tourists` directly,
/// so registered tourists come from the `getLandingPublicStats` function.
class LandingPublicStatsService {
  LandingPublicStatsService._();

  static LandingPublicStats? _cached;

  static Future<LandingPublicStats> load() async {
    final cached = _cached;
    if (cached != null) return cached;

    int? tourists;
    int? spots;
    try {
      final result = await FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('getLandingPublicStats').call<Map<String, dynamic>>();
      final data = Map<String, dynamic>.from(result.data);
      tourists = (data['registeredTourists'] as num?)?.toInt();
      spots = (data['touristSpots'] as num?)?.toInt();
    } catch (e) {
      debugPrint('[LandingPublicStats] function failed: $e');
    }

    if (spots == null) {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('tourist_spots')
            .get();
        spots = snap.docs.where((d) {
          final status = d.data()['status']?.toString().trim().toLowerCase();
          return status != 'deleted' &&
              status != 'removed' &&
              status != 'archived';
        }).length;
      } catch (e) {
        debugPrint('[LandingPublicStats] tourist_spots fallback failed: $e');
      }
    }

    final stats = LandingPublicStats(
      registeredTourists: tourists,
      touristSpots: spots,
    );
    if (tourists != null && spots != null) _cached = stats;
    return stats;
  }
}
