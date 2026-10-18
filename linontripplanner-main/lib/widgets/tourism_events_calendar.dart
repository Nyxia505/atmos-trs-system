import 'package:flutter/material.dart';

import '../data.dart';
import '../event_datetime_format.dart';
import 'municipality_image.dart';
import 'tourism_plan_ui.dart';

/// Month grid calendar for [TourismEvent] lists (Moodle-style layout).
class TourismEventsCalendar extends StatefulWidget {
  const TourismEventsCalendar({
    super.key,
    required this.events,
    this.accentColor = AppColors.primary,
    this.onEventTap,
    this.onDayTap,
    this.initialMonth,
    this.titleOnly = false,
  });

  final List<TourismEvent> events;
  final Color accentColor;
  final void Function(TourismEvent event)? onEventTap;
  final void Function(DateTime day, List<TourismEvent> eventsOnDay)? onDayTap;
  final DateTime? initialMonth;
  /// When true, cells and detail sheets show event titles only (no time/venue/etc.).
  final bool titleOnly;

  @override
  State<TourismEventsCalendar> createState() => _TourismEventsCalendarState();
}

class _TourismEventsCalendarState extends State<TourismEventsCalendar> {
  static const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  late DateTime _monthStart;
  DateTime? _focusedDay;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialMonth ?? DateTime.now();
    _monthStart = DateTime(seed.year, seed.month);
  }

  @override
  void didUpdateWidget(covariant TourismEventsCalendar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final becameNonEmpty =
        oldWidget.events.isEmpty && widget.events.isNotEmpty;
    if (becameNonEmpty) {
      final seed = widget.initialMonth ?? widget.events.first.dateTime;
      _monthStart = DateTime(seed.year, seed.month);
      return;
    }
    if (widget.initialMonth != null &&
        (widget.initialMonth!.year != _monthStart.year ||
            widget.initialMonth!.month != _monthStart.month)) {
      _monthStart = DateTime(
        widget.initialMonth!.year,
        widget.initialMonth!.month,
      );
    }
  }

  void _shiftMonth(int delta) {
    setState(() {
      _monthStart = DateTime(_monthStart.year, _monthStart.month + delta);
      _focusedDay = null;
    });
  }

  Map<DateTime, List<TourismEvent>> _eventsByDay() {
    final map = <DateTime, List<TourismEvent>>{};
    for (final e in widget.events) {
      final d = e.dateTime;
      final key = DateTime(d.year, d.month, d.day);
      (map[key] ??= []).add(e);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    }
    return map;
  }

  String _monthYearLabel(DateTime m) =>
      '${formatEventDateWords(DateTime(m.year, m.month, 1)).split(' ').first} ${m.year}';

  String _shortMonth(DateTime m) =>
      formatEventDateWords(DateTime(m.year, m.month, 1)).split(' ').first;

  void _openEvent(TourismEvent e) {
    if (widget.onEventTap != null) {
      widget.onEventTap!(e);
    } else {
      openTourismEventDetail(context, e, accentColor: widget.accentColor);
    }
  }

  @override
  Widget build(BuildContext context) {
    final byDay = _eventsByDay();
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);

    final firstOfMonth = _monthStart;
    final daysInMonth = DateTime(firstOfMonth.year, firstOfMonth.month + 1, 0).day;
    // Monday = 1 … Sunday = 7
    final leading = (firstOfMonth.weekday - 1) % 7;
    final cellCount = ((leading + daysInMonth + 6) ~/ 7) * 7;

    final prev = DateTime(firstOfMonth.year, firstOfMonth.month - 1);
    final next = DateTime(firstOfMonth.year, firstOfMonth.month + 1);

    final focus = _resolveFocus(byDay, todayKey);
    final focusEvents = focus == null
        ? const <TourismEvent>[]
        : (byDay[focus] ?? const <TourismEvent>[]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _MonthNavButton(
              tooltip: _shortMonth(prev),
              icon: Icons.chevron_left_rounded,
              color: widget.accentColor,
              onPressed: () => _shiftMonth(-1),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    _monthYearLabel(firstOfMonth),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _monthSummary(byDay, firstOfMonth),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textGrey.withValues(alpha: 0.95),
                    ),
                  ),
                ],
              ),
            ),
            _MonthNavButton(
              tooltip: _shortMonth(next),
              icon: Icons.chevron_right_rounded,
              color: widget.accentColor,
              onPressed: () => _shiftMonth(1),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < _weekdayLabels.length; i++)
              Expanded(
                child: Text(
                  _weekdayLabels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: i >= 5
                        ? widget.accentColor.withValues(alpha: 0.85)
                        : Colors.grey.shade600,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var row = 0; row < cellCount ~/ 7; row++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: _buildCell(
                    cellIndex: row * 7 + col,
                    leading: leading,
                    daysInMonth: daysInMonth,
                    monthStart: firstOfMonth,
                    byDay: byDay,
                    todayKey: todayKey,
                    focus: focus,
                  ),
                ),
            ],
          ),
        if (focus != null && focusEvents.isNotEmpty) ...[
          const SizedBox(height: 14),
          _DayAgenda(
            day: focus,
            events: focusEvents,
            accentColor: widget.accentColor,
            onEventTap: _openEvent,
          ),
        ],
      ],
    );
  }

  DateTime? _resolveFocus(
    Map<DateTime, List<TourismEvent>> byDay,
    DateTime todayKey,
  ) {
    final stored = _focusedDay;
    if (stored != null &&
        stored.year == _monthStart.year &&
        stored.month == _monthStart.month) {
      return stored;
    }
    if (todayKey.year == _monthStart.year &&
        todayKey.month == _monthStart.month &&
        (byDay[todayKey]?.isNotEmpty ?? false)) {
      return todayKey;
    }
    DateTime? first;
    for (final day in byDay.keys) {
      if (day.year != _monthStart.year || day.month != _monthStart.month) {
        continue;
      }
      if (first == null || day.isBefore(first)) first = day;
    }
    return first;
  }

  String _monthSummary(
    Map<DateTime, List<TourismEvent>> byDay,
    DateTime month,
  ) {
    var count = 0;
    for (final entry in byDay.entries) {
      if (entry.key.year == month.year && entry.key.month == month.month) {
        count += entry.value.length;
      }
    }
    if (count == 0) return 'No events this month';
    if (count == 1) return '1 event this month';
    return '$count events this month';
  }

  Widget _buildCell({
    required int cellIndex,
    required int leading,
    required int daysInMonth,
    required DateTime monthStart,
    required Map<DateTime, List<TourismEvent>> byDay,
    required DateTime todayKey,
    required DateTime? focus,
  }) {
    final dayNum = cellIndex - leading + 1;
    final inMonth = dayNum >= 1 && dayNum <= daysInMonth;
    if (!inMonth) {
      return const SizedBox(height: 78);
    }

    final day = DateTime(monthStart.year, monthStart.month, dayNum);
    final dayEvents = byDay[day] ?? const <TourismEvent>[];
    final hasEvents = dayEvents.isNotEmpty;
    final isToday = day == todayKey;
    final isFocused = focus == day;
    final accent = widget.accentColor;

    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: isFocused
            ? accent.withValues(alpha: 0.12)
            : hasEvents
                ? AppColors.listTilePeach.withValues(alpha: 0.7)
                : const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: hasEvents
              ? () {
                  setState(() => _focusedDay = day);
                  if (widget.onDayTap != null) {
                    widget.onDayTap!(day, dayEvents);
                  }
                }
              : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isFocused
                    ? accent.withValues(alpha: 0.55)
                    : isToday
                        ? accent.withValues(alpha: 0.35)
                        : Colors.transparent,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: isToday
                      ? BoxDecoration(color: accent, shape: BoxShape.circle)
                      : null,
                  child: Text(
                    '$dayNum',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isToday
                          ? Colors.white
                          : hasEvents
                              ? accent
                              : AppColors.textDark,
                    ),
                  ),
                ),
                if (hasEvents) ...[
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: isFocused ? 0.18 : 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      dayEvents.first.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        color: accent.withValues(alpha: 0.95),
                      ),
                    ),
                  ),
                  if (dayEvents.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '+${dayEvents.length - 1}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthNavButton extends StatelessWidget {
  const _MonthNavButton({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.1),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, color: color, size: 22),
          ),
        ),
      ),
    );
  }
}

