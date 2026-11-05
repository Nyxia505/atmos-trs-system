import 'package:flutter/material.dart';

import '../../data.dart';
import '../../theme/tourism_app_theme.dart';
import '../../utils/trip_planner_analytics.dart';

const _orange = Color(0xFFFF7900);
const _fill = Color(0xFFFFE2C7);
const _ink = Color(0xFF1F2937);

final _firstDate = DateTime(2020, 1, 1);

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

int get _lastYear {
  final y = _today().year + 1;
  return y < 2027 ? 2027 : y;
}

DateTime _clampDay(DateTime day) {
  var d = DateTime(day.year, day.month, day.day);
  final last = _today();
  if (d.isBefore(_firstDate)) d = _firstDate;
  if (d.isAfter(last)) d = last;
  return d;
}

ThemeData _pickerTheme(BuildContext context) {
  return Theme.of(context).copyWith(
    colorScheme: const ColorScheme.light(
      primary: _orange,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: _ink,
    ),
    datePickerTheme: DatePickerThemeData(
      rangeSelectionBackgroundColor: _fill,
      dayBackgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return _orange;
        return null;
      }),
      todayForegroundColor: const WidgetStatePropertyAll(_orange),
    ),
  );
}

/// Opens the picker that matches [grain] (date, week, month, or year).
Future<TripTrendWindow?> pickTripAnalyticsPeriod({
  required BuildContext context,
  required TripTrendGrain grain,
  required TripTrendWindow current,
}) {
  final initial = current.contains(_today()) ? _today() : current.start;
  return switch (grain) {
    TripTrendGrain.daily => pickTripAnalyticsDay(
        context: context,
        initial: initial,
      ),
    TripTrendGrain.weekly => pickTripAnalyticsWeek(
        context: context,
        initial: initial,
      ),
    TripTrendGrain.monthly => pickTripAnalyticsMonth(
        context: context,
        initial: initial,
      ),
    TripTrendGrain.yearly => pickTripAnalyticsYear(
        context: context,
        initial: initial,
      ),
  };
}

Future<TripTrendWindow?> pickTripAnalyticsDay({
  required BuildContext context,
  required DateTime initial,
}) async {
  final picked = await showDatePicker(
    context: context,
    initialDate: _clampDay(initial),
    firstDate: _firstDate,
    lastDate: _today(),
    helpText: 'Select a date',
    builder: (context, child) => Theme(
      data: _pickerTheme(context),
      child: child ?? const SizedBox.shrink(),
    ),
  );
  if (picked == null) return null;
  return TripTrendWindow.day(picked);
}

Future<TripTrendWindow?> pickTripAnalyticsWeek({
  required BuildContext context,
  required DateTime initial,
}) {
  return showDialog<TripTrendWindow>(
    context: context,
    builder: (ctx) => _WeekPickerDialog(initial: initial),
  );
}

Future<TripTrendWindow?> pickTripAnalyticsMonth({
  required BuildContext context,
  required DateTime initial,
}) {
  return showDialog<TripTrendWindow>(
    context: context,
    builder: (ctx) => _MonthPickerDialog(initial: initial),
  );
}

Future<TripTrendWindow?> pickTripAnalyticsYear({
  required BuildContext context,
  required DateTime initial,
}) {
  return showDialog<TripTrendWindow>(
    context: context,
    builder: (ctx) => _YearPickerDialog(initial: initial),
  );
}

class _WeekPickerDialog extends StatefulWidget {
  const _WeekPickerDialog({required this.initial});

  final DateTime initial;

  @override
  State<_WeekPickerDialog> createState() => _WeekPickerDialogState();
}

class _WeekPickerDialogState extends State<_WeekPickerDialog> {
  late DateTime _month;
  late DateTime _monday;

