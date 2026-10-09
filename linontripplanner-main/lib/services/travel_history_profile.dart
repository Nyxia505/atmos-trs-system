/// Signals from the tourist's Firestore registration (`tourists/{uid}`).
class TravelHistoryProfile {
  /// Past destinations from registration (`travelHistory` / `lastDestination*`).
  final List<String> pastDestinations;
  final Set<String> interestTags;
  final Map<String, double> interestWeights;
  final Set<String> visitedSpotNameKeys;
  final Set<String> visitedMunicipalityNames;

  const TravelHistoryProfile({
    this.pastDestinations = const [],
    this.interestTags = const {},
    this.interestWeights = const {},
    this.visitedSpotNameKeys = const {},
    this.visitedMunicipalityNames = const {},
  });

  bool get hasSignals =>
      pastDestinations.isNotEmpty ||
      interestTags.isNotEmpty ||
      visitedSpotNameKeys.isNotEmpty ||
      visitedMunicipalityNames.isNotEmpty;
}