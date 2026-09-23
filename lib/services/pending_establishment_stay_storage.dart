import 'package:shared_preferences/shared_preferences.dart';

/// Persists a scanned establishment QR when the tourist must sign in first.
class PendingEstablishmentStay {
  const PendingEstablishmentStay({
    required this.establishmentId,
    this.municipalityId,
    this.businessName,
    this.municipality,
    this.partySize = 1,
    this.femaleCount = 0,
    this.maleCount = 0,
    this.filipinoCount = 0,
    this.foreignCount = 0,
  });

  final String establishmentId;
  final String? municipalityId;
  final String? businessName;
  final String? municipality;
  final int partySize;
  final int femaleCount;
  final int maleCount;
  final int filipinoCount;
  final int foreignCount;
}

class PendingEstablishmentStayStorage {
  PendingEstablishmentStayStorage._();

  static const _kEstablishmentId = 'pending_est_stay_establishment_id';
  static const _kMunicipalityId = 'pending_est_stay_municipality_id';
  static const _kBusinessName = 'pending_est_stay_business_name';
  static const _kMunicipality = 'pending_est_stay_municipality';
  static const _kPartySize = 'pending_est_stay_party_size';
  static const _kFemaleCount = 'pending_est_stay_female_count';
  static const _kMaleCount = 'pending_est_stay_male_count';
  static const _kFilipinoCount = 'pending_est_stay_filipino_count';
  static const _kForeignCount = 'pending_est_stay_foreign_count';

  static Future<void> save({
    required String establishmentId,
    String? municipalityId,
    String? businessName,
    String? municipality,
    int? partySize,
    int? femaleCount,
    int? maleCount,
    int? filipinoCount,
    int? foreignCount,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEstablishmentId, establishmentId.trim());
    if (municipalityId != null && municipalityId.trim().isNotEmpty) {
      await prefs.setString(_kMunicipalityId, municipalityId.trim());
    } else {
      await prefs.remove(_kMunicipalityId);
    }
    if (businessName != null && businessName.trim().isNotEmpty) {
      await prefs.setString(_kBusinessName, businessName.trim());
    } else {
      await prefs.remove(_kBusinessName);
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
    if (filipinoCount != null && filipinoCount >= 0) {
      await prefs.setInt(_kFilipinoCount, filipinoCount);
    }
    if (foreignCount != null && foreignCount >= 0) {
      await prefs.setInt(_kForeignCount, foreignCount);
    }
  }

  static Future<void> setPartyDemographics({
    required int partySize,
    required int femaleCount,
    required int maleCount,
    int filipinoCount = 0,
    int foreignCount = 0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final eid = prefs.getString(_kEstablishmentId)?.trim() ?? '';
    if (eid.isEmpty) return;
    await prefs.setInt(_kPartySize, partySize < 1 ? 1 : partySize);
    await prefs.setInt(_kFemaleCount, femaleCount < 0 ? 0 : femaleCount);
    await prefs.setInt(_kMaleCount, maleCount < 0 ? 0 : maleCount);
    await prefs.setInt(_kFilipinoCount, filipinoCount < 0 ? 0 : filipinoCount);
    await prefs.setInt(_kForeignCount, foreignCount < 0 ? 0 : foreignCount);
  }

  static Future<PendingEstablishmentStay?> peek() async {
    final prefs = await SharedPreferences.getInstance();
    final eid = prefs.getString(_kEstablishmentId)?.trim() ?? '';
    if (eid.isEmpty) return null;
    return PendingEstablishmentStay(
      establishmentId: eid,
      municipalityId: prefs.getString(_kMunicipalityId)?.trim(),
      businessName: prefs.getString(_kBusinessName)?.trim(),
      municipality: prefs.getString(_kMunicipality)?.trim(),
      partySize: prefs.getInt(_kPartySize) ?? 1,
      femaleCount: prefs.getInt(_kFemaleCount) ?? 0,
      maleCount: prefs.getInt(_kMaleCount) ?? 0,
      filipinoCount: prefs.getInt(_kFilipinoCount) ?? 0,
      foreignCount: prefs.getInt(_kForeignCount) ?? 0,
    );
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kEstablishmentId);
    await prefs.remove(_kMunicipalityId);
    await prefs.remove(_kBusinessName);
    await prefs.remove(_kMunicipality);
    await prefs.remove(_kPartySize);
    await prefs.remove(_kFemaleCount);
    await prefs.remove(_kMaleCount);
    await prefs.remove(_kFilipinoCount);
    await prefs.remove(_kForeignCount);
  }
}
