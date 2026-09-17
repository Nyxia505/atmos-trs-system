import 'package:shared_preferences/shared_preferences.dart';

/// Persists a scanned spot when the user must sign in before check-in.
class PendingSpotCheckIn {
  const PendingSpotCheckIn({
    required this.municipalityId,
    required this.spotId,
    this.spotName,
    this.municipality,
    this.partySize = 1,
    this.femaleCount = 0,
    this.maleCount = 0,
  });

  final String municipalityId;
  final String spotId;
  final String? spotName;
  final String? municipality;

  /// Total visitors for this scan (pila kabook). Default 1.
  final int partySize;
  final int femaleCount;
  final int maleCount;
}

/// Stores pending QR spot context across login / OTP verification.
class PendingSpotCheckInStorage {
  PendingSpotCheckInStorage._();

  static const _kMunicipalityId = 'pending_checkin_municipality_id';
  static const _kSpotId = 'pending_checkin_spot_id';
  static const _kSpotName = 'pending_checkin_spot_name';
  static const _kMunicipality = 'pending_checkin_municipality_display';
  static const _kPartySize = 'pending_checkin_party_size';
  static const _kFemaleCount = 'pending_checkin_female_count';
  static const _kMaleCount = 'pending_checkin_male_count';

  static Future<void> save({
    required String municipalityId,
    required String spotId,
    String? spotName,
    String? municipality,
    int? partySize,
    int? femaleCount,
    int? maleCount,
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
    if (partySize != null && partySize > 0) {
      await prefs.setInt(_kPartySize, partySize);
    }
    if (femaleCount != null && femaleCount >= 0) {
      await prefs.setInt(_kFemaleCount, femaleCount);
    }
    if (maleCount != null && maleCount >= 0) {
      await prefs.setInt(_kMaleCount, maleCount);
    }
  }

  /// Updates party demographics on an existing pending spot scan (welcome screen).
  static Future<void> setPartyDemographics({
    required int partySize,
    required int femaleCount,
    required int maleCount,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final mid = prefs.getString(_kMunicipalityId)?.trim() ?? '';
    final sid = prefs.getString(_kSpotId)?.trim() ?? '';
    if (mid.isEmpty || sid.isEmpty) return;
    await prefs.setInt(_kPartySize, partySize < 1 ? 1 : partySize);
    await prefs.setInt(_kFemaleCount, femaleCount < 0 ? 0 : femaleCount);
    await prefs.setInt(_kMaleCount, maleCount < 0 ? 0 : maleCount);
  }

  /// Returns pending data without removing it.
  static Future<PendingSpotCheckIn?> peek() async {
    final prefs = await SharedPreferences.getInstance();
    final mid = prefs.getString(_kMunicipalityId)?.trim() ?? '';
    final sid = prefs.getString(_kSpotId)?.trim() ?? '';
    if (mid.isEmpty || sid.isEmpty) return null;
    final party = prefs.getInt(_kPartySize) ?? 1;
    final females = prefs.getInt(_kFemaleCount) ?? 0;
    final males = prefs.getInt(_kMaleCount) ?? 0;
    return PendingSpotCheckIn(
      municipalityId: mid,
      spotId: sid,
      spotName: prefs.getString(_kSpotName),
      municipality: prefs.getString(_kMunicipality),
      partySize: party < 1 ? 1 : party,
      femaleCount: females < 0 ? 0 : females,
      maleCount: males < 0 ? 0 : males,
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kMunicipalityId);
    await prefs.remove(_kSpotId);
    await prefs.remove(_kSpotName);
    await prefs.remove(_kMunicipality);
    await prefs.remove(_kPartySize);
    await prefs.remove(_kFemaleCount);
    await prefs.remove(_kMaleCount);
  }
}
