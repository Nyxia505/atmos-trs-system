import 'package:atmos_trs_system/config/qr_scan_geofence_config.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Demo-only QR rules for client presentations (office / device demos).
class QrScanDemoGuard {
  QrScanDemoGuard._();

  static bool get _oroquietaOnlyDemo =>
      kQrScanPresentationDemoEnabled &&
      kDemoOnlyMunicipalityId != null &&
      kDemoOnlyMunicipalityId!.trim().isNotEmpty;

  /// True when presentation demo flags are on (shows banner on QR tab).
  static bool get isDemoActive =>
      _oroquietaOnlyDemo &&
      (kQrScanBypassGeofenceInDebug || kQrScanPresentationDemoEnabled);

  /// Skip GPS proximity checks (Oroquieta presentation demos on real devices).
  static bool get shouldBypassGeofence =>
      kQrScanPresentationDemoEnabled && kQrScanBypassGeofenceInDebug;

  /// Blocks check-in for municipalities other than [kDemoOnlyMunicipalityId].
  static String? municipalityRestrictionMessage(String municipalityId) {
    if (!_oroquietaOnlyDemo) return null;
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
