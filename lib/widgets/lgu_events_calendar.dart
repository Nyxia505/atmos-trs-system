import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/lgu_event_service.dart';
import 'package:flutter/material.dart';

/// Redesigned month / week grid for LGU events — matches the reference design.
///
/// - Grid with subtle border lines.
/// - Date numbers at the top-left of each cell.
/// - Orange event chips with dot indicator.
/// - "+N" interactive overflow chip → popup listing extra events.
/// - Month ↔ Week view toggle.
/// - Today / Month / Week controls + legend in header.
class LguEventsCalendar extends StatefulWidget {
  const LguEventsCalendar({
    super.key,
    required this.month,
    required this.events,
    required this.accent,
    required this.onMonthChanged,
    required this.onDaySelected,
    this.selectedDay,
    this.viewMode = 'month',
    this.onViewModeChanged,
    this.onEventTap,
  });

  final DateTime month;
  final List<Map<String, dynamic>> events;
  final Color accent;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDaySelected;

  /// 'month' or 'week'
  final String viewMode;
  final ValueChanged<String>? onViewModeChanged;

  /// Called when a chip event is tapped directly (opens details).
  final ValueChanged<Map<String, dynamic>>? onEventTap;

  static const _weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  static const _monthNames = [
    'January', 'February', 'March', 'April',
    'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December',
  ];

  @override
  State<LguEventsCalendar> createState() => _LguEventsCalendarState();
}

class _LguEventsCalendarState extends State<LguEventsCalendar> {
  // ── helpers ────────────────────────────────────────────────────────────────

  DateTime get _todayDate {
    final now = LguEventService.manilaNow();
    return DateTime(now.year, now.month, now.day);
  }

  bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Unique events that appear at least once during the displayed month.
  int _monthEventCount() {
    final daysInMonth =
        DateTime(widget.month.year, widget.month.month + 1, 0).day;
    final seen = <String>{};
    var count = 0;
    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(widget.month.year, widget.month.month, d);
      for (final ev in widget.events) {
        if (LguEventService.occursOnDay(ev, date)) {
          final id = ev['id']?.toString() ?? ev.hashCode.toString();
          if (seen.add(id)) count++;
        }
      }
    }
    return count;
  }

  // ── build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 640;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 16, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(isNarrow),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
          _buildWeekdayRow(),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
          widget.viewMode == 'week' ? _buildWeekGrid() : _buildMonthGrid(),
        ],
      ),
    );
  }

  // ── header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(bool isNarrow) {
    final label =
        '${LguEventsCalendar._monthNames[widget.month.month - 1]} ${widget.month.year}';
    final count = _monthEventCount();
    final countLabel = count == 0
        ? 'No events this month'
        : '$count event${count == 1 ? '' : 's'} this month';

    final prevBtn = _navBtn(
      Icons.chevron_left_rounded,
      () => widget.onMonthChanged(
          DateTime(widget.month.year, widget.month.month - 1)),
    );
    final nextBtn = _navBtn(
      Icons.chevron_right_rounded,
      () => widget.onMonthChanged(
          DateTime(widget.month.year, widget.month.month + 1)),
    );

    final monthInfo = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF1F2937),
                fontWeight: FontWeight.w800,
                fontSize: 17)),
        Text(countLabel,
            style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 11.5,
                fontWeight: FontWeight.w600)),
      ],
    );

    void goToday() {
      final now = LguEventService.manilaNow();
      final day = DateTime(now.year, now.month, now.day);
      widget.onMonthChanged(DateTime(now.year, now.month));
      widget.onDaySelected(day);
    }

    final controls = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _viewBtn('Today', false, onTap: goToday),
        const SizedBox(width: 5),
        _viewBtn('Month', widget.viewMode == 'month',
            onTap: () => widget.onViewModeChanged?.call('month')),
        const SizedBox(width: 5),
        _viewBtn('Week', widget.viewMode == 'week',
            onTap: () => widget.onViewModeChanged?.call('week')),
      ],
    );

    if (isNarrow) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                prevBtn,
                const SizedBox(width: 8),
                Expanded(child: monthInfo),
                nextBtn,
              ],
            ),
            const SizedBox(height: 8),
            controls,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      child: Row(
        children: [
          prevBtn,
          const SizedBox(width: 8),
          monthInfo,
          const SizedBox(width: 8),
          nextBtn,
          const Spacer(),
          controls,
          const SizedBox(width: 14),
          _buildLegend(),
        ],
      ),
    );
  }

  Widget _navBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF374151)),
      ),
    );
  }

  Widget _viewBtn(String label, bool active, {required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: active ? widget.accent : Colors.transparent,
          border: Border.all(
              color: active ? widget.accent : const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFF374151),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    Widget dot({bool outlined = false, bool stacked = false}) {
      if (stacked) {
        return SizedBox(
          width: 14,
          height: 8,
          child: Stack(children: [
            Positioned(
              left: 0,
              child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: widget.accent.withValues(alpha: 0.4),
                      shape: BoxShape.circle)),
            ),
            Positioned(
              right: 0,
              child: Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: widget.accent, shape: BoxShape.circle)),
            ),
          ]),
        );
      }
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: outlined ? null : widget.accent,
          shape: BoxShape.circle,
          border: outlined
              ? Border.all(color: widget.accent, width: 1.5)
              : null,
        ),
      );
    }

    Widget item(Widget d, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            d,
            const SizedBox(width: 4),
            Text(text,
                style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                    fontWeight: FontWeight.w600)),
          ],
        );

    return Wrap(
      spacing: 10,
      children: [
        item(dot(), 'Event'),
        item(dot(stacked: true), 'Multiple events'),
        item(dot(outlined: true), 'Today'),
      ],
    );
  }

  // ── weekday row ─────────────────────────────────────────────────────────────

  Widget _buildWeekdayRow() {
    return Row(
      children: LguEventsCalendar._weekdays
          .map(
            (d) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  d.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  // ── month grid ──────────────────────────────────────────────────────────────

  Widget _buildMonthGrid() {
    final first = DateTime(widget.month.year, widget.month.month, 1);
    final daysInMonth =
        DateTime(widget.month.year, widget.month.month + 1, 0).day;
    final leading = first.weekday % 7; // Sun = 0
    final rows = ((leading + daysInMonth) / 7).ceil();
    final today = _todayDate;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(rows, (row) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (row > 0)
              const Divider(height: 1, thickness: 1, color: Color(0xFFE5E7EB)),
            _MonthRow(
              row: row,
              leading: leading,
              daysInMonth: daysInMonth,
              month: widget.month,
              today: today,
              selected: widget.selectedDay,
              events: widget.events,
              accent: widget.accent,
              onDayTap: widget.onDaySelected,
              onEventTap: widget.onEventTap,
              onOverflowTap: _showOverflowDialog,
            ),
          ],
        );
      }),
    );
  }

  void _showOverflowDialog(
      List<Map<String, dynamic>> events, DateTime date) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          _fmt(date),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: events
                .map(
                  (ev) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                          color: widget.accent, shape: BoxShape.circle),
                    ),
                    title: Text(
                      ev['title']?.toString().trim() ?? 'Event',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    subtitle: Text(
                      LguEventService.displayStatus(ev),
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.unselectedMuted),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      widget.onEventTap?.call(ev);
                    },
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close',
                style: TextStyle(color: widget.accent)),
          ),
        ],
      ),
    );
  }

  // ── week grid ───────────────────────────────────────────────────────────────

  Widget _buildWeekGrid() {
    final ref = widget.selectedDay ??
        DateTime(widget.month.year, widget.month.month, 1);
    final dow = ref.weekday % 7; // Sun = 0
    final sunday = ref.subtract(Duration(days: dow));
    final today = _todayDate;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(7, (i) {
          final date = sunday.add(Duration(days: i));
          final inMonth = date.month == widget.month.month &&
              date.year == widget.month.year;
          final events = widget.events
              .where((e) => LguEventService.occursOnDay(e, date))
              .toList();
          final isToday = _same(date, today);
          final isSelected =
              widget.selectedDay != null && _same(date, widget.selectedDay!);

          return Expanded(
            child: GestureDetector(
              onTap: () => widget.onDaySelected(date),
              child: Container(
                constraints: const BoxConstraints(minHeight: 160),
                decoration: BoxDecoration(
                  color: isSelected
                      ? widget.accent.withValues(alpha: 0.08)
                      : null,
                  border: i < 6
                      ? const Border(
                          right: BorderSide(color: Color(0xFFE5E7EB)))
                      : null,
                ),
                padding: const EdgeInsets.fromLTRB(5, 6, 4, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DateBubble(
                      day: date.day,
                      inMonth: inMonth,
                      isToday: isToday,
                      isSelected: isSelected,
                      accent: widget.accent,
                    ),
                    if (events.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      for (final ev in events)
                        _EventChip(
                          title: ev['title']?.toString().trim() ?? 'Event',
                          accent: widget.accent,
                          fullWidth: true,
                          onTap: () {
                            widget.onDaySelected(date);
                            widget.onEventTap?.call(ev);
                          },
                        ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── utils ───────────────────────────────────────────────────────────────────

  String _fmt(DateTime d) =>
      '${LguEventsCalendar._monthNames[d.month - 1]} ${d.day}, ${d.year}';
}

// ── month row widget (extracted to avoid IntrinsicHeight nesting) ─────────────

class _MonthRow extends StatelessWidget {
  const _MonthRow({
    required this.row,
    required this.leading,
    required this.daysInMonth,
    required this.month,
    required this.today,
    required this.selected,
    required this.events,
    required this.accent,
    required this.onDayTap,
    required this.onEventTap,
    required this.onOverflowTap,
  });

  final int row;
  final int leading;
  final int daysInMonth;
  final DateTime month;
  final DateTime today;
  final DateTime? selected;
  final List<Map<String, dynamic>> events;
  final Color accent;
  final ValueChanged<DateTime> onDayTap;
  final ValueChanged<Map<String, dynamic>>? onEventTap;
  final void Function(List<Map<String, dynamic>>, DateTime) onOverflowTap;

  bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: List.generate(7, (col) {
          final index = row * 7 + col;
          final dayNum = index - leading + 1;
          final inMonth = dayNum >= 1 && dayNum <= daysInMonth;

          // Compute actual date (including prev/next month overflow)
          final DateTime date;
          if (dayNum < 1) {
            final prevLast = DateTime(month.year, month.month, 0).day;
            date = DateTime(month.year, month.month - 1, prevLast + dayNum);
          } else if (dayNum > daysInMonth) {
            date = DateTime(month.year, month.month + 1, dayNum - daysInMonth);
          } else {
            date = DateTime(month.year, month.month, dayNum);
          }

          final isToday = _same(date, today);
          final isSelected = selected != null && _same(date, selected!);
          final hits = inMonth
              ? events
                  .where((e) => LguEventService.occursOnDay(e, date))
                  .toList()
              : <Map<String, dynamic>>[];

          return Expanded(
            child: GestureDetector(
              onTap: inMonth ? () => onDayTap(date) : null,
              child: Container(
                constraints: const BoxConstraints(minHeight: 82),
                decoration: BoxDecoration(
                  color: isSelected
                      ? accent.withValues(alpha: 0.08)
                      : Colors.transparent,
                  border: col < 6
                      ? const Border(
                          right: BorderSide(color: Color(0xFFE5E7EB)))
                      : null,
                ),
                padding: const EdgeInsets.fromLTRB(5, 5, 4, 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DateBubble(
                      day: date.day,
                      inMonth: inMonth,
                      isToday: isToday,
                      isSelected: isSelected,
                      accent: accent,
                    ),
                    if (hits.isNotEmpty && inMonth) ...[
                      const SizedBox(height: 3),
                      ..._chips(hits, date),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  static const _maxVisible = 1;

  List<Widget> _chips(List<Map<String, dynamic>> hits, DateTime date) {
    final shown = hits.take(_maxVisible).toList();
    final more = hits.length - _maxVisible;

    return [
      for (final ev in shown)
        _EventChip(
          title: ev['title']?.toString().trim() ?? 'Event',
          accent: accent,
          onTap: () {
            onDayTap(date);
            onEventTap?.call(ev);
          },
        ),
      if (more > 0)
        _EventChip(
          title: '+$more',
          accent: accent,
          isDot: false,
          onTap: () {
            onDayTap(date);
            onOverflowTap(hits.skip(_maxVisible).toList(), date);
          },
        ),
    ];
  }
}

// ── shared sub-widgets ────────────────────────────────────────────────────────

class _DateBubble extends StatelessWidget {
  const _DateBubble({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.accent,
  });

  final int day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isSelected ? accent : null,
        shape: BoxShape.circle,
        border: isToday && !isSelected
            ? Border.all(color: accent, width: 1.6)
            : null,
      ),
      child: Text(
        '$day',
        style: TextStyle(
          color: !inMonth
              ? const Color(0xFFD1D5DB)
              : isSelected
                  ? Colors.white
                  : isToday
                      ? accent
                      : const Color(0xFF1F2937),
          fontWeight:
              (isToday || isSelected) ? FontWeight.w800 : FontWeight.w500,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _EventChip extends StatelessWidget {
  const _EventChip({
    required this.title,
    required this.accent,
    required this.onTap,
    this.isDot = true,
    this.fullWidth = false,
  });

  final String title;
  final Color accent;
  final VoidCallback onTap;
  final bool isDot;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: fullWidth ? double.infinity : null,
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.fromLTRB(4, 2, 5, 2),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          children: [
            if (isDot) ...[
              Container(
                width: 5,
                height: 5,
                decoration:
                    BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