class _DayAgenda extends StatelessWidget {
  const _DayAgenda({
    required this.day,
    required this.events,
    required this.accentColor,
    required this.onEventTap,
  });

  final DateTime day;
  final List<TourismEvent> events;
  final Color accentColor;
  final void Function(TourismEvent event) onEventTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.listTilePeach.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            formatEventDateWords(day),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          for (final e in events)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onEventTap(e),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.title,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textDark,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  formatEventTime12(e.dateTime),
                                  if (e.venue.trim().isNotEmpty) e.venue.trim(),
                                  if (e.municipality.trim().isNotEmpty)
                                    e.municipality.trim(),
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textGrey.withValues(
                                    alpha: 0.95,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: accentColor,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Opens full-screen event details (image, description, date, time).
void openTourismEventDetail(
  BuildContext context,
  TourismEvent e, {
  Color accentColor = AppColors.primary,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TourismEventDetailPage(
        event: e,
        accentColor: accentColor,
        onEdit: onEdit,
        onDelete: onDelete,
      ),
    ),
  );
}

/// @deprecated Use [openTourismEventDetail] for full-screen view.
void showTourismEventDetailSheet(
  BuildContext context,
  TourismEvent e, {
  Color accentColor = AppColors.primary,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
}) {
  openTourismEventDetail(
    context,
    e,
    accentColor: accentColor,
    onEdit: onEdit,
    onDelete: onDelete,
  );
}

/// Full-screen event detail (user + admin) — cream body, banner, pill tag.
class TourismEventDetailPage extends StatelessWidget {
  const TourismEventDetailPage({
    super.key,
    required this.event,
    this.accentColor = AppColors.primary,
    this.onEdit,
    this.onDelete,
  });

