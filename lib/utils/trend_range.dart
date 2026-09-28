/// Shared time-range bucketing for dashboard trend charts
/// (rolling 7/14 days, calendar week / month / year).
enum TrendRange { days7, days14, thisWeek, thisMonth, thisYear }

extension TrendRangeX on TrendRange {
  String get label => switch (this) {
        TrendRange.days7 => 'Last 7 days',
        TrendRange.days14 => 'Last 14 days',
        TrendRange.thisWeek => 'This week',
        TrendRange.thisMonth => 'This month',
        TrendRange.thisYear => 'This year',
      };

  /// Calendar ranges include future buckets, so they render as bars.
  bool get isCalendar => switch (this) {
        TrendRange.days7 || TrendRange.days14 => false,
        _ => true,
      };

  /// "per day" / "per month" for chart subtitles.
  String get bucketNoun => this == TrendRange.thisYear ? 'month' : 'day';
}

class TrendSeries {
  const TrendSeries({
    required this.values,
    required this.labels,
    required this.tooltips,
  });

  final List<int> values;

  /// Short axis labels (Mon, 1…31, Jan).
  final List<String> labels;

  /// Full bucket names for tooltips / sparse axes (Sep 25, Sep 2026).
  final List<String> tooltips;

  int get total => values.fold(0, (a, b) => a + b);
}

abstract final class TrendBuckets {
  static const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// Counts each non-null [days] entry (optionally weighted) into [range].
  static TrendSeries build(
    Iterable<DateTime?> days,
    TrendRange range, {
    Iterable<int>? weights,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final today = DateTime(clock.year, clock.month, clock.day);

    if (range == TrendRange.thisYear) {
      final counts = List<int>.filled(12, 0);
      _each(days, weights, (d, w) {
        if (d.year == today.year) counts[d.month - 1] += w;
      });
      return TrendSeries(
        values: counts,
        labels: monthNames,
        tooltips: [for (final m in monthNames) '$m ${today.year}'],
      );
    }

    final DateTime start;
    final int len;
    switch (range) {
      case TrendRange.days7:
      case TrendRange.days14:
        len = range == TrendRange.days7 ? 7 : 14;
        start = DateTime(today.year, today.month, today.day - (len - 1));
      case TrendRange.thisWeek:
        len = 7;
        start = DateTime(today.year, today.month, today.day - (today.weekday - 1));
      case TrendRange.thisMonth:
        len = DateTime(today.year, today.month + 1, 0).day;
        start = DateTime(today.year, today.month, 1);
      case TrendRange.thisYear:
        throw StateError('handled above');
    }

    final counts = List<int>.filled(len, 0);
    _each(days, weights, (d, w) {
      final idx = DateTime.utc(d.year, d.month, d.day)
          .difference(DateTime.utc(start.year, start.month, start.day))
          .inDays;
      if (idx >= 0 && idx < len) counts[idx] += w;
    });
    final bucketDays = [
      for (var i = 0; i < len; i++)
        DateTime(start.year, start.month, start.day + i),
    ];
    return TrendSeries(
      values: counts,
      labels: [
        for (final d in bucketDays)
          range == TrendRange.thisMonth
              ? '${d.day}'
              : weekdayNames[d.weekday - 1],
      ],
      tooltips: [
        for (final d in bucketDays) '${monthNames[d.month - 1]} ${d.day}',
      ],
    );
  }

  static void _each(
    Iterable<DateTime?> days,
    Iterable<int>? weights,
    void Function(DateTime day, int weight) add,
  ) {
    final w = weights?.iterator;
    for (final d in days) {
      final weight = (w != null && w.moveNext()) ? w.current : 1;
      if (d != null) add(d, weight);
    }
  }
}
