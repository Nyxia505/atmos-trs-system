import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint, kDebugMode;

import '../algorithms/content_based_filtering.dart';
import '../data.dart';
import '../trip_preferences_store.dart';
import 'spot_interaction_history.dart';
import 'travel_history_profile.dart';

/// Scored tourist spot for Home Featured / Recommended sections.
class ScoredHomeSpot {
  final TouristSpot spot;
  final double score;
  final double ratingScore;
  final double popularity;
  final double preferenceMatch;
  final double userHistory;
  final double routeMatch;
  final double recentEngagement;
  final double quality;
  final bool askVisitAgain;

  const ScoredHomeSpot({
    required this.spot,
    required this.score,
    this.ratingScore = 0,
    this.popularity = 0,
    this.preferenceMatch = 0,
    this.userHistory = 0,
    this.routeMatch = 0,
    this.recentEngagement = 0,
    this.quality = 0,
    this.askVisitAgain = false,
  });
}

/// Home Featured + Recommended hybrid ranking (cached; not recalculated every build).
class HomeRecommendationService {
  HomeRecommendationService._();
  static final HomeRecommendationService instance =
      HomeRecommendationService._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  List<ScoredHomeSpot> _featured = const [];
  List<ScoredHomeSpot> _recommended = const [];
  String _cacheKey = '';

  List<ScoredHomeSpot> get featured => _featured;
  List<ScoredHomeSpot> get recommended => _recommended;

  List<TouristSpot> featuredSpots({int limit = 8}) =>
      _featured.take(limit).map((e) => e.spot).toList(growable: false);

  List<TouristSpot> recommendedSpots({int limit = 12}) =>
      _recommended.take(limit).map((e) => e.spot).toList(growable: false);

  /// Drops cached rankings without touching SharedPreferences / network.
  void clearCachedRankings() {
    _featured = const [];
    _recommended = const [];
    _cacheKey = '';
    revision.value++;
  }

