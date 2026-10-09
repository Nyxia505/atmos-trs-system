import '../data.dart';

/// Internal scored spot passed between algorithm stages.
class ScoredSpotData {
  final TouristSpot spot;
  final double contentSimilarity;
  final double weightedScore;
  final List<String> matchReasons;
  final bool exactBudgetMatch;

  const ScoredSpotData({
    required this.spot,
    this.contentSimilarity = 0,
    this.weightedScore = 0,
    this.matchReasons = const [],
    this.exactBudgetMatch = false,
  });

  ScoredSpotData copyWith({
    double? contentSimilarity,
    double? weightedScore,
    List<String>? matchReasons,
    bool? exactBudgetMatch,
  }) {
    return ScoredSpotData(
      spot: spot,
      contentSimilarity: contentSimilarity ?? this.contentSimilarity,
      weightedScore: weightedScore ?? this.weightedScore,
      matchReasons: matchReasons ?? this.matchReasons,
      exactBudgetMatch: exactBudgetMatch ?? this.exactBudgetMatch,
    );
  }

  String get key => '${spot.name}|${spot.location}';
}

typedef LatLngPair = ({double lat, double lng});
