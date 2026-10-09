import 'package:atmos_trs_system/services/pending_qr_expiry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists a scanned LGU (municipality) QR when the user must sign in before check-in.
class PendingLguCheckIn {
  const PendingLguCheckIn({
    required this.municipalityId,
    required this.displayName,
    this.partySize = 1,
    this.femaleCount = 0,
    this.maleCount = 0,
    this.filipinoCount = 0,
    this.foreignCount = 0,
    this.anchorLat,
    this.anchorLng,
    this.isDemoQr = false,
  });

  final String municipalityId;
  final String displayName;

  /// Total visitors for this scan (pila kabook). Default 1.
  final int partySize;
  final int femaleCount;
  final int maleCount;
  final int filipinoCount;
  final int foreignCount;

  /// Anchor printed on the LGU QR (`lat`/`lng`), when present.
  final double? anchorLat;
  final double? anchorLng;

  /// Scanned from a dummy QR (LGU Debug data → Demo QR): no on-site GPS.
  final bool isDemoQr;

  bool get hasAnchor =>
      anchorLat != null &&
      anchorLng != null &&
      anchorLat!.abs() > 1e-7 &&
      anchorLng!.abs() > 1e-7;
}

class PendingLguCheckInStorage {
  PendingLguCheckInStorage._();

  static const _kMunicipalityId = 'pending_lgu_checkin_municipality_id';
  static const _kDisplayName = 'pending_lgu_checkin_display_name';
  static const _kPartySize = 'pending_lgu_checkin_party_size';
  static const _kFemaleCount = 'pending_lgu_checkin_female_count';
  static const _kMaleCount = 'pending_lgu_checkin_male_count';
  static const _kFilipinoCount = 'pending_lgu_checkin_filipino_count';
  static const _kForeignCount = 'pending_lgu_checkin_foreign_count';
  static const _kSavedAt = 'pending_lgu_checkin_saved_at';
  static const _kAnchorLat = 'pending_lgu_checkin_anchor_lat';
  static const _kAnchorLng = 'pending_lgu_checkin_anchor_lng';
  static const _kIsDemoQr = 'pending_lgu_checkin_is_demo_qr';

  static Future<void> save({
    required String municipalityId,
    required String displayName,
    int? partySize,
    int? femaleCount,
    int? maleCount,
    double? anchorLat,
    double? anchorLng,
    bool isDemoQr = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await markPendingQrSaved(prefs, _kSavedAt);
    await prefs.setString(_kMunicipalityId, municipalityId.trim());
    await prefs.setString(_kDisplayName, displayName.trim());
    await prefs.setBool(_kIsDemoQr, isDemoQr);
    await prefs.remove(_kFilipinoCount);
    await prefs.remove(_kForeignCount);
    if (anchorLat != null && anchorLng != null) {
      await prefs.setDouble(_kAnchorLat, anchorLat);
      await prefs.setDouble(_kAnchorLng, anchorLng);
    } else {
      await prefs.remove(_kAnchorLat);
      await prefs.remove(_kAnchorLng);
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

  /// Updates party demographics on an existing pending LGU scan (welcome screen).
  static Future<void> setPartyDemographics({
    required int partySize,
    required int femaleCount,
    required int maleCount,
    int filipinoCount = 0,
    int foreignCount = 0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final mid = prefs.getString(_kMunicipalityId)?.trim() ?? '';
    if (mid.isEmpty) return;
    await prefs.setInt(_kPartySize, partySize < 1 ? 1 : partySize);
    await prefs.setInt(_kFemaleCount, femaleCount < 0 ? 0 : femaleCount);
    await prefs.setInt(_kMaleCount, maleCount < 0 ? 0 : maleCount);
    await prefs.setInt(_kFilipinoCount, filipinoCount < 0 ? 0 : filipinoCount);
    await prefs.setInt(_kForeignCount, foreignCount < 0 ? 0 : foreignCount);
  }

  static Future<PendingLguCheckIn?> peek() async {
    final prefs = await SharedPreferences.getInstance();
    final mid = prefs.getString(_kMunicipalityId)?.trim() ?? '';
    if (mid.isEmpty) return null;
    if (await isPendingQrExpired(prefs, _kSavedAt)) {
      await clear();
      return null;
    }
    final name = prefs.getString(_kDisplayName)?.trim() ?? mid;
    final party = prefs.getInt(_kPartySize) ?? 1;
    final females = prefs.getInt(_kFemaleCount) ?? 0;
    final males = prefs.getInt(_kMaleCount) ?? 0;
    final filipinos = prefs.getInt(_kFilipinoCount) ?? 0;
    final foreigners = prefs.getInt(_kForeignCount) ?? 0;
    return PendingLguCheckIn(
      municipalityId: mid,
      displayName: name,
      partySize: party < 1 ? 1 : party,
      femaleCount: females < 0 ? 0 : females,
      maleCount: males < 0 ? 0 : males,
      filipinoCount: filipinos < 0 ? 0 : filipinos,
      foreignCount: foreigners < 0 ? 0 : foreigners,
      anchorLat: prefs.getDouble(_kAnchorLat),
      anchorLng: prefs.getDouble(_kAnchorLng),
      isDemoQr: prefs.getBool(_kIsDemoQr) ?? false,
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kMunicipalityId);
    await prefs.remove(_kDisplayName);
    await prefs.remove(_kPartySize);
    await prefs.remove(_kFemaleCount);
    await prefs.remove(_kMaleCount);
    await prefs.remove(_kFilipinoCount);
    await prefs.remove(_kForeignCount);
    await prefs.remove(_kSavedAt);
    await prefs.remove(_kAnchorLat);
    await prefs.remove(_kAnchorLng);
    await prefs.remove(_kIsDemoQr);
  }
}
