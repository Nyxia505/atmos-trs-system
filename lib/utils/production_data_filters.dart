import 'package:atmos_trs_system/utils/checkin_dedupe.dart';

/// Filters seeded / demo records so beta dashboards show only real user activity.
class ProductionDataFilters {
  ProductionDataFilters._();

  static bool isDummyCheckIn(Map<String, dynamic> row) {
    final uid =
        row['userId']?.toString().trim() ??
        row['user_id']?.toString().trim() ??
        row['tourist_id']?.toString().trim() ??
        '';
    if (uid.startsWith('dummy_tourist_')) return true;
    final email =
        row['touristEmail']?.toString().trim() ??
        row['email']?.toString().trim() ??
        '';
    if (email.contains('@dummy-tourist.test')) return true;
    final name = row['touristName']?.toString().toLowerCase() ?? '';
    if (name.contains('dummy tourist')) return true;
    if (row['source']?.toString() == 'dummy_seed') return true;
    return false;
  }

  static bool isDummyTourist(Map<String, dynamic> row) {
    if (row['accountDeleted'] == true) return true;
    final status = row['status']?.toString().trim().toLowerCase() ?? '';
    if (status == 'deleted' || status == 'removed') return true;
    final uid =
        row['firebaseUid']?.toString().trim() ??
        row['id']?.toString().trim() ??
        '';
    if (uid.startsWith('dummy_tourist_')) return true;
    final email = row['email']?.toString().trim().toLowerCase() ?? '';
    if (email.contains('@dummy-tourist.test')) return true;
    if (row['source']?.toString() == 'dummy_seed') return true;
    return false;
  }

  static List<Map<String, dynamic>> realCheckIns(
    List<Map<String, dynamic>> rows, {
    bool collapseRedundant = true,
  }) {
    final real = rows.where((r) => !isDummyCheckIn(r)).toList(growable: false);
    if (!collapseRedundant) return real;
    return CheckInDedupe.oneVisitPerUserSpotDay(real);
  }

  static List<Map<String, dynamic>> realTourists(
    List<Map<String, dynamic>> rows,
  ) {
    return rows
        .where((t) => !isDummyTourist(t))
        .toList(growable: true);
  }
}