  final TourismEvent event;
  final Color accentColor;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final e = event;
    final topPad = MediaQuery.paddingOf(context).top;
    final bannerHeight = MediaQuery.sizeOf(context).height * 0.34;

    final detailRows = <_EventDetailRowData>[
      _EventDetailRowData(
        icon: Icons.calendar_today_outlined,
        label: 'Date',
        value: formatEventDateWords(e.dateTime),
      ),
      _EventDetailRowData(
        icon: Icons.access_time_rounded,
        label: 'Time',
        value: formatEventTime12(e.dateTime),
      ),
      if (e.municipality.isNotEmpty)
        _EventDetailRowData(
          icon: Icons.business_outlined,
          label: 'Municipality',
          value: e.municipality,
        ),
      if (e.venue.isNotEmpty)
        _EventDetailRowData(
          icon: Icons.location_on_outlined,
          label: 'Venue',
          value: e.venue,
        ),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: bannerHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _EventDetailBanner(
                  imagePath: e.imagePath,
                  accentColor: accentColor,
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 72,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.18),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: topPad + 8,
                  left: 12,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.38),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.maybePop(context),
                      customBorder: const CircleBorder(),
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                      height: 1.2,
                      letterSpacing: -0.4,
                    ),
                  ),
                  if (e.eventType.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _EventCategoryTag(label: e.eventType, color: accentColor),
                  ],
                  const SizedBox(height: 18),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.listTilePeach.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.14),
                      ),
                    ),
                    child: Text(
                      e.description.isNotEmpty
                          ? e.description
                          : 'No description provided.',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.55,
                        color: e.description.isNotEmpty
                            ? AppColors.textDark
                            : AppColors.textGrey,
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  TourismPlanUi.sectionTitleBar(title: 'Event details'),
                  const SizedBox(height: 10),
                  Container(
                    decoration: TourismPlanUi.planCardDecoration(),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      children: [
                        for (var i = 0; i < detailRows.length; i++) ...[
                          if (i > 0)
                            Divider(
                              height: 1,
                              thickness: 1,
                              indent: 72,
                              endIndent: 18,
                              color: Colors.black.withValues(alpha: 0.06),
                            ),
                          _EventDetailRow(
                            icon: detailRows[i].icon,
                            label: detailRows[i].label,
                            value: detailRows[i].value,
                            accentColor: accentColor,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (onEdit != null || onDelete != null) ...[
                    const SizedBox(height: 28),
                    if (onEdit != null)
                      TourismGradientButton(
                        label: 'Edit event',
                        icon: Icons.edit_outlined,
                        onPressed: () {
                          Navigator.pop(context);
                          onEdit!();
                        },
                      ),
                    if (onEdit != null && onDelete != null)
                      const SizedBox(height: 12),
                    if (onDelete != null)
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            onDelete!();
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade400,
                            side: BorderSide(color: Colors.red.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.delete_outline, size: 20),
                          label: const Text('Delete event'),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventDetailRowData {
  const _EventDetailRowData({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

/// Full-bleed banner with cover fit when possible.
class _EventDetailBanner extends StatelessWidget {
  const _EventDetailBanner({
    required this.imagePath,
    required this.accentColor,
  });

  final String imagePath;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final fallback = _eventImagePlaceholder(accentColor);
    if (imagePath.trim().isEmpty) {
      return fallback;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return OverflowBox(
          alignment: Alignment.center,
          minWidth: constraints.maxWidth,
          maxWidth: constraints.maxWidth,
          minHeight: constraints.maxHeight,
          maxHeight: constraints.maxHeight,
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: Alignment.center,
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: buildMunicipalityImage(imagePath, fallback: fallback),
            ),
          ),
        );
      },
    );
  }
}

/// Orange-outlined pill for event category (e.g. Sports).
class _EventCategoryTag extends StatelessWidget {
  const _EventCategoryTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

Widget _eventImagePlaceholder(Color accentColor) {
  return Container(
    color: accentColor.withValues(alpha: 0.08),
    alignment: Alignment.center,
    child: Icon(Icons.event, color: accentColor, size: 56),
  );
}

class _EventDetailRow extends StatelessWidget {
  const _EventDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.listTilePeach,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: accentColor.withValues(alpha: 0.12),
              ),
            ),
            child: Icon(icon, size: 22, color: accentColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textGrey.withValues(alpha: 0.95),
                    letterSpacing: 0.2,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// White card list of event titles ("Events (n)" + rows with orange chevrons).
class TourismEventTitlesList extends StatelessWidget {
  const TourismEventTitlesList({
    super.key,
    required this.events,
    this.accentColor = AppColors.primary,
    this.onEventTap,
  });

  final List<TourismEvent> events;
  final Color accentColor;
  final void Function(TourismEvent event)? onEventTap;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
        decoration: TourismPlanUi.planCardDecoration(),
        child: Text(
          'No events yet. Posted events will be listed here.',
          style: TextStyle(
            fontSize: 13.5,
            height: 1.4,
            color: AppColors.textGrey.withValues(alpha: 0.95),
          ),
        ),
      );
    }

    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return Column(
      children: [
        for (var i = 0; i < events.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onEventTap == null ? null : () => onEventTap!(events[i]),
              child: Ink(
                decoration: TourismPlanUi.planCardDecoration(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.listTilePeach,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${events[i].dateTime.day}',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                height: 1,
                                color: accentColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              monthNames[events[i].dateTime.month - 1],
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: accentColor.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              events[i].title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textDark,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                formatEventTime12(events[i].dateTime),
                                if (events[i].venue.trim().isNotEmpty)
                                  events[i].venue.trim(),
                                if (events[i].municipality.trim().isNotEmpty)
                                  events[i].municipality.trim(),
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textGrey.withValues(
                                  alpha: 0.95,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 24,
                        color: accentColor,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
