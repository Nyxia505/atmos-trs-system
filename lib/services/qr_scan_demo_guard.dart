import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:atmos_trs_system/config/beta_testing_config.dart';
import 'package:atmos_trs_system/config/qr_scan_geofence_config.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Demo-only QR rules for client presentations (debug builds).
class QrScanDemoGuard {
  QrScanDemoGuard._();

  /// True when debug demo flags are on (never in release/profile).
  static bool get isDemoActive =>
      !BetaTestingGuard.isActive &&
      kDebugMode &&
      (kQrScanBypassGeofenceInDebug ||
          (kDemoOnlyMunicipalityId != null &&
              kDemoOnlyMunicipalityId!.trim().isNotEmpty));

  /// Blocks check-in for municipalities other than [kDemoOnlyMunicipalityId].
  static String? municipalityRestrictionMessage(String municipalityId) {
    if (BetaTestingGuard.isActive) return null;
    if (!kDebugMode) return null;
    final only = kDemoOnlyMunicipalityId?.trim();
    if (only == null || only.isEmpty) return null;

    final actual = normalizeMunicipalityId(municipalityId);
    final allowed = normalizeMunicipalityId(only);
    if (actual.isEmpty || allowed.isEmpty) return null;
    if (actual == allowed) return null;

    return 'Demo mode (testing only): QR check-in is limited to Oroquieta City '
        'for this presentation. Use an Oroquieta spot or LGU QR code.';
  }
}
