/// Proximity rules for QR check-in (anti-abuse: photo/print of a code used far from the site).
///
/// Printed posters at the real location still work: your phone GPS must be near the spot
/// coordinates stored in Firestore (not near the printer's home).
///
// =============================================================================
// DEMO ONLY — revert before release (client presentation / office testing)
// -----------------------------------------------------------------------------
// ENABLE (presentation demo — phones/tablets, any build mode):
//   kQrScanPresentationDemoEnabled = true;
//   kQrScanBypassGeofenceInDebug = true;
//   kDemoOnlyMunicipalityId = 'oroquieta';
//   → Oroquieta spot/LGU QRs work without being on site (office demo).
//
// REVERT (production — must scan on site with GPS):
//   kQrScanPresentationDemoEnabled = false;
//   kQrScanBypassGeofenceInDebug = false;
//   kDemoOnlyMunicipalityId = null;
// =============================================================================

/// Master switch for client presentation demos (physical devices included).
const bool kQrScanPresentationDemoEnabled = true;

/// Skip GPS proximity while [kQrScanPresentationDemoEnabled] is true.
const bool kQrScanBypassGeofenceInDebug = true;

/// When non-null and presentation demo is on, only this municipality may check in.
const String? kDemoOnlyMunicipalityId = 'oroquieta';

/// Target distance shown to users ("within about 5 meters").
const double kQrScanSpotMaxDistanceMeters = 5.0;

/// Extra allowance for GPS inaccuracy so on-site scans are not rejected (meters).
const double kQrScanSpotGpsAccuracyBufferMeters = 12.0;

/// If reported GPS accuracy is worse than this, ask the user to wait for a better fix.
const double kQrScanRejectIfAccuracyWorseThanMeters = 80.0;

/// Max distance between coordinates embedded in the QR URL and Firestore spot coords.
/// Blocks re-printed codes that were generated for a different anchor.
const double kQrScanQrVsFirestoreMaxMismatchMeters = 40.0;

/// Max distance when the LGU QR does not embed coordinates and we only have the
/// municipality center (approximate). Still blocks someone scanning from another town.
const double kQrScanLguCenterMaxDistanceMeters = 2500.0;

/// Max distance when the LGU QR includes explicit anchor coordinates
/// (`ATMOS-TRS-LGU:id:lat:lng`), e.g. printed at the municipal hall desk.
const double kQrScanLguAnchoredMaxDistanceMeters = 75.0;