  static const _dow = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    _monday = mondayOnOrBefore(widget.initial);
    _month = DateTime(_monday.year, _monday.month, 1);
  }

  DateTime get _sunday => _monday.add(const Duration(days: 6));

  bool _inSelectedWeek(DateTime day) {
    return !day.isBefore(_monday) && !day.isAfter(_sunday);
  }

  void _shiftMonth(int delta) {
    final next = DateTime(_month.year, _month.month + delta, 1);
    final last = DateTime(_lastYear, 12, 1);
    if (next.isBefore(DateTime(_firstDate.year, _firstDate.month, 1))) return;
    if (next.isAfter(last)) return;
    setState(() => _month = next);
  }

  @override
  Widget build(BuildContext context) {
    final gridStart = mondayOnOrBefore(_month);
    final preview = TripTrendWindow.weekOf(_monday);

    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        'Select a week',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous month',
                  onPressed: () => _shiftMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    '${_monthLong[_month.month - 1]} ${_month.year}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: _ink,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next month',
                  onPressed: () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final name in _dow)
                  Expanded(
                    child: Text(
                      name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            for (var week = 0; week < 6; week++)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: _weekDayCell(
                          gridStart.add(Duration(days: week * 7 + i)),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4EB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _fill),
              ),
              child: Text(
                '${preview.label} · 7 days',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: _ink,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, preview),
          style: FilledButton.styleFrom(
            backgroundColor: OptacaAdminTheme.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _weekDayCell(DateTime day) {
    final inMonth = day.month == _month.month;
    final selected = _inSelectedWeek(day);
    final isStart = day == _monday;
    final isEnd = day == _sunday;
    final isToday = day == _today();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? _fill : Colors.transparent,
        borderRadius: BorderRadius.horizontal(
          left: isStart ? const Radius.circular(16) : Radius.zero,
          right: isEnd ? const Radius.circular(16) : Radius.zero,
        ),
        child: InkWell(
          onTap: () => setState(() => _monday = mondayOnOrBefore(day)),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isStart || isEnd ? _orange : null,
              shape: BoxShape.circle,
              border: isToday && !isStart && !isEnd
                  ? Border.all(color: _orange)
                  : null,
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: isStart || isEnd
                    ? Colors.white
                    : inMonth
                        ? _ink
                        : AppColors.textGrey,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthPickerDialog extends StatefulWidget {
  const _MonthPickerDialog({required this.initial});

  final DateTime initial;

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    _year = widget.initial.year.clamp(_firstDate.year, _lastYear);
    _month = widget.initial.month;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        'Select a month',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Previous year',
                  onPressed: _year <= _firstDate.year
                      ? null
                      : () => setState(() => _year--),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    '$_year',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: _ink,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next year',
                  onPressed: _year >= _lastYear
                      ? null
                      : () => setState(() => _year++),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.1,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var m = 1; m <= 12; m++)
                  ChoiceChip(
                    label: Text(_monthLong[m - 1]),
                    selected: _month == m,
                    selectedColor: _fill,
                    labelStyle: TextStyle(
                      color: _ink,
                      fontWeight:
                          _month == m ? FontWeight.w800 : FontWeight.w600,
                    ),
                    side: BorderSide(
                      color: _month == m
                          ? OptacaAdminTheme.primary
                          : OptacaAdminTheme.border,
                    ),
                    onSelected: (_) => setState(() => _month = m),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            TripTrendWindow.daily(_year, _month),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: OptacaAdminTheme.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _YearPickerDialog extends StatefulWidget {
  const _YearPickerDialog({required this.initial});

  final DateTime initial;

  @override
  State<_YearPickerDialog> createState() => _YearPickerDialogState();
}

class _YearPickerDialogState extends State<_YearPickerDialog> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.initial.year.clamp(_firstDate.year, _lastYear);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text(
        'Select a year',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
      ),
      content: SizedBox(
        width: 320,
        child: GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.1,
          children: [
            for (var y = _firstDate.year; y <= _lastYear; y++)
              ChoiceChip(
                label: Text('$y'),
                selected: _year == y,
                selectedColor: _fill,
                labelStyle: TextStyle(
                  color: _ink,
                  fontWeight: _year == y ? FontWeight.w800 : FontWeight.w600,
                ),
                side: BorderSide(
                  color: _year == y
                      ? OptacaAdminTheme.primary
                      : OptacaAdminTheme.border,
                ),
                onSelected: (_) => setState(() => _year = y),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            TripTrendWindow.monthly(_year),
          ),
          style: FilledButton.styleFrom(
            backgroundColor: OptacaAdminTheme.primary,
            foregroundColor: Colors.white,
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

const _monthLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