  /// Rebuild rankings from catalog + profile + interactions + trip prefs.
  Future<void> recompute({
    required TravelHistoryProfile? profile,
    int featuredLimit = 8,
    int recommendedLimit = 12,
  }) async {
    final catalog = List<TouristSpot>.from(allSpots);
    if (catalog.isEmpty) {
      _featured = const [];
      _recommended = const [];
      _cacheKey = '';
      revision.value++;
      return;
    }

    final history = SpotInteractionHistoryStore.instance;
    final trip = TripPreferencesStore.instance;
    final interestWeights = await trip.loadInterestWeights();
    final lastInterests = await trip.loadLastInterests();
    final lastTransport = await trip.loadLastTransport();
    final lastBudget = await trip.loadLastBudgetTier();
    final routeCtx = await trip.loadRouteContext();
    final ratedTypes = await trip.loadRatedSpotTypeCounts();

    final interests = <String>{
      ...?profile?.interestTags,
      ...lastInterests,
    };
    final weights = <String, double>{
      ...?profile?.interestWeights,
      ...interestWeights,
    };

    final key = [
      catalog.length,
      profile?.pastDestinations.join(','),
      interests.join(','),
      history.revision.value,
      routeCtx.start,
      routeCtx.end,
      routeCtx.along.join(','),
      lastBudget,
      lastTransport,
    ].join('|');
    if (key == _cacheKey &&
        _featured.isNotEmpty &&
        _recommended.isNotEmpty) {
      return;
    }

    final maxVisitors = catalog
        .map((s) => s.visitors)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final maxRatingCount = catalog
        .map((s) => _effectiveRatingCount(s))
        .fold<int>(0, (a, b) => a > b ? a : b);
    final now = DateTime.now().millisecondsSinceEpoch;

    final featuredScored = <ScoredHomeSpot>[];
    for (final spot in catalog) {
      final ratingScore = computeRatingScore(
        averageStars: spot.rating,
        ratingCount: _effectiveRatingCount(spot),
        maxRatingCount: maxRatingCount,
      );
      final popularity = _normalizeCount(spot.visitors, maxVisitors);
      final recent = _recentEngagement(spot.updatedAtMs, now);
      final quality = _qualityScore(spot);
      final featuredScore = popularity * 0.40 +
          ratingScore * 0.30 +
          recent * 0.20 +
          quality * 0.10;
      featuredScored.add(
        ScoredHomeSpot(
          spot: spot,
          score: featuredScore,
          ratingScore: ratingScore,
          popularity: popularity,
          recentEngagement: recent,
          quality: quality,
        ),
      );
    }
    featuredScored.sort((a, b) => b.score.compareTo(a.score));
    _featured = featuredScored.take(featuredLimit).toList(growable: false);

    final featuredKeys = {
      for (final s in _featured) normalizeTourismNameKey(s.spot.name),
    };

    final recommendedScored = <ScoredHomeSpot>[];
    for (final spot in catalog) {
      final ratingScore = computeRatingScore(
        averageStars: spot.rating,
        ratingCount: _effectiveRatingCount(spot),
        maxRatingCount: maxRatingCount,
      );
      final popularity = _normalizeCount(spot.visitors, maxVisitors);
      final preference = _preferenceMatch(
        spot: spot,
        interests: interests,
        weights: weights,
        budgetTier: lastBudget,
        transport: lastTransport,
        ratedTypes: ratedTypes,
      );
      final userHistory = _userHistoryScore(
        spot: spot,
        profile: profile,
        history: history,
      );
      final routeMatch = _routeLocationMatch(
        spot: spot,
        profile: profile,
        route: routeCtx,
      );
      final recScore = preference * 0.35 +
          userHistory * 0.25 +
          routeMatch * 0.20 +
          popularity * 0.10 +
          ratingScore * 0.10;

      // Soft penalty for Featured duplicates (prefer unique Recommended).
      final keyName = normalizeTourismNameKey(spot.name);
      final duplicatePenalty =
          featuredKeys.contains(keyName) ? 0.08 : 0.0;

      recommendedScored.add(
        ScoredHomeSpot(
          spot: spot,
          score: (recScore - duplicatePenalty).clamp(0.0, 1.0),
          ratingScore: ratingScore,
          popularity: popularity,
          preferenceMatch: preference,
          userHistory: userHistory,
          routeMatch: routeMatch,
          askVisitAgain: history.shouldAskVisitAgain(spot),
        ),
      );
    }
    recommendedScored.sort((a, b) => b.score.compareTo(a.score));

    // Prefer unique names vs Featured when enough alternatives exist.
    final out = <ScoredHomeSpot>[];
    final seen = <String>{};
    for (final row in recommendedScored) {
      final k = normalizeTourismNameKey(row.spot.name);
      if (featuredKeys.contains(k) &&
          recommendedScored.length > recommendedLimit + featuredKeys.length) {
        continue;
      }
      if (!seen.add(k)) continue;
      out.add(row);
      if (out.length >= recommendedLimit) break;
    }
    if (out.length < recommendedLimit) {
      for (final row in recommendedScored) {
        final k = normalizeTourismNameKey(row.spot.name);
        if (!seen.add(k)) continue;
        out.add(row);
        if (out.length >= recommendedLimit) break;
      }
    }
    _recommended = out;
    _cacheKey = key;

    if (kDebugMode && _featured.isNotEmpty) {
      final f = _featured.first;
      debugPrint(
        'HomeFeatured top="${f.spot.name}" score=${f.score.toStringAsFixed(3)} '
        'pop=${f.popularity.toStringAsFixed(2)} rating=${f.ratingScore.toStringAsFixed(2)} '
        'recent=${f.recentEngagement.toStringAsFixed(2)} quality=${f.quality.toStringAsFixed(2)}',
      );
    }
    if (kDebugMode && _recommended.isNotEmpty) {
      final r = _recommended.first;
      debugPrint(
        'HomeRecommended top="${r.spot.name}" score=${r.score.toStringAsFixed(3)} '
        'pref=${r.preferenceMatch.toStringAsFixed(2)} hist=${r.userHistory.toStringAsFixed(2)} '
        'route=${r.routeMatch.toStringAsFixed(2)}',
      );
    }

    revision.value++;
  }

