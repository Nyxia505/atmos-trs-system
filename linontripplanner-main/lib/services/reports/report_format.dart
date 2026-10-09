import 'report_models.dart';

/// Formatting shared by the Reports page, the preview, and the exporters so a
/// number reads identically on screen and in a downloaded file.

const List<String> _monthNamesShort = [
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

const List<String> _monthNamesLong = [
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

/// `1234567` → `1,234,567`.
String formatCount(num value) {
  final negative = value < 0;
  final digits = value.abs().round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
    buf.write(digits[i]);
  }
  return negative ? '-$buf' : buf.toString();
}

/// `1234.5` → `1,234.5` with [decimals] places.
String formatDecimal(num value, {int decimals = 1}) {
  final fixed = value.toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final whole = formatCount(num.parse(parts[0]).abs());
  final sign = value < 0 ? '-' : '';
  return parts.length > 1 ? '$sign$whole.${parts[1]}' : '$sign$whole';
}

/// `120` → `PHP 120`. Uses the ISO code rather than `₱` so PDF and CSV output
/// stays readable in fonts and locales without the peso glyph.
String formatPeso(num value) => 'PHP ${formatCount(value)}';

/// `120.4` → `PHP 120.40`.
String formatPesoDecimal(num value) => 'PHP ${formatDecimal(value, decimals: 2)}';

/// `4.25` → `4.3`, and `0` → `—` since an unrated spot is not a zero-star spot.
String formatRating(double value) =>
    value <= 0 ? '—' : formatDecimal(value, decimals: 1);

/// `12.5` → `+12.5%`, `null` → `—`.
String formatSignedPercent(double? value) {
  if (value == null) return '—';
  final sign = value > 0 ? '+' : '';
  return '$sign${formatDecimal(value, decimals: 1)}%';
}

/// `0.125` of a whole → `12.5%`.
String formatShare(num part, num total) {
  if (total <= 0) return '0.0%';
  return '${formatDecimal(part / total * 100, decimals: 1)}%';
}

/// `2026-09-09`, used in filenames and machine-readable columns.
String formatIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// `09 Sep 2026`.
String formatReportDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')} ${_monthNamesShort[d.month - 1]} ${d.year}';

/// `09 Sep 2026, 02:15 PM`.
String formatReportDateTime(DateTime d) {
  final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final period = d.hour < 12 ? 'AM' : 'PM';
  return '${formatReportDate(d)}, '
      '${hour12.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')} $period';
}

/// `September 2026`.
String formatMonthYear(int year, int month) =>
    '${_monthNamesLong[month - 1]} $year';

/// `Sep 2026`, for chart axes.
String formatMonthYearShort(int year, int month) =>
    '${_monthNamesShort[month - 1]} $year';

/// `Bontoc, Mt. Province` → `bontoc_mt_province`.
String fileSlug(String raw) => raw
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_+|_+$'), '');

/// `tourist_arrivals_summary_2026-09-09.pdf` for an overall report, or
/// `tourist_arrivals_summary_sagada_2026-09-09.pdf` when scoped to one LGU.
String reportFileName(
  ReportKind kind,
  ReportFormat format,
  DateTime on, {
  String? municipality,
}) {
  final slug = municipality == null ? '' : fileSlug(municipality);
  final scope = slug.isEmpty ? '' : '_$slug';
  return '${kind.fileStem}${scope}_${formatIsoDate(on)}.${format.extension}';
}

/// Minutes → `1 h 25 m`, `45 m`, or `—`.
String formatTravelMinutes(int? minutes) {
  if (minutes == null || minutes <= 0) return '—';
  if (minutes < 60) return '$minutes m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h h' : '$h h $m m';
}

/// Kilometres → `12.4 km`, or `—` when the record carries no distance.
String formatDistanceKm(double? km) =>
    (km == null || km <= 0) ? '—' : '${formatDecimal(km, decimals: 1)} km';

/// `jeepney` → `Jeepney`.
String formatTransportType(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return '—';
  return s[0].toUpperCase() + s.substring(1);
}
