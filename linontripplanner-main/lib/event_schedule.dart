import 'data.dart';
import 'event_datetime_format.dart';

/// Unique catalog locations currently loaded for the event form.
List<Municipality> eventLocationCatalog() {
  final byName = <String, Municipality>{};
  for (final m in municipalities) {
    final name = m.name.trim();
    if (name.isEmpty) continue;
    byName.putIfAbsent(name, () => m);
  }
  final list = byName.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  return list;
}

List<Municipality> eventCityLocations([List<Municipality>? catalog]) {
  return [
    for (final m in catalog ?? eventLocationCatalog())
      if (m.divisionLabel == 'City') m,
  ];
}

List<Municipality> eventMunicipalityLocations([List<Municipality>? catalog]) {
  return [
    for (final m in catalog ?? eventLocationCatalog())
      if (m.divisionLabel != 'City') m,
  ];
}

DateTime eventCalendarDay(DateTime d) => DateTime(d.year, d.month, d.day);

String formatEventCalendarDateKey(DateTime d) {
  final y = d.year.toString().padLeft(4, '0');
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

DateTime? parseEventCalendarDateKey(String raw) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw.trim());
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}

DateTime combineEventDateAndTime(DateTime day, DateTime timeSource) {
  return DateTime(
    day.year,
    day.month,
    day.day,
    timeSource.hour,
    timeSource.minute,
  );
}

List<DateTime> eventExpandedCalendarDays(TourismEvent event) {
  if (event.dateMode == TourismEventDateMode.range) {
    final startRaw = event.rangeStart ?? event.dateTime;
    final endRaw = event.rangeEnd ?? event.rangeStart ?? event.dateTime;
    var start = eventCalendarDay(startRaw);
    var end = eventCalendarDay(endRaw);
    if (end.isBefore(start)) {
      final swap = start;
      start = end;
      end = swap;
    }
    final out = <DateTime>[];
    var cursor = start;
    while (!cursor.isAfter(end)) {
      out.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }
    return out;
  }
  if (event.eventDates.isNotEmpty) {
    final unique = <String, DateTime>{};
    for (final d in event.eventDates) {
      final day = eventCalendarDay(d);
      unique[formatEventCalendarDateKey(day)] = day;
    }
    unique.putIfAbsent(
      formatEventCalendarDateKey(event.dateTime),
      () => eventCalendarDay(event.dateTime),
    );
    final list = unique.values.toList()..sort((a, b) => a.compareTo(b));
    return list;
  }
  return [eventCalendarDay(event.dateTime)];
}

String formatEventLocationSummary(List<String> names) {
  final selected = <String>[
    for (final name in names)
      if (name.trim().isNotEmpty) name.trim(),
  ];
  if (selected.isEmpty) return '';
  final catalog = eventLocationCatalog();
  final cityNames = {
    for (final m in eventCityLocations(catalog)) m.name,
  };
  final muniNames = {
    for (final m in eventMunicipalityLocations(catalog)) m.name,
  };
  final selectedSet = selected.toSet();
  if (catalog.isNotEmpty &&
      selectedSet.length == catalog.length &&
      selectedSet.containsAll(catalog.map((m) => m.name))) {
    return 'All Municipalities and Cities (${catalog.length} locations)';
  }
  if (muniNames.isNotEmpty &&
      selectedSet.length == muniNames.length &&
      selectedSet.containsAll(muniNames)) {
    return 'All Municipalities (${muniNames.length} locations)';
  }
  if (cityNames.isNotEmpty &&
      selectedSet.length == cityNames.length &&
      selectedSet.containsAll(cityNames)) {
    return 'All Cities (${cityNames.length} locations)';
  }
  if (selected.length == 1) return selected.first;
  return '${selected.length} locations selected';
}

String formatEventDatesSummary(TourismEvent event) {
  switch (event.dateMode) {
    case TourismEventDateMode.range:
      final start = event.rangeStart ?? event.dateTime;
      final end = event.rangeEnd ?? start;
      if (eventCalendarDay(start) == eventCalendarDay(end)) {
        return formatEventDateWords(start);
      }
      return formatEventDateRangeCompact(start, end);
    case TourismEventDateMode.multiple:
      final days = eventExpandedCalendarDays(event);
      if (days.isEmpty) return formatEventDateWords(event.dateTime);
      if (days.length == 1) return formatEventDateWords(days.first);
      return days.map(formatEventDateWords).join(' · ');
    case TourismEventDateMode.single:
      return formatEventDateWords(event.dateTime);
  }
}

String formatEventListLocationLine(TourismEvent event) {
  return formatEventLocationSummary(event.locationNames);
}

String formatEventScheduleSubtitle(TourismEvent event) {
  final time = formatEventTime12(event.dateTime);
  switch (event.dateMode) {
    case TourismEventDateMode.single:
      return formatEventDateTimeDisplay(event.dateTime);
    case TourismEventDateMode.multiple:
    case TourismEventDateMode.range:
      return '${formatEventDatesSummary(event)} · $time';
  }
}

List<String> splitEventLocationNames(String raw) {
  return [
    for (final part in raw.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];
}

bool isAnnouncementBackedEventId(String id) =>
    id.trim().startsWith('announcement_');

String announcementIdFromEventId(String id) {
  const prefix = 'announcement_';
  final trimmed = id.trim();
  return trimmed.startsWith(prefix) ? trimmed.substring(prefix.length) : trimmed;
}

bool eventOccursOnCalendarDay(TourismEvent event, DateTime day) {
  final key = eventCalendarDay(day);
  return eventExpandedCalendarDays(event).any((d) => d == key);
}

bool eventOverlapsLocalDateRange(
  TourismEvent event,
  DateTime start,
  DateTime end,
) {
  final startDay = eventCalendarDay(start);
  final endDay = eventCalendarDay(end);
  return eventExpandedCalendarDays(event).any(
    (day) => !day.isBefore(startDay) && !day.isAfter(endDay),
  );
}

bool eventMatchesLocationName(TourismEvent event, String location) {
  final needle = location.trim().toLowerCase();
  if (needle.isEmpty) return false;
  for (final name in event.locationNames) {
    final lower = name.toLowerCase();
    if (lower == needle || lower.contains(needle) || needle.contains(lower)) {
      return true;
    }
  }
  return false;
}
