import 'package:atmos_trs_system/utils/checkin_visitor_count.dart';

/// Shared visit metrics so LGU and super-admin (provincial / governor) dashboards
/// use the same language:
/// - **check-ins** = QR scan sessions (one row per scan)
/// - **visitors** = party headcount (`partySize` / `visitorCount` summed)
class VisitStats {
  const VisitStats({
    required this.checkIns,
    required this.visitors,
  });

  /// Number of QR check-in documents / sessions.
  final int checkIns;

  /// Sum of party sizes across those check-ins.
  final int visitors;

  factory VisitStats.fromCheckIns(Iterable<Map<String, dynamic>> rows) {
    final list = rows is List<Map<String, dynamic>>
        ? rows
        : rows.toList(growable: false);
    return VisitStats(
      checkIns: list.length,
      visitors: sumCheckInVisitors(list),
    );
  }

  /// e.g. "42 visitors · 18 check-ins"
  String get summaryLine {
    if (checkIns == 0 && visitors == 0) return '0 check-ins';
    if (visitors == checkIns) {
      return '$checkIns check-in${checkIns == 1 ? '' : 's'}';
    }
    return '$visitors visitors · $checkIns check-in${checkIns == 1 ? '' : 's'}';
  }

  /// Compact KPI subtitle when the big number is visitors.
  String get asVisitorsSubtitle {
    if (checkIns == 0) return 'No QR check-ins yet';
    if (visitors == checkIns) {
      return '$checkIns QR check-in${checkIns == 1 ? '' : 's'}';
    }
    return 'From $checkIns QR check-in${checkIns == 1 ? '' : 's'}';
  }

  /// Compact KPI subtitle when the big number is check-in sessions.
  String get asCheckInsSubtitle {
    if (checkIns == 0) return 'No visitors yet';
    if (visitors == checkIns) return '1 visitor per check-in';
    return '$visitors visitors (party headcount)';
  }
}
