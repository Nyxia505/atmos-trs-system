import 'package:flutter/material.dart';

import '../data.dart';
import '../event_datetime_format.dart';
import '../event_schedule.dart';

/// One Date field that opens a range calendar, plus a shared time.
class EventDateSchedulePicker extends StatelessWidget {
  const EventDateSchedulePicker({
    super.key,
    required this.timeSource,
    required this.rangeStart,
    required this.rangeEnd,
    required this.onTimeChanged,
    required this.onRangeChanged,
  });

  final DateTime timeSource;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final ValueChanged<DateTime> onTimeChanged;
  final void Function(DateTime start, DateTime end) onRangeChanged;

  Future<void> _pickTime(BuildContext context) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(timeSource),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (t == null) return;
    onTimeChanged(
      DateTime(
        timeSource.year,
        timeSource.month,
        timeSource.day,
        t.hour,
        t.minute,
      ),
    );
  }

  Future<void> _openRangeCalendar(BuildContext context) async {
    final picked = await showDialog<DateTimeRange>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => _EventRangeCalendarDialog(
        initialStart: eventCalendarDay(rangeStart),
        initialEnd: eventCalendarDay(rangeEnd),
      ),
    );
    if (picked == null) return;
    onRangeChanged(
      eventCalendarDay(picked.start),
      eventCalendarDay(picked.end),
    );
  }

  @override
  Widget build(BuildContext context) {
    final start = eventCalendarDay(rangeStart);
    final end = eventCalendarDay(rangeEnd);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DateField(
          label: 'Date',
          value: formatEventDateRangeField(start, end),
          icon: Icons.calendar_today,
          onTap: () => _openRangeCalendar(context),
        ),
        const SizedBox(height: 16),
        _DateField(
          label: 'Time',
          value: formatEventTime12(timeSource),
          icon: Icons.schedule,
          onTap: () => _pickTime(context),
        ),
        const SizedBox(height: 8),
        Text(
          inclusiveCalendarDayCount(start, end) == 1
              ? 'One-day event · ${formatEventTime12(timeSource)}'
              : '${formatEventDateRangeCompact(start, end)} · ${formatEventTime12(timeSource)}',
          style: const TextStyle(fontSize: 13, color: AppColors.textGrey),
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: Icon(icon, size: 18),
          ),
          child: Text(value, style: const TextStyle(fontSize: 15)),
        ),
      ),
    );
  }
}

class _EventRangeCalendarDialog extends StatefulWidget {
  const _EventRangeCalendarDialog({
    required this.initialStart,
    required this.initialEnd,
  });

  final DateTime initialStart;
  final DateTime initialEnd;

  @override
  State<_EventRangeCalendarDialog> createState() =>
      _EventRangeCalendarDialogState();
}

class _EventRangeCalendarDialogState extends State<_EventRangeCalendarDialog> {
  static const _weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  DateTime? _start;
  DateTime? _end;
  late DateTime _month;
  bool _pickingEnd = false;

  @override
  void initState() {
    super.initState();
    _start = eventCalendarDay(widget.initialStart);
    _end = eventCalendarDay(widget.initialEnd);
    _month = DateTime(_start!.year, _start!.month);
  }

  DateTimeRange? get _appliedRange {
    if (_start == null) return null;
    final end = _end ?? _start!;
    if (end.isBefore(_start!)) {
      return DateTimeRange(start: end, end: _start!);
    }
    return DateTimeRange(start: _start!, end: end);
  }

  void _onDayTap(DateTime day) {
    final tapped = eventCalendarDay(day);
    setState(() {
      if (_start == null || (_start != null && _end != null && !_pickingEnd)) {
        _start = tapped;
        _end = null;
        _pickingEnd = true;
        return;
      }
      if (tapped.isBefore(_start!)) {
        _end = _start;
        _start = tapped;
      } else {
        _end = tapped;
      }
      _pickingEnd = false;
    });
  }

  void _clear() {
    setState(() {
      _start = null;
      _end = null;
      _pickingEnd = false;
    });
  }

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  String _monthYearLabel(DateTime m) =>
      '${formatEventDateWords(DateTime(m.year, m.month, 1)).split(' ').first} ${m.year}';

  String _shortMonth(DateTime m) =>
      formatEventDateWords(DateTime(m.year, m.month, 1)).split(' ').first;

