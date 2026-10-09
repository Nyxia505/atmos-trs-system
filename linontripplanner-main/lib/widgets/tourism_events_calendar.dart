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

  void _handleDayTap(DateTime day, List<TourismEvent> dayEvents) {
    if (dayEvents.isEmpty) return;
    if (widget.onDayTap != null) {
      widget.onDayTap!(day, dayEvents);
      return;
    }
    if (dayEvents.length == 1) {
      _openEvent(dayEvents.first);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                formatEventDateWords(day),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: dayEvents.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final e = dayEvents[index];
                  return ListTile(
                    title: Text(e.title),
                    subtitle: Text(formatEventTime12(e.dateTime)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openEvent(e);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            TextButton(
              onPressed: () => _shiftMonth(-1),
              style: TextButton.styleFrom(
                foregroundColor: widget.accentColor,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text('◀ ${_shortMonth(prev)}'),
            ),
            Expanded(
              child: Text(
                _monthYearLabel(firstOfMonth),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
            ),
            TextButton(
              onPressed: () => _shiftMonth(1),
              style: TextButton.styleFrom(
                foregroundColor: widget.accentColor,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text('${_shortMonth(next)} ▶'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  for (final label in _weekdayLabels)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Colors.grey.shade300),
                            right: label == 'Sun'
                                ? BorderSide.none
                                : BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              for (var row = 0; row < cellCount ~/ 7; row++)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
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
                            isLastCol: col == 6,
                            isLastRow: row == cellCount ~/ 7 - 1,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCell({
    required int cellIndex,
    required int leading,
    required int daysInMonth,
    required DateTime monthStart,
    required Map<DateTime, List<TourismEvent>> byDay,
    required DateTime todayKey,
    required bool isLastCol,
    required bool isLastRow,
  }) {
    final dayNum = cellIndex - leading + 1;
    final inMonth = dayNum >= 1 && dayNum <= daysInMonth;
    if (!inMonth) {
      return Container(
        constraints: const BoxConstraints(minHeight: 84),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          border: Border(
            right: isLastCol ? BorderSide.none : BorderSide(color: Colors.grey.shade300),
            bottom: isLastRow ? BorderSide.none : BorderSide(color: Colors.grey.shade300),
          ),
        ),
      );
    }

    final day = DateTime(monthStart.year, monthStart.month, dayNum);
    final dayEvents = byDay[day] ?? const <TourismEvent>[];
    final hasEvents = dayEvents.isNotEmpty;
    final isToday = day == todayKey;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: hasEvents ? () => _handleDayTap(day, dayEvents) : null,
        child: Container(
          constraints: const BoxConstraints(minHeight: 84),
          padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
          decoration: BoxDecoration(
            border: Border(
              right: isLastCol ? BorderSide.none : BorderSide(color: Colors.grey.shade300),
              bottom: isLastRow ? BorderSide.none : BorderSide(color: Colors.grey.shade300),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: isToday
                    ? BoxDecoration(
                        color: widget.accentColor,
                        shape: BoxShape.circle,
                      )
                    : null,
                child: Text(
                  '$dayNum',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isToday
                        ? Colors.white
                        : hasEvents
                            ? widget.accentColor
                            : AppColors.textDark,
                  ),
                ),
              ),
              if (hasEvents) ...[
                const SizedBox(height: 2),
                for (final e in widget.titleOnly ? dayEvents : dayEvents.take(2))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: InkWell(
                      onTap: () => _openEvent(e),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          e.title,
                          maxLines: widget.titleOnly ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.25,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!widget.titleOnly && dayEvents.length > 2)
                  Text(
                    '+${dayEvents.length - 2} more',
                    style: TextStyle(
                      fontSize: 10,
                      color: widget.accentColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ],
          ),
        ),
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

    return Container(
      decoration: TourismPlanUi.planCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
            child: Text(
              'Events (${events.length})',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
                letterSpacing: -0.2,
              ),
            ),
          ),
          for (var i = 0; i < events.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: 18,
                endIndent: 18,
                color: Colors.black.withValues(alpha: 0.07),
              ),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap:
                    onEventTap == null ? null : () => onEventTap!(events[i]),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          events[i].title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textDark,
                            height: 1.25,
                          ),
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
          ],
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
