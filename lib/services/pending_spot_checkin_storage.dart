import 'package:shared_preferences/shared_preferences.dart';

/// Persists a scanned spot when the user must sign in before check-in.
class PendingSpotCheckIn {
  const PendingSpotCheckIn({
    required this.municipalityId,
    required this.spotId,
    this.spotName,
    this.municipality,
  });

  final String municipalityId;
  final String spotId;
  final String? spotName;
  final String? municipality;
}

/// Stores pending QR spot context across login / OTP verification.
class PendingSpotCheckInStorage {
  PendingSpotCheckInStorage._();

  static const _kMunicipalityId = 'pending_checkin_municipality_id';
  static const _kSpotId = 'pending_checkin_spot_id';
  static const _kSpotName = 'pending_checkin_spot_name';
  static const _kMunicipality = 'pending_checkin_municipality_display';

  static Future<void> save({
    required String municipalityId,
    required String spotId,
    String? spotName,
    String? municipality,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMunicipalityId, municipalityId.trim());
    await prefs.setString(_kSpotId, spotId.trim());
    if (spotName != null && spotName.trim().isNotEmpty) {
      await prefs.setString(_kSpotName, spotName.trim());
    } else {
      await prefs.remove(_kSpotName);
    }
    if (municipality != null && municipality.trim().isNotEmpty) {
      await prefs.setString(_kMunicipality, municipality.trim());
    } else {
      await prefs.remove(_kMunicipality);
    }
  }

  /// Returns pending data without removing it.
  static Future<PendingSpotCheckIn?> peek() async {
    final prefs = await SharedPreferences.getInstance();
    final mid = prefs.getString(_kMunicipalityId)?.trim() ?? '';
    final sid = prefs.getString(_kSpotId)?.trim() ?? '';
    if (mid.isEmpty || sid.isEmpty) return null;
    return PendingSpotCheckIn(
      municipalityId: mid,
      spotId: sid,
      spotName: prefs.getString(_kSpotName),
      municipality: prefs.getString(_kMunicipality),
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kMunicipalityId);
    await prefs.remove(_kSpotId);
    await prefs.remove(_kSpotName);
    await prefs.remove(_kMunicipality);
  }
}
