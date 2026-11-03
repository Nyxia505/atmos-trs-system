// Shared display format for tourism events: word date + 12-hour time.

const _monthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// e.g. October 10, 2026
String formatEventDateWords(DateTime d) {
  return '${_monthNames[d.month - 1]} ${d.day}, ${d.year}';
}

/// e.g. 11:09 AM
String formatEventTime12(DateTime d) {
  final h = d.hour;
  final m = d.minute;
  final period = h >= 12 ? 'PM' : 'AM';
  var hour12 = h % 12;
  if (hour12 == 0) hour12 = 12;
  final mm = m < 10 ? '0$m' : '$m';
  return '$hour12:$mm $period';
}

/// e.g. October 10, 2026 · 11:09 AM
String formatEventDateTimeDisplay(DateTime d) {
  return '${formatEventDateWords(d)} · ${formatEventTime12(d)}';
}

DateTime _calendarDay(DateTime d) => DateTime(d.year, d.month, d.day);

int inclusiveCalendarDayCount(DateTime start, DateTime end) {
  var a = _calendarDay(start);
  var b = _calendarDay(end);
  if (b.isBefore(a)) {
    final swap = a;
    a = b;
    b = swap;
  }
  return b.difference(a).inDays + 1;
}

/// Compact range: November 5–10, 2026 or November 28 – December 3, 2026.
String formatEventDateRangeCompact(DateTime start, DateTime end) {
  var a = _calendarDay(start);
  var b = _calendarDay(end);
  if (b.isBefore(a)) {
    final swap = a;
    a = b;
    b = swap;
  }
  if (a == b) return formatEventDateWords(a);
  if (a.year == b.year && a.month == b.month) {
    return '${_monthNames[a.month - 1]} ${a.day}–${b.day}, ${a.year}';
  }
  if (a.year == b.year) {
    return '${_monthNames[a.month - 1]} ${a.day} – ${_monthNames[b.month - 1]} ${b.day}, ${a.year}';
  }
  return '${formatEventDateWords(a)} – ${formatEventDateWords(b)}';
}

/// Form field label: October 30, 2026 or November 5–10, 2026 (6 days).
String formatEventDateRangeField(DateTime start, DateTime end) {
  final days = inclusiveCalendarDayCount(start, end);
  if (days <= 1) return formatEventDateWords(start);
  return '${formatEventDateRangeCompact(start, end)} ($days days)';
}

/// Push notification body: municipality · venue, date · time, description.
String buildEventPushNotificationBody({
  required String municipality,
  required String venue,
  required DateTime dateTime,
  required String description,
  int maxLength = 280,
}) {
  final lines = <String>[];
  final location = <String>[
    if (municipality.trim().isNotEmpty) municipality.trim(),
    if (venue.trim().isNotEmpty) venue.trim(),
  ].join(' · ');
  if (location.isNotEmpty) lines.add(location);
  lines.add(formatEventDateTimeDisplay(dateTime));
  final desc = description.trim();
  if (desc.isNotEmpty) lines.add(desc);
  var body = lines.join('\n');
  if (body.length > maxLength) {
    body = '${body.substring(0, maxLength - 1)}…';
  }
  return body;
}
