import '../data.dart';
import '../event_schedule.dart';
import 'trip_wizard_controller.dart';

/// Municipalities / cities touched by the current trip plan.
Set<String> tripItineraryMunicipalityNames(TripWizardController wizard) {
  final names = <String>{};
  void add(String? raw) {
    final name = raw?.trim() ?? '';
    if (name.isNotEmpty) names.add(name);
  }

  add(wizard.start?.name);
  add(wizard.end?.name);
  for (final m in wizard.municipalitiesOnRoute) {
    add(m.name);
  }
  for (final day in wizard.spotsByDay) {
    for (final spot in day) {
      add(spot.location);
    }
  }
  return names;
}

bool _eventIsExpired(TourismEvent event, DateTime today) {
  final days = eventExpandedCalendarDays(event);
  if (days.isEmpty) return true;
  return days.last.isBefore(today);
}

/// Province-wide / all-cities / all-municipalities coverage for an event.
bool _eventIsProvinceWideForTrip(
  TourismEvent event,
  Set<String> tripMunicipalities,
) {
  final names = event.locationNames;
  if (names.isEmpty) return false;
  final summary = formatEventLocationSummary(names);
  if (summary.startsWith('All Municipalities and Cities')) {
    return tripMunicipalities.isNotEmpty;
  }
  if (summary.startsWith('All Municipalities')) {
    final catalog = eventMunicipalityLocations();
    if (catalog.isEmpty) return tripMunicipalities.isNotEmpty;
    return tripMunicipalities.any(
      (trip) => catalog.any(
        (m) =>
            m.name.toLowerCase() == trip.toLowerCase() ||
            trip.toLowerCase().contains(m.name.toLowerCase()) ||
            m.name.toLowerCase().contains(trip.toLowerCase()),
      ),
    );
  }
  if (summary.startsWith('All Cities')) {
    final catalog = eventCityLocations();
    if (catalog.isEmpty) return tripMunicipalities.isNotEmpty;
    return tripMunicipalities.any(
      (trip) => catalog.any(
        (m) =>
            m.name.toLowerCase() == trip.toLowerCase() ||
            trip.toLowerCase().contains(m.name.toLowerCase()) ||
            m.name.toLowerCase().contains(trip.toLowerCase()),
      ),
    );
  }
  return false;
}

bool _eventMatchesAnyTripMunicipality(
  TourismEvent event,
  Set<String> tripMunicipalities,
) {
  if (_eventIsProvinceWideForTrip(event, tripMunicipalities)) return true;
  for (final trip in tripMunicipalities) {
    if (eventMatchesLocationName(event, trip)) return true;
  }
  return false;
}

/// Signature of travel dates + itinerary places used to gate "show once".
String tripTravelEventsMatchSignature(TripWizardController wizard) {
  final arrival = wizard.arrivalDate;
  final departure = wizard.departureDate ?? arrival;
  final a = arrival == null
      ? ''
      : '${arrival.year}-${arrival.month}-${arrival.day}';
  final d = departure == null
      ? ''
      : '${departure.year}-${departure.month}-${departure.day}';
  final munis = tripItineraryMunicipalityNames(wizard).toList()..sort();
  return '$a|$d|${munis.join(',')}';
}

/// OPTACA events that overlap the trip dates and itinerary municipalities.
List<TourismEvent> matchingTravelEventsForTrip(
  TripWizardController wizard, {
  List<TourismEvent>? catalog,
  DateTime? now,
}) {
  final arrival = wizard.arrivalDate;
  if (arrival == null) return const [];
  final departure = wizard.departureDate ?? arrival;
  final tripMunis = tripItineraryMunicipalityNames(wizard);
  if (tripMunis.isEmpty) return const [];

  final today = eventCalendarDay(now ?? DateTime.now());
  final source = catalog ?? tourismEvents;
  final matched = <TourismEvent>[];

  for (final event in source) {
    if (event.title.trim().isEmpty) continue;
    if (_eventIsExpired(event, today)) continue;
    if (!eventOverlapsLocalDateRange(event, arrival, departure)) continue;
    if (!_eventMatchesAnyTripMunicipality(event, tripMunis)) continue;
    matched.add(event);
  }

  matched.sort((a, b) {
    final aDay = eventExpandedCalendarDays(a).first;
    final bDay = eventExpandedCalendarDays(b).first;
    final byDate = aDay.compareTo(bDay);
    if (byDate != 0) return byDate;
    return a.title.toLowerCase().compareTo(b.title.toLowerCase());
  });
  return matched;
}
