import '../data.dart';
import 'content_based_filtering.dart';
import 'trip_algorithm_models.dart';

/// Weighted Scoring Algorithm — combines interest, budget, rating, transport, behavior.
class WeightedScoring {
  static const _weights = {
    'interest_match': 0.30,
    'budget_fit': 0.25,
    'rating': 0.20,
    'transport_access': 0.15,
    'behavior': 0.10,
  };

  static List<double> _parsePrices(String text) {
    return RegExp(r'(\d+(?:\.\d+)?)')
        .allMatches(text)
        .map((m) => double.tryParse(m.group(1) ?? '') ?? 0)
        .where((v) => v > 0)
        .toList();
  }

  static ({double component, bool exact, bool within}) _budget(
    TouristSpot spot,
    double budget,
  ) {
    final prices = _parsePrices(spot.priceRange);
    if (prices.isEmpty || budget <= 0) {
      return (component: 1.0, exact: false, within: true);
    }
    final lo = prices.reduce((a, b) => a < b ? a : b);
    final hi = prices.reduce((a, b) => a > b ? a : b);
    if (lo > budget) return (component: 0.0, exact: false, within: false);
    if (budget >= lo && budget <= hi) {
      return (component: 1.0, exact: true, within: true);
    }
    return (component: 0.65, exact: false, within: true);
  }

  static double _transport(TouristSpot spot, String mode) {
    final hasCoords = spot.latitude != null && spot.longitude != null;
    switch (mode) {
      case 'Public Transport':
        return hasCoords ? 0.85 : 0.55;
      case 'Motorcycle':
        return 0.88;
      default:
        return 0.82;
    }
  }

  static ScoredSpotData? score({
    required ScoredSpotData input,
    required Set<String> selectedInterests,
    required double budget,
    required String transportMode,
    required Map<String, int> ratedTypes,
  }) {
    final spot = input.spot;
    final reasons = <String>[];
    final matched = selectedInterests.isEmpty
        ? ContentBasedFiltering.spotInterests(spot)
        : ContentBasedFiltering.spotInterests(spot)
            .intersection(selectedInterests);

    double interestComponent;
    if (selectedInterests.isNotEmpty) {
      if (matched.isEmpty) return null;
      final frac = matched.length / selectedInterests.length;
      interestComponent =
          (frac + input.contentSimilarity * 0.35).clamp(0.0, 1.0);
      reasons.add('Matches ${matched.join(', ')}');
    } else {
      interestComponent = 0.7;
    }

    final budgetResult = _budget(spot, budget);
    if (!budgetResult.within && budget > 0) return null;
    if (budgetResult.exact) {
      reasons.add('Fits your budget closely');
    } else if (budgetResult.within) {
      reasons.add('Within budget');
    }

    final ratingComponent = (spot.rating / 5.0).clamp(0.0, 1.0);
    final transportComponent = _transport(spot, transportMode);
    final behaviorComponent =
        ((ratedTypes[spot.type] ?? 0) * 0.25).clamp(0.0, 1.0);
    if ((ratedTypes[spot.type] ?? 0) > 0) {
      reasons.add('You rated similar ${spot.type} spots highly');
    }
    final breakdown = {
      'interest_match': interestComponent,
      'budget_fit': budgetResult.component,
      'rating': ratingComponent,
      'transport_access': transportComponent,
      'behavior': behaviorComponent,
    };
    var total = 0.0;
    for (final e in _weights.entries) {
      total += (breakdown[e.key] ?? 0) * e.value;
    }
    total *= 100;

    return input.copyWith(
      weightedScore: double.parse(total.toStringAsFixed(2)),
      matchReasons: reasons.toSet().toList(),
      exactBudgetMatch: budgetResult.exact,
    );
  }

  static List<ScoredSpotData> scoreAll({
    required List<ScoredSpotData> candidates,
    required Set<String> selectedInterests,
    required double budget,
    required String transportMode,
    required Map<String, int> ratedTypes,
  }) {
    final out = <ScoredSpotData>[];
    for (final c in candidates) {
      final s = score(
        input: c,
        selectedInterests: selectedInterests,
        budget: budget,
        transportMode: transportMode,
        ratedTypes: ratedTypes,
      );
      if (s != null && s.weightedScore > 0) out.add(s);
    }
    out.sort((a, b) => b.weightedScore.compareTo(a.weightedScore));
    return out;
  }
}
