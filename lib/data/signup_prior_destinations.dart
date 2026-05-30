/// Selectable options for "last three tourist destinations" on signup.
const String kSignupPriorDestinationNone = '— None —';

const List<String> signupPriorDestinationOptions = [
  kSignupPriorDestinationNone,
  // Misamis Occidental & nearby
  'Misamis Occidental',
  'Oroquieta City',
  'Ozamiz City',
  'Tangub City',
  'Sinacaban',
  'Tudela',
  'Jimenez',
  'Baliangao',
  // Popular Philippine destinations
  'Boracay, Aklan',
  'Palawan',
  'El Nido, Palawan',
  'Puerto Princesa, Palawan',
  'Cebu City',
  'Mactan, Cebu',
  'Bohol',
  'Siargao',
  'Davao City',
  'Manila',
  'Baguio City',
  'Vigan, Ilocos Sur',
  'La Union',
  'Batanes',
  'Camiguin',
  'Dumaguete',
  'Iloilo City',
  'Bacolod City',
  'Cagayan de Oro',
  'Zamboanga City',
  'Tagaytay',
  'Coron, Palawan',
  // International (common for foreign visitors)
  'Singapore',
  'Hong Kong',
  'Japan',
  'South Korea',
  'Thailand',
  'Vietnam',
  'Malaysia',
  'Indonesia (Bali)',
  'United States',
  'Canada',
  'Australia',
  'United Kingdom',
  'China',
  'Taiwan',
  'Other (not listed)',
];

/// Options for one dropdown, excluding destinations already picked in other slots.
List<String> signupPriorDestinationChoices({
  String? exclude1,
  String? exclude2,
  String? exclude3,
}) {
  final taken = <String>{
    if (exclude1 != null && exclude1 != kSignupPriorDestinationNone) exclude1,
    if (exclude2 != null && exclude2 != kSignupPriorDestinationNone) exclude2,
    if (exclude3 != null && exclude3 != kSignupPriorDestinationNone) exclude3,
  };
  return signupPriorDestinationOptions
      .where((d) => d == kSignupPriorDestinationNone || !taken.contains(d))
      .toList();
}

String signupPriorDestinationValueForSave(String? selected) {
  if (selected == null ||
      selected.isEmpty ||
      selected == kSignupPriorDestinationNone) {
    return '';
  }
  return selected;
}
