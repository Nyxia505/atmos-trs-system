import 'package:shared_preferences/shared_preferences.dart';

/// Persists a scanned LGU (municipality) QR when the user must sign in before check-in.
class PendingLguCheckIn {
  const PendingLguCheckIn({
    required this.municipalityId,
    required this.displayName,
    this.partySize = 1,
    this.femaleCount = 0,
    this.maleCount = 0,
  });

  final String municipalityId;
  final String displayName;

  /// Total visitors for this scan (pila kabook). Default 1.
  final int partySize;
  final int femaleCount;
  final int maleCount;
}

class PendingLguCheckInStorage {
  PendingLguCheckInStorage._();

  static const _kMunicipalityId = 'pending_lgu_checkin_municipality_id';
  static const _kDisplayName = 'pending_lgu_checkin_display_name';
  static const _kPartySize = 'pending_lgu_checkin_party_size';
  static const _kFemaleCount = 'pending_lgu_checkin_female_count';
  static const _kMaleCount = 'pending_lgu_checkin_male_count';

  static Future<void> save({
    required String municipalityId,
    required String displayName,
    int? partySize,
    int? femaleCount,
    int? maleCount,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMunicipalityId, municipalityId.trim());
    await prefs.setString(_kDisplayName, displayName.trim());
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
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final mid = prefs.getString(_kMunicipalityId)?.trim() ?? '';
    if (mid.isEmpty) return;
    await prefs.setInt(_kPartySize, partySize < 1 ? 1 : partySize);
    await prefs.setInt(_kFemaleCount, femaleCount < 0 ? 0 : femaleCount);
    await prefs.setInt(_kMaleCount, maleCount < 0 ? 0 : maleCount);
  }

  static Future<PendingLguCheckIn?> peek() async {
    final prefs = await SharedPreferences.getInstance();
    final mid = prefs.getString(_kMunicipalityId)?.trim() ?? '';
    if (mid.isEmpty) return null;
    final name = prefs.getString(_kDisplayName)?.trim() ?? mid;
    final party = prefs.getInt(_kPartySize) ?? 1;
    final females = prefs.getInt(_kFemaleCount) ?? 0;
    final males = prefs.getInt(_kMaleCount) ?? 0;
    return PendingLguCheckIn(
      municipalityId: mid,
      displayName: name,
      partySize: party < 1 ? 1 : party,
      femaleCount: females < 0 ? 0 : females,
      maleCount: males < 0 ? 0 : males,
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kMunicipalityId);
    await prefs.remove(_kDisplayName);
    await prefs.remove(_kPartySize);
    await prefs.remove(_kFemaleCount);
    await prefs.remove(_kMaleCount);
  }
}
