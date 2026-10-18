import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/lgu_event_service.dart';
import 'package:flutter/material.dart';

/// Month grid for LGU events. Dates that have a post are tappable.
class LguEventsCalendar extends StatelessWidget {
  const LguEventsCalendar({
    super.key,
    required this.month,
    required this.events,
    required this.accent,
    required this.onMonthChanged,
    required this.onDaySelected,
    this.selectedDay,
  });

  final DateTime month;
  final List<Map<String, dynamic>> events;
  final Color accent;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDaySelected;

  static const _weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday % 7;
    final today = LguEventService.manilaNow();
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();
    final posted = events.where((event) {
      for (var day = 1; day <= daysInMonth; day++) {
        if (LguEventService.occursOnDay(event, DateTime(month.year, month.month, day))) {
          return true;
        }
      }
      return false;
    }).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _monthButton(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Previous month',
                onPressed: () => onMonthChanged(DateTime(month.year, month.month - 1, 1)),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      _monthTitle(month),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      posted == 0
                          ? 'No posts this month'
                          : posted == 1
                              ? '1 post this month'
                              : '$posted posts this month',
                      style: TextStyle(
                        color: AppTheme.unselectedMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  final now = LguEventService.manilaNow();
                  final day = DateTime(now.year, now.month, now.day);
                  onMonthChanged(day);
                  onDaySelected(day);
                },
                style: TextButton.styleFrom(
                  foregroundColor: accent,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                child: const Text('Today', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              _monthButton(
                icon: Icons.chevron_right_rounded,
                tooltip: 'Next month',
                onPressed: () => onMonthChanged(DateTime(month.year, month.month + 1, 1)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final label in _weekdays)
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppTheme.unselectedMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var row = 0; row < rows; row++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var col = 0; col < 7; col++)
                  Expanded(
                    child: _dayCell(
                      index: row * 7 + col,
                      leading: leading,
                      daysInMonth: daysInMonth,
                      today: today,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _monthButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFFF8FAFC),
        foregroundColor: AppTheme.textPrimary,
        fixedSize: const Size(36, 36),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon, size: 20),
    );
  }

  Widget _dayCell({
    required int index,
    required int leading,
    required int daysInMonth,
    required DateTime today,
  }) {
    final dayNumber = index - leading + 1;
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox(height: 72);
    }
    final date = DateTime(month.year, month.month, dayNumber);
    final hits = events.where((event) => LguEventService.occursOnDay(event, date)).toList();
    final isToday = today.year == date.year && today.month == date.month && today.day == date.day;
    final hasEvents = hits.isNotEmpty;
    final selected = selectedDay != null &&
        selectedDay!.year == date.year &&
        selectedDay!.month == date.month &&
        selectedDay!.day == date.day;
    final title = hits
        .map((event) => event['title']?.toString().trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    final extra = title.isEmpty ? hits.length : hits.length - 1;
    final numberColor = selected
        ? Colors.white
        : (isToday ? accent : AppTheme.textPrimary);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          hoverColor: accent.withValues(alpha: 0.06),
          onTap: () => onDaySelected(date),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: selected ? accent : (isToday ? accent.withValues(alpha: 0.12) : null),
                    shape: BoxShape.circle,
                    border: isToday && !selected ? Border.all(color: accent, width: 1.6) : null,
                  ),
                  child: Text(
                    '$dayNumber',
                    style: TextStyle(
                      color: numberColor,
                      fontWeight: isToday || hasEvents || selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                if (title.isNotEmpty)
                  Text(
                    extra > 0 ? '$title +$extra' : title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: accent,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  )
                else if (hasEvents)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  )
                else
                  const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _monthTitle(DateTime month) {
    const names = [
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
    return '${names[month.month - 1]} ${month.year}';
  }
}