  /// Rating Score = (normStars × 0.60) + (normCount × 0.40).
  /// Missing ratings → neutral 0.5 components.
  static double computeRatingScore({
    required double averageStars,
    required int ratingCount,
    required int maxRatingCount,
  }) {
    final hasStars = averageStars > 0;
    final normStars = hasStars ? (averageStars.clamp(0.0, 5.0) / 5.0) : 0.5;
    final normCount = ratingCount <= 0
        ? 0.5
        : _normalizeCount(ratingCount, maxRatingCount <= 0 ? ratingCount : maxRatingCount);
    return normStars * 0.60 + normCount * 0.40;
  }

  static int _effectiveRatingCount(TouristSpot spot) {
    if (spot.ratingCount > 0) return spot.ratingCount;
    // No dedicated count field: visitors are a soft reliability proxy only when
    // the spot has a published average rating.
    if (spot.rating > 0 && spot.visitors > 0) return spot.visitors;
    return 0;
  }

  static double _normalizeCount(num value, num max) {
    if (value <= 0) return 0.0;
    if (max <= 0) return 1.0;
    // Log scale so a few vs many raters still separates without crushing mid values.
    final n = math.log(1 + value.toDouble()) / math.log(1 + max.toDouble());
    return n.clamp(0.0, 1.0);
  }

  static double _recentEngagement(int updatedAtMs, int nowMs) {
    if (updatedAtMs <= 0) return 0.45; // neutral when unknown
    final ageDays = (nowMs - updatedAtMs) / (1000 * 60 * 60 * 24);
    if (ageDays <= 7) return 1.0;
    if (ageDays <= 30) return 0.75;
    if (ageDays <= 90) return 0.55;
    if (ageDays <= 365) return 0.35;
    return 0.2;
  }

  static double _qualityScore(TouristSpot spot) {
    var q = 0.0;
    if (spot.description.trim().length >= 40) q += 0.25;
    if (spot.imagePath.trim().isNotEmpty) q += 0.25;
    if (spot.latitude != null && spot.longitude != null) q += 0.2;
    if (spot.category.trim().isNotEmpty ||
        (spot.type.isNotEmpty && spot.type != 'spot')) {
      q += 0.15;
    }
    if (spot.entranceFee.trim().isNotEmpty ||
        spot.priceRange.trim().isNotEmpty) {
      q += 0.15;
    }
    return q.clamp(0.0, 1.0);
  }

  static double _preferenceMatch({
    required TouristSpot spot,
    required Set<String> interests,
    required Map<String, double> weights,
    required String? budgetTier,
    required String? transport,
    required Map<String, int> ratedTypes,
  }) {
    // Cold start: mild uniform preference so section is never empty.
    final selected = interests.isEmpty
        ? kTravelInterests.toSet()
        : interests;
    final scored = ContentBasedFiltering.filter(
      spots: [spot],
      selectedInterests: selected,
      interestWeights: weights,
      minSimilarity: 0.0,
    );
    var pref = scored.isEmpty ? 0.35 : scored.first.contentSimilarity;

    // Category / type affinity from positively rated spot types.
    final typeBoost = ratedTypes[spot.type] ?? 0;
    if (typeBoost > 0) {
      pref = (pref + 0.08 * math.min(3, typeBoost)).clamp(0.0, 1.0);
    }
    if (spot.category.isNotEmpty &&
        selected.any((i) =>
            spot.category.toLowerCase().contains(i.toLowerCase()) ||
            i.toLowerCase().contains(spot.category.toLowerCase()))) {
      pref = (pref + 0.1).clamp(0.0, 1.0);
    }

    // Budget: entrance fee vs last budget tier (soft).
    pref = (pref + _budgetAffinity(spot, budgetTier) * 0.12).clamp(0.0, 1.0);
    // Transport: walking-friendly spots for Walking mode.
    if ((transport ?? '').toLowerCase().contains('walk') &&
        (spot.walkingDistanceMinutes ?? 99) <= 20) {
      pref = (pref + 0.08).clamp(0.0, 1.0);
    }
    return pref.clamp(0.0, 1.0);
  }

