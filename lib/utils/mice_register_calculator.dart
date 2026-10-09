import 'package:atmos_trs_system/config/mice_event_types.dart';
import 'package:atmos_trs_system/models/mice_register.dart';

/// Pure CUS MICE math: ordering, control numbers, totals and validation.
abstract final class MiceRegisterCalculator {
  /// Longest single event accepted (guards typos like a wrong end year).
  static const maxEventDays = 62;

  /// Events whose start date falls in [year]/[month], in CUS order.
  static List<MiceEvent> eventsInMonth(Iterable<MiceEvent> events, int year, int month) =>
      sorted(events.where((e) => e.dateStart.year == year && e.dateStart.month == month));

  /// CUS order: start date, then event name, then id (stable).
  static List<MiceEvent> sorted(Iterable<MiceEvent> events) => events.toList()
    ..sort((a, b) {
      final c = a.dateStart.compareTo(b.dateStart);
      if (c != 0) return c;
      final n = a.eventName.toLowerCase().compareTo(b.eventName.toLowerCase());
      return n != 0 ? n : a.id.compareTo(b.id);
    });

  /// Control numbers (CN) 1…n per venue-month in date order — never typed.
  static Map<String, int> controlNumbers(Iterable<MiceEvent> monthEvents) {
    final out = <String, int>{};
    var n = 0;
    for (final e in sorted(monthEvents)) {
      out[e.id] = ++n;
    }
    return out;
  }

  static MiceMonthTotals totals(Iterable<MiceEvent> events) {
    var count = 0, foreign = 0, local = 0, male = 0, female = 0;
    var exhibitions = 0, exhibitors = 0, visitors = 0, multi = 0;
    var hours = 0.0;
    final byCategory = <String, MiceCategoryTotals>{};
    final byCountry = <String, int>{};
    for (final e in events) {
      count++;
      hours += e.hours;
      foreign += e.foreign;
      local += e.local;
      male += e.male;
      female += e.female;
      if (e.isMultiDay) multi++;
      if (e.hasExhibit) {
        exhibitions++;
        exhibitors += e.exhibitors;
        visitors += e.exhibitVisitors;
      }
      final k = e.category.id;
      byCategory[k] = (byCategory[k] ?? const MiceCategoryTotals()) +
          MiceCategoryTotals(events: 1, attendees: e.total, hours: e.hours);
      for (final c in e.foreignCountries.entries) {
        final label = c.key.trim();
        if (label.isEmpty || c.value <= 0) continue;
        byCountry[label] = (byCountry[label] ?? 0) + c.value;
      }
    }
    return MiceMonthTotals(
      events: count,
      hours: hours,
      foreign: foreign,
      local: local,
      male: male,
      female: female,
      exhibitions: exhibitions,
      exhibitors: exhibitors,
      exhibitVisitors: visitors,
      multiDayEvents: multi,
      byCategory: byCategory,
      byCountry: byCountry,
    );
  }

  /// Sums saved header totals (quarter / year / multi-venue rollups).
  static MiceMonthTotals combine(Iterable<MiceMonthTotals> list) {
    var events = 0, foreign = 0, local = 0, male = 0, female = 0;
    var exhibitions = 0, exhibitors = 0, visitors = 0, multi = 0;
    var hours = 0.0;
    final byCategory = <String, MiceCategoryTotals>{};
    final byCountry = <String, int>{};
    for (final t in list) {
      events += t.events;
      hours += t.hours;
      foreign += t.foreign;
      local += t.local;
      male += t.male;
      female += t.female;
      exhibitions += t.exhibitions;
      exhibitors += t.exhibitors;
      visitors += t.exhibitVisitors;
      multi += t.multiDayEvents;
      t.byCategory.forEach((k, v) => byCategory[k] = (byCategory[k] ?? const MiceCategoryTotals()) + v);
      t.byCountry.forEach((k, v) => byCountry[k] = (byCountry[k] ?? 0) + v);
    }
    return MiceMonthTotals(
      events: events,
      hours: hours,
      foreign: foreign,
      local: local,
      male: male,
      female: female,
      exhibitions: exhibitions,
      exhibitors: exhibitors,
      exhibitVisitors: visitors,
      multiDayEvents: multi,
      byCategory: byCategory,
      byCountry: byCountry,
    );
  }

  /// Blocking problems for one event (empty = valid). Same style as DAE rows:
  /// totals are computed, the sex split must match the attendee total.
  static List<String> validate(MiceEvent e) {
    final issues = <String>[];
    if (e.eventName.trim().isEmpty) issues.add('Event name is required.');
    if (e.eventType.trim().isEmpty) issues.add('Pick or add an event type.');
    if (e.dateEnd != null && e.dateEnd!.isBefore(e.dateStart)) {
      issues.add('End date is before the start date.');
    } else if (e.days > maxEventDays) {
      issues.add('Event spans ${e.days} days — check the end date (max $maxEventDays).');
    }
    if (e.hours <= 0) issues.add('Enter the number of hours.');
    if (e.hours > e.days * 24) issues.add('Hours exceed ${e.days * 24} (${e.days} day(s) × 24).');
    if (e.foreign < 0 || e.local < 0 || e.male < 0 || e.female < 0) {
      issues.add('Counts cannot be negative.');
    }
    if (e.total <= 0) issues.add('Enter at least one attendee (foreign or local).');
    if (e.male + e.female != e.total) {
      issues.add('Male + Female (${e.male + e.female}) must equal total attendees (${e.total}).');
    }
    if (e.hasExhibit && e.exhibitors <= 0) issues.add('Exhibit events need the number of exhibitors.');
    final countries = e.foreignCountries.values.fold<int>(0, (a, b) => a + b);
    if (countries > e.foreign) {
      issues.add('Country breakdown ($countries) exceeds foreign attendees (${e.foreign}).');
    }
    return issues;
  }

  /// Non-blocking hints shown as a badge (form still saves).
  static List<String> warnings(MiceEvent e) => [
        if (e.organizerName.trim().isEmpty) 'Organizer name missing.',
        if (e.contactNo.trim().isEmpty && e.contactPerson.trim().isEmpty) 'Contact person / tel. no. missing.',
        if (e.foreign > 0 && e.foreignCountries.isEmpty) 'Foreign attendees without country breakdown (optional).',
      ];

  /// CUS DATE cell: "10/5/2026", "10/5–7/2026", "10/30/2026–11/2/2026".
  static String dateLabel(MiceEvent e) {
    final s = e.dateStart;
    String d(DateTime x) => '${x.month}/${x.day}/${x.year}';
    if (!e.isMultiDay) return d(s);
    final l = e.lastDay;
    if (l.year == s.year && l.month == s.month) return '${s.month}/${s.day}–${l.day}/${s.year}';
    return '${d(s)}–${d(l)}';
  }

  /// "4", "2.5" — hours without trailing zeros.
  static String hoursLabel(double h) =>
      h == h.roundToDouble() ? h.round().toString() : h.toStringAsFixed(1);

  /// Category totals in catalog order (non-empty only).
  static List<(MiceCategory, MiceCategoryTotals)> categoryBreakdown(MiceMonthTotals t) => [
        for (final c in MiceCategory.values)
          if ((t.byCategory[c.id]?.events ?? 0) > 0) (c, t.byCategory[c.id]!),
      ];
}
