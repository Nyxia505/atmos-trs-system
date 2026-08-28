import 'package:atmos_trs_system/utils/municipality_helper.dart';

// =============================================================================
// BETA TESTING MODE — temporary; disable before production release
// -----------------------------------------------------------------------------
// Set [betaTestingMode] to false to restore:
//   • GPS / geofence validation on QR scans
//   • Municipality restrictions on check-in
//   • Registration routing based on scanned LGU / prior destinations
// =============================================================================

/// Production: GPS/geofence and municipality rules apply on scan.
const bool betaTestingMode = false;

/// Canonical LGU dashboard used during beta testing.
const String kBetaTestingLguMunicipalityId = 'oroquieta';

/// Display name shown in check-in copy and saved to Firestore.
const String kBetaTestingLguDisplayName = 'Oroquieta City';

/// Default spot anchor for beta-routed check-ins (Oroquieta City Plaza).
const String kBetaTestingDefaultSpotId = 'oroquieta_city_plaza';

const String kBetaTestingDefaultSpotName = 'Oroquieta City Plaza';

/// Applies temporary beta overrides for QR validation and LGU dashboard routing.
class BetaTestingGuard {
  BetaTestingGuard._();

  static bool get isActive => betaTestingMode;

  /// Skip GPS, geofence, QR coordinate, and municipality scan restrictions.
  static bool get bypassValidation => betaTestingMode;

  static String get dashboardMunicipalityId => kBetaTestingLguMunicipalityId;

  static String get dashboardMunicipalityName => kBetaTestingLguDisplayName;

  /// Registration field written to `tourists.registrationMunicipalityId`.
  static String? registrationMunicipalityId(String? resolved) {
    final mid = normalizeMunicipalityId(resolved);
    return mid.isEmpty ? null : mid;
  }

  /// Preserves the scanned spot's LGU — no forced routing to a single dashboard.
  static ({
    String municipalityId,
    String municipality,
    String spotId,
    String spotName,
  })
  applyCheckInRouting({
    required String municipalityId,
    required String municipality,
    required String spotId,
    required String spotName,
  }) {
    final mid = normalizeMunicipalityId(municipalityId);
    return (
      municipalityId: mid.isNotEmpty ? mid : municipalityId,
      municipality: municipality,
      spotId: spotId.trim().isNotEmpty ? spotId.trim() : kBetaTestingDefaultSpotId,
      spotName: spotName.trim().isNotEmpty ? spotName.trim() : kBetaTestingDefaultSpotName,
    );
  }
}
