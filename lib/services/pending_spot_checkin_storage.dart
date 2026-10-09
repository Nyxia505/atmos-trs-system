import 'package:atmos_trs_system/services/pending_qr_expiry.dart';
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
    this.filipinoCount = 0,
    this.foreignCount = 0,
    this.isDemoQr = false,
  });

  final String municipalityId;
  final String spotId;
  final String? spotName;
  final String? municipality;

  /// Total visitors for this scan (pila kabook). Default 1.
  final int partySize;
  final int femaleCount;
  final int maleCount;
  final int filipinoCount;
  final int foreignCount;

  /// Scanned from a dummy QR (LGU Debug data → Demo QR): no on-site GPS.
  final bool isDemoQr;
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
  static const _kFilipinoCount = 'pending_checkin_filipino_count';
  static const _kForeignCount = 'pending_checkin_foreign_count';
  static const _kSavedAt = 'pending_checkin_saved_at';
  static const _kIsDemoQr = 'pending_checkin_is_demo_qr';

  static Future<void> save({
    required String municipalityId,
    required String spotId,
    String? spotName,
    String? municipality,
    int? partySize,
    int? femaleCount,
    int? maleCount,
    bool isDemoQr = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await markPendingQrSaved(prefs, _kSavedAt);
    await prefs.setString(_kMunicipalityId, municipalityId.trim());
    await prefs.setString(_kSpotId, spotId.trim());
    await prefs.setBool(_kIsDemoQr, isDemoQr);
    await prefs.remove(_kFilipinoCount);
    await prefs.remove(_kForeignCount);
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
    int filipinoCount = 0,
    int foreignCount = 0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final mid = prefs.getString(_kMunicipalityId)?.trim() ?? '';
    final sid = prefs.getString(_kSpotId)?.trim() ?? '';
    if (mid.isEmpty || sid.isEmpty) return;
    await prefs.setInt(_kPartySize, partySize < 1 ? 1 : partySize);
    await prefs.setInt(_kFemaleCount, femaleCount < 0 ? 0 : femaleCount);
    await prefs.setInt(_kMaleCount, maleCount < 0 ? 0 : maleCount);
    await prefs.setInt(_kFilipinoCount, filipinoCount < 0 ? 0 : filipinoCount);
    await prefs.setInt(_kForeignCount, foreignCount < 0 ? 0 : foreignCount);
  }

  /// Returns pending data without removing it.
  static Future<PendingSpotCheckIn?> peek() async {
    final prefs = await SharedPreferences.getInstance();
    final mid = prefs.getString(_kMunicipalityId)?.trim() ?? '';
    final sid = prefs.getString(_kSpotId)?.trim() ?? '';
    if (mid.isEmpty || sid.isEmpty) return null;
    if (await isPendingQrExpired(prefs, _kSavedAt)) {
      await clear();
      return null;
    }
    final party = prefs.getInt(_kPartySize) ?? 1;
    final females = prefs.getInt(_kFemaleCount) ?? 0;
    final males = prefs.getInt(_kMaleCount) ?? 0;
    final filipinos = prefs.getInt(_kFilipinoCount) ?? 0;
    final foreigners = prefs.getInt(_kForeignCount) ?? 0;
    return PendingSpotCheckIn(
      municipalityId: mid,
      spotId: sid,
      spotName: prefs.getString(_kSpotName),
      municipality: prefs.getString(_kMunicipality),
      partySize: party < 1 ? 1 : party,
      femaleCount: females < 0 ? 0 : females,
      maleCount: males < 0 ? 0 : males,
      filipinoCount: filipinos < 0 ? 0 : filipinos,
      foreignCount: foreigners < 0 ? 0 : foreigners,
      isDemoQr: prefs.getBool(_kIsDemoQr) ?? false,
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
    await prefs.remove(_kFilipinoCount);
    await prefs.remove(_kForeignCount);
    await prefs.remove(_kSavedAt);
    await prefs.remove(_kIsDemoQr);
  }
}