  static double _budgetAffinity(TouristSpot spot, String? tier) {
    if (tier == null || tier.isEmpty) return 0.5;
    final fee = double.tryParse(
          spot.entranceFee.replaceAll(RegExp(r'[^0-9.]'), ''),
        ) ??
        0;
    final t = tier.toLowerCase();
    if (t.contains('budget') || t.contains('low')) {
      if (fee <= 50) return 1.0;
      if (fee <= 150) return 0.6;
      return 0.25;
    }
    if (t.contains('mid') || t.contains('moderate')) {
      if (fee <= 300) return 0.9;
      return 0.5;
    }
    if (t.contains('premium') || t.contains('high') || t.contains('luxury')) {
      return fee >= 100 ? 0.9 : 0.55;
    }
    return 0.5;
  }

  static double _userHistoryScore({
    required TouristSpot spot,
    required TravelHistoryProfile? profile,
    required SpotInteractionHistoryStore history,
  }) {
    final key = normalizeTourismNameKey(spot.name);
    final pref = history.preferenceFor(spot.name);

    // Explicit repeat-visit preference dominates.
    if (pref == RepeatVisitPreference.yes) return 1.0;
    if (pref == RepeatVisitPreference.no) return 0.12;

    var score = 0.45; // neutral baseline (visited without answer stays neutral)

    if (history.favoritedKeys.contains(key)) score += 0.25;
    if (history.itineraryKeys.contains(key)) score += 0.15;
    if (history.searchedKeys.contains(key)) score += 0.1;
    if (history.viewedKeys.contains(key)) score += 0.08;

    // Similar to past destinations / interests — not the exact same spot only.
    if (profile != null) {
      final spotTags = ContentBasedFiltering.spotInterests(spot);
      final overlap = spotTags.intersection(profile.interestTags).length;
      if (overlap > 0) score += 0.06 * math.min(3, overlap);
      for (final m in profile.visitedMunicipalityNames) {
        if (spot.location.toLowerCase().contains(m.toLowerCase()) ||
            m.toLowerCase().contains(spot.location.toLowerCase())) {
          score += 0.1;
          break;
        }
      }
      // Exact previously visited without preference → neutral (no auto-exclude).
      if (profile.visitedSpotNameKeys.contains(key) &&
          pref == RepeatVisitPreference.unknown) {
        score = score.clamp(0.4, 0.7);
      }
    }

    return score.clamp(0.0, 1.0);
  }

  static double _routeLocationMatch({
    required TouristSpot spot,
    required TravelHistoryProfile? profile,
    required ({String? start, String? end, List<String> along}) route,
  }) {
    final loc = spot.location.trim().toLowerCase();
    if (loc.isEmpty && route.start == null && route.end == null) {
      return 0.5; // no route context → neutral
    }

    final targets = <String>{
      if (route.start != null && route.start!.trim().isNotEmpty)
        route.start!.trim().toLowerCase(),
      if (route.end != null && route.end!.trim().isNotEmpty)
        route.end!.trim().toLowerCase(),
      for (final a in route.along)
        if (a.trim().isNotEmpty) a.trim().toLowerCase(),
    };

    if (targets.isEmpty) {
      // Fall back to municipalities from registration history.
      for (final m in profile?.visitedMunicipalityNames ?? const <String>{}) {
        targets.add(m.toLowerCase());
      }
      if (targets.isEmpty) return 0.5;
    }

    for (final t in targets) {
      if (loc.contains(t) || t.contains(loc)) return 1.0;
      if (spot.name.toLowerCase().contains(t)) return 0.85;
    }
    return 0.2;
  }
}
