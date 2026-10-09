import 'dart:math' as math;

import '../data.dart';

/// Anonymized user–item signals for collaborative filtering (no PII).
class CollaborativeUserProfile {
  final String userId;
  /// Normalized spot keys the user implicitly favored (from travel history).
  final Map<String, double> itemScores;
  /// Interest tag weights for user–user similarity.
  final Map<String, double> tagScores;

  const CollaborativeUserProfile({
    required this.userId,
    this.itemScores = const {},
    this.tagScores = const {},
  });

  bool get hasSignals => itemScores.isNotEmpty || tagScores.isNotEmpty;
}

/// User-based + item-based collaborative filtering (on-device).
class CollaborativeFiltering {
  CollaborativeFiltering._();

  static double _cosine(
    Map<String, double> a,
    Map<String, double> b,
  ) {
    if (a.isEmpty || b.isEmpty) return 0;
    final keys = {...a.keys, ...b.keys};
    var dot = 0.0;
    var na = 0.0;
    var nb = 0.0;
    for (final k in keys) {
      final va = a[k] ?? 0;
      final vb = b[k] ?? 0;
      dot += va * vb;
      na += va * va;
      nb += vb * vb;
    }
    if (na == 0 || nb == 0) return 0;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }

  /// User-based CF: neighbors with similar travel history recommend their liked spots.
  static Map<String, double> userBasedScores({
    required Map<String, double> targetItems,
    required Map<String, double> targetTags,
    required List<CollaborativeUserProfile> peers,
    int neighborK = 15,
    double minNeighborSim = 0.08,
  }) {
    if (peers.isEmpty) return {};

    final neighbors = <({CollaborativeUserProfile peer, double sim})>[];
    for (final p in peers) {
      var sim = _cosine(targetItems, p.itemScores);
      if (targetTags.isNotEmpty && p.tagScores.isNotEmpty) {
        sim = sim * 0.65 + _cosine(targetTags, p.tagScores) * 0.35;
      }
      if (sim >= minNeighborSim) {
        neighbors.add((peer: p, sim: sim));
      }
    }
    if (neighbors.isEmpty) return {};

    neighbors.sort((a, b) => b.sim.compareTo(a.sim));
    final top = neighbors.take(neighborK).toList();
    var simSum = 0.0;
    for (final n in top) {
      simSum += n.sim;
    }
    if (simSum <= 0) return {};

    final scores = <String, double>{};
    for (final n in top) {
      final weight = n.sim / simSum;
      for (final e in n.peer.itemScores.entries) {
        if (targetItems.containsKey(e.key)) continue;
        scores[e.key] = (scores[e.key] ?? 0) + weight * e.value;
      }
    }
    return scores;
  }

  /// Item-based CF: spots co-liked by similar travelers are similar items.
  static Map<String, Map<String, double>> _itemCooccurrence(
    List<CollaborativeUserProfile> peers,
  ) {
    final cooc = <String, Map<String, double>>{};
    for (final p in peers) {
      final keys = p.itemScores.keys.toList();
      for (var i = 0; i < keys.length; i++) {
        for (var j = i + 1; j < keys.length; j++) {
          final a = keys[i];
          final b = keys[j];
          cooc.putIfAbsent(a, () => {})[b] =
              (cooc[a]?[b] ?? 0) + 1;
          cooc.putIfAbsent(b, () => {})[a] =
              (cooc[b]?[a] ?? 0) + 1;
        }
      }
    }
    return cooc;
  }

  static Map<String, double> itemBasedScores({
    required Map<String, double> targetItems,
    required List<CollaborativeUserProfile> peers,
  }) {
    if (targetItems.isEmpty || peers.isEmpty) return {};

    final cooc = _itemCooccurrence(peers);
    final pop = <String, double>{};
    for (final p in peers) {
      for (final k in p.itemScores.keys) {
        pop[k] = (pop[k] ?? 0) + 1;
      }
    }

    final scores = <String, double>{};
    for (final seed in targetItems.keys) {
      final neighbors = cooc[seed];
      if (neighbors == null) continue;
      final popA = pop[seed] ?? 1;
      for (final e in neighbors.entries) {
        if (targetItems.containsKey(e.key)) continue;
        final popB = pop[e.key] ?? 1;
        final sim = e.value / math.sqrt(popA * popB);
        scores[e.key] = (scores[e.key] ?? 0) + sim * (targetItems[seed] ?? 1);
      }
    }
    return scores;
  }

  /// Combined CF score per catalog spot key.
  static Map<String, double> combinedScores({
    required Map<String, double> targetItems,
    required Map<String, double> targetTags,
    required List<CollaborativeUserProfile> peers,
  }) {
    final user = userBasedScores(
      targetItems: targetItems,
      targetTags: targetTags,
      peers: peers,
    );
    final item = itemBasedScores(
      targetItems: targetItems,
      peers: peers,
    );

    final merged = <String, double>{};
    void merge(Map<String, double> src, double weight) {
      for (final e in src.entries) {
        merged[e.key] = (merged[e.key] ?? 0) + e.value * weight;
      }
    }

    merge(user, 0.55);
    merge(item, 0.45);
    return merged;
  }

  /// Ranks [catalog] using collaborative scores; returns empty if no peer data.
  static List<({TouristSpot spot, double score})> rankSpots({
    required List<TouristSpot> catalog,
    required Map<String, double> targetItems,
    required Map<String, double> targetTags,
    required List<CollaborativeUserProfile> peers,
    int limit = 20,
  }) {
    final cf = combinedScores(
      targetItems: targetItems,
      targetTags: targetTags,
      peers: peers,
    );
    if (cf.isEmpty) return [];

    final ranked = <({TouristSpot spot, double score})>[];
    for (final spot in catalog) {
      final key = normalizeTourismNameKey(spot.name);
      final cfScore = cf[key];
      if (cfScore == null || cfScore <= 0) continue;
      ranked.add((
        spot: spot,
        score: cfScore + spot.rating * 0.05,
      ));
    }

    ranked.sort((a, b) => b.score.compareTo(a.score));
    if (ranked.length <= limit) return ranked;
    return ranked.take(limit).toList();
  }
}