  @override
  Widget build(BuildContext context) {
    final range = _appliedRange;
    final previewStart = range?.start ?? _start;
    final previewEnd = range?.end ?? _end ?? _start;
    final days = previewStart == null || previewEnd == null
        ? 0
        : inclusiveCalendarDayCount(previewStart, previewEnd);
    final prev = DateTime(_month.year, _month.month - 1);
    final next = DateTime(_month.year, _month.month + 1);
    final first = DateTime(_month.year, _month.month);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leading = (first.weekday - 1) % 7;
    final cellCount = ((leading + daysInMonth + 6) ~/ 7) * 7;
    final today = eventCalendarDay(DateTime.now());
    const accent = AppColors.primary;

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _PortalMonthNav(
                      tooltip: _shortMonth(prev),
                      icon: Icons.chevron_left_rounded,
                      onPressed: () => _shiftMonth(-1),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            _monthYearLabel(_month),
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
                            _end == null && _start != null
                                ? 'Tap an end date, or Apply for one day'
                                : 'Tap a start date, then an end date',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textGrey.withValues(alpha: 0.95),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _PortalMonthNav(
                      tooltip: _shortMonth(next),
                      icon: Icons.chevron_right_rounded,
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
                                ? accent.withValues(alpha: 0.85)
                                : Colors.grey.shade600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                for (var row = 0; row < cellCount ~/ 7; row++)
                  Row(
                    children: [
                      for (var col = 0; col < 7; col++)
                        Expanded(
                          child: _PortalDayCell(
                            cellIndex: row * 7 + col,
                            leading: leading,
                            daysInMonth: daysInMonth,
                            monthStart: first,
                            today: today,
                            start: _start,
                            end: _end ?? _start,
                            onTap: _onDayTap,
                          ),
                        ),
                    ],
                  ),
                if (previewStart != null && previewEnd != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    decoration: BoxDecoration(
                      color: AppColors.listTilePeach.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Selected Event Dates',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textGrey,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatEventDateRangeCompact(
                            previewStart,
                            previewEnd,
                          ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          days == 1
                              ? '1 day selected'
                              : '$days days selected',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    TextButton(
                      onPressed:
                          _start == null && _end == null ? null : _clear,
                      child: const Text('Clear'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: range == null
                          ? null
                          : () => Navigator.pop(context, range),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PortalMonthNav extends StatelessWidget {
  const _PortalMonthNav({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.primary.withValues(alpha: 0.1),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
        ),
      ),
    );
  }
}

class _PortalDayCell extends StatelessWidget {
  const _PortalDayCell({
    required this.cellIndex,
    required this.leading,
    required this.daysInMonth,
    required this.monthStart,
    required this.today,
    required this.start,
    required this.end,
    required this.onTap,
  });

  final int cellIndex;
  final int leading;
  final int daysInMonth;
  final DateTime monthStart;
  final DateTime today;
  final DateTime? start;
  final DateTime? end;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final dayNum = cellIndex - leading + 1;
    if (dayNum < 1 || dayNum > daysInMonth) {
      return const SizedBox(height: 44);
    }
    final day = DateTime(monthStart.year, monthStart.month, dayNum);
    const accent = AppColors.primary;
    final isStart = start != null && day == start;
    final isEnd = end != null && day == end;
    final inMiddle = start != null &&
        end != null &&
        start != end &&
        day.isAfter(start!) &&
        day.isBefore(end!);
    final isEdge = isStart || isEnd;
    final inRange = isEdge || inMiddle;
    final isToday = day == today;

    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: isEdge
            ? accent.withValues(alpha: 0.12)
            : inMiddle
                ? AppColors.listTilePeach.withValues(alpha: 0.85)
                : const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onTap(day),
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isEdge
                    ? accent.withValues(alpha: 0.55)
                    : isToday
                        ? accent.withValues(alpha: 0.35)
                        : Colors.transparent,
              ),
            ),
            alignment: Alignment.center,
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: isEdge
                  ? const BoxDecoration(color: accent, shape: BoxShape.circle)
                  : null,
              child: Text(
                '$dayNum',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isEdge
                      ? Colors.white
                      : inRange
                          ? accent
                          : AppColors.textDark,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
