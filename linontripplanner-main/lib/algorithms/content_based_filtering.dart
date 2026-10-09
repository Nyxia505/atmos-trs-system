import 'dart:math' as math;

import '../data.dart';
import 'trip_algorithm_models.dart';

/// Content-Based Filtering — cosine similarity between user profile and spots.
class ContentBasedFiltering {
  static const _typeToInterest = {
    'Nature': 'Nature',
    'Adventure': 'Adventure',
    'Culture': 'Culture',
    'Relaxation': 'Beaches',
    'Food': 'Food',
    'hotel': 'Food',
    'spot': 'Nature',
  };

  static const _keywordHints = {
    'beach': ['Beaches'],
    'island': ['Beaches', 'Nature'],
    'waterfall': ['Nature', 'Adventure'],
    'church': ['Culture', 'Historical Places'],
    'museum': ['Culture', 'Historical Places'],
    'heritage': ['Historical Places', 'Culture'],
    'festival': ['Festivals'],
    'market': ['Shopping', 'Food'],
    'mall': ['Shopping'],
    'bar': ['Nightlife'],
    'night': ['Nightlife'],
    'hike': ['Adventure', 'Nature'],
    'eco': ['Nature'],
  };

  /// Infers interest tags from free-text destinations (registration travel history).
  static Set<String> interestsFromDestinationText(String text) {
    final matched = <String>{};
    final blob = text.toLowerCase().trim();
    if (blob.isEmpty) return matched;
    for (final e in _keywordHints.entries) {
      if (blob.contains(e.key)) matched.addAll(e.value);
    }
    return matched;
  }

  static Set<String> spotInterests(TouristSpot spot) {
    final matched = <String>{};
    final mapped = _typeToInterest[spot.type];
    if (mapped != null) matched.add(mapped);
    if (spot.type == 'Culture') matched.add('Historical Places');
    final category = spot.category.trim().toLowerCase();
    if (category.contains('beach')) matched.addAll(['Beaches', 'Nature']);
    if (category.contains('mountain') || category.contains('falls')) {
      matched.addAll(['Nature', 'Adventure']);
    }
    if (category.contains('church') || category.contains('heritage')) {
      matched.addAll(['Culture', 'Historical Places']);
    }
    if (category.contains('park') || category.contains('garden')) {
      matched.add('Nature');
    }
    final blob =
        '${spot.name} ${spot.description} ${spot.location} ${spot.category}'
            .toLowerCase();
    for (final e in _keywordHints.entries) {
      if (blob.contains(e.key)) matched.addAll(e.value);
    }
    return matched;
  }

  static Map<String, double> _interestVector(
    Set<String> selected,
    Map<String, double> weights,
  ) {
    final vec = {for (final i in kTravelInterests) i: 0.0};
    for (final interest in selected) {
      if (vec.containsKey(interest)) {
        vec[interest] = 1.0 + (weights[interest] ?? 0) * 0.15;
      }
    }
    if (selected.isEmpty) {
      for (final k in vec.keys) {
        vec[k] = 0.3;
      }
    }
    return vec;
  }

  static Map<String, double> _spotVector(TouristSpot spot) {
    final vec = {for (final i in kTravelInterests) i: 0.0};
    for (final tag in spotInterests(spot)) {
      if (vec.containsKey(tag)) vec[tag] = 1.0;
    }
    if (spot.type.isNotEmpty) vec['type_${spot.type}'] = 1.0;
    vec['_rating'] = spot.rating / 5.0;
    return vec;
  }

  static double _cosine(Map<String, double> a, Map<String, double> b) {
    final keys = {...a.keys, ...b.keys};
    var dot = 0.0;
    for (final k in keys) {
      dot += (a[k] ?? 0) * (b[k] ?? 0);
    }
    var na = 0.0, nb = 0.0;
    for (final v in a.values) {
      na += v * v;
    }
    for (final v in b.values) {
      nb += v * v;
    }
    if (na == 0 || nb == 0) return 0;
    return dot / (math.sqrt(na) * math.sqrt(nb));
  }

  static List<ScoredSpotData> filter({
    required List<TouristSpot> spots,
    required Set<String> selectedInterests,
    required Map<String, double> interestWeights,
    double minSimilarity = 0.12,
  }) {
    final userVec = _interestVector(selectedInterests, interestWeights);
    final ranked = <({double sim, TouristSpot spot})>[];

    for (final spot in spots) {
      final sim = _cosine(userVec, _spotVector(spot));
      if (selectedInterests.isNotEmpty) {
        if (spotInterests(spot).intersection(selectedInterests).isEmpty) {
          continue;
        }
      }
      if (sim >= minSimilarity || selectedInterests.isEmpty) {
        ranked.add((sim: sim, spot: spot));
      }
    }

    ranked.sort((a, b) => b.sim.compareTo(a.sim));
    return ranked
        .map(
          (e) => ScoredSpotData(
            spot: e.spot,
            contentSimilarity: double.parse(e.sim.toStringAsFixed(4)),
          ),
        )
        .toList();
  }
}
