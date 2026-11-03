import 'package:atmos_trs_system/utils/checkin_time.dart';

/// Collapses redundant QR visit rows so LGU / Governor dashboards show real
/// distinct visits (not double-writes or dual-collection mirrors).
class CheckInDedupe {
  CheckInDedupe._();

  /// One row per tourist + spot + local calendar day (keeps newest).
  static List<Map<String, dynamic>> oneVisitPerUserSpotDay(
    List<Map<String, dynamic>> rows, {
    DateTime? Function(Map<String, dynamic>)? parseTime,
  }) {
    if (rows.isEmpty) return const [];
    final parse = parseTime ?? parseTimestamp;
    final sorted = List<Map<String, dynamic>>.from(rows);
    sorted.sort((a, b) {
      final ta = parse(a);
      final tb = parse(b);
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });

    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final row in sorted) {
      final key = _dayKey(row, parse);
      if (key == null) {
        out.add(row);
        continue;
      }
      if (!seen.add(key)) continue;
      out.add(row);
    }
    return out;
  }

  static String? _dayKey(
    Map<String, dynamic> row,
    DateTime? Function(Map<String, dynamic>) parse,
  ) {
    final uid = userId(row);
    final spot = spotId(row);
    if (uid.isEmpty && spot.isEmpty) return null;
    final t = parse(row);
    final day = t == null
        ? 'unknown'
        : '${t.year.toString().padLeft(4, '0')}-'
            '${t.month.toString().padLeft(2, '0')}-'
            '${t.day.toString().padLeft(2, '0')}';
    return '$uid|$spot|$day';
  }

  static String userId(Map<String, dynamic> c) {
    return c['userId']?.toString().trim() ??
        c['tourist_id']?.toString().trim() ??
        c['user_id']?.toString().trim() ??
        '';
  }

  static String spotId(Map<String, dynamic> c) {
    return c['spotId']?.toString().trim() ??
        c['spot_id']?.toString().trim() ??
        c['touristSpotId']?.toString().trim() ??
        c['location_id']?.toString().trim() ??
        '';
  }

  static DateTime? parseTimestamp(Map<String, dynamic> c) {
    return parseCheckInTimestamp(c);
  }
}
