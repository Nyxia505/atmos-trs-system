import 'package:shared_preferences/shared_preferences.dart';

/// Persists a scanned LGU (municipality) QR when the user must sign in before check-in.
class PendingLguCheckIn {
  const PendingLguCheckIn({
    required this.municipalityId,
    required this.displayName,
  });

  final String municipalityId;
  final String displayName;
}

class PendingLguCheckInStorage {
  PendingLguCheckInStorage._();

  static const _kMunicipalityId = 'pending_lgu_checkin_municipality_id';
  static const _kDisplayName = 'pending_lgu_checkin_display_name';

  static Future<void> save({
    required String municipalityId,
    required String displayName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMunicipalityId, municipalityId.trim());
    await prefs.setString(_kDisplayName, displayName.trim());
  }

  static Future<PendingLguCheckIn?> peek() async {
    final prefs = await SharedPreferences.getInstance();
    final mid = prefs.getString(_kMunicipalityId)?.trim() ?? '';
    if (mid.isEmpty) return null;
    final name = prefs.getString(_kDisplayName)?.trim() ?? mid;
    return PendingLguCheckIn(municipalityId: mid, displayName: name);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kMunicipalityId);
    await prefs.remove(_kDisplayName);
  }
}
