import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;

import '../algorithms/collaborative_filtering.dart';
import '../data.dart';
import '../firestore_loader.dart';
import 'home_recommendation_service.dart';
import 'spot_interaction_history.dart';
import 'travel_history_profile.dart';

/// Home personalization: loads travel history + peer CF profiles, then runs
/// [HomeRecommendationService] for Featured / Recommended ranking.
class HomePersonalizationService {
  HomePersonalizationService._();
  static final HomePersonalizationService instance =
      HomePersonalizationService._();

  /// Bumped after each [refresh] so Home can rebuild personalized sections.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  TravelHistoryProfile? _profile;
  List<CollaborativeUserProfile> _peers = [];

  bool get hasPersonalization => allSpots.isNotEmpty;

  TravelHistoryProfile? get profile => _profile;

  /// Clears personalized data immediately on logout (no network).
  void clearForLogout() {
    _profile = null;
    _peers = [];
    HomeRecommendationService.instance.clearCachedRankings();
    revision.value++;
  }

  /// Reloads profile, interactions, and recomputes home rankings.
  Future<void> refresh() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _profile = null;
      _peers = [];
      await SpotInteractionHistoryStore.instance.load();
      await HomeRecommendationService.instance.recompute(profile: null);
      revision.value++;
      return;
    }
    try {
      await Future(() async {
        _profile = await fetchTravelHistoryProfile(uid);
        if (_profile!.hasSignals) {
          await saveRecommendationProfileForCollaborativeFiltering(
            uid: uid,
            profile: _profile!,
          );
        }
        _peers = await loadCollaborativePeerProfiles(excludeUid: uid);
        await SpotInteractionHistoryStore.instance.load();
        if (_profile != null) {
          SpotInteractionHistoryStore.instance
              .mergeVisitedKeys(_profile!.visitedSpotNameKeys);
        }
      }).timeout(const Duration(seconds: 12));
    } catch (_) {
      // Keep last good profile on timeout.
    }

    await HomeRecommendationService.instance.recompute(profile: _profile);
    revision.value++;
  }

  /// Personalized spots for Home "Recommended for You".
  List<TouristSpot> personalizedSpots({int limit = 12}) {
    final fromEngine =
        HomeRecommendationService.instance.recommendedSpots(limit: limit);
    if (fromEngine.isNotEmpty) return fromEngine;

    final profile = _profile;
    if (allSpots.isEmpty) return const [];

    if (profile == null || !profile.hasSignals) {
      final featured =
          HomeRecommendationService.instance.featuredSpots(limit: limit);
      if (featured.isNotEmpty) return featured;
      return List<TouristSpot>.from(allSpots)
        ..sort((a, b) => b.rating.compareTo(a.rating));
    }

    final vectors = travelHistoryToCfVectors(profile);
    final ranked = <({TouristSpot spot, double score})>[];
    if (_peers.isNotEmpty) {
      ranked.addAll(
        CollaborativeFiltering.rankSpots(
          catalog: allSpots,
          targetItems: vectors.items,
          targetTags: vectors.tags,
          peers: _peers,
          limit: limit * 2,
        ),
      );
    }
    ranked.sort((a, b) => b.score.compareTo(a.score));
    final seen = <String>{};
    final out = <TouristSpot>[];
    for (final r in ranked) {
      if (!seen.add(normalizeTourismNameKey(r.spot.name))) continue;
      out.add(r.spot);
      if (out.length >= limit) break;
    }
    if (out.isEmpty) {
      return List<TouristSpot>.from(allSpots)
        ..sort((a, b) => b.rating.compareTo(a.rating));
    }
    return out.take(limit).toList();
  }

  List<ScoredHomeSpot> featuredRanked({int limit = 8}) =>
      HomeRecommendationService.instance.featured.take(limit).toList();

  List<ScoredHomeSpot> recommendedRanked({int limit = 12}) =>
      HomeRecommendationService.instance.recommended.take(limit).toList();

  List<Municipality> personalizedMunicipalities() {
    final profile = _profile;
    if (municipalities.isEmpty) return recommendedMunicipalities;
    if (profile == null) return recommendedMunicipalities;

    final spots = personalizedSpots(limit: 40);
    double scoreFor(Municipality m) {
      var score = 0.0;
      if (profile.visitedMunicipalityNames.contains(m.name)) {
        score += 2.0;
      }
      for (final s in spots) {
        if (touristSpotBelongsToMunicipality(s, m)) {
          score += 0.25 + s.rating * 0.05;
        }
      }
      final inM = allSpots.where((s) => touristSpotBelongsToMunicipality(s, m));
      if (inM.isNotEmpty) {
        score += inM.map((s) => s.rating).reduce((a, b) => a > b ? a : b) * 0.1;
      }
      return score;
    }

    final list = List<Municipality>.from(municipalities);
    list.sort((a, b) => scoreFor(b).compareTo(scoreFor(a)));
    return list;
  }
}
