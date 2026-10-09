/// Proximity rules for QR check-in (anti-abuse: photo/print of a code used far from the site).
///
/// For temporary beta testing (any device/location), see [betaTestingMode] in
/// `lib/config/beta_testing_config.dart`.
///
/// Printed posters at the real location still work: your phone GPS must be near the spot
/// coordinates stored in Firestore (not near the printer's home).
///
// =============================================================================
// DEMO ONLY — revert before release (client presentation / office testing)
// -----------------------------------------------------------------------------
// ENABLE (demo — debug build only, e.g. laptop `flutter run -d chrome`):
//   kQrScanBypassGeofenceInDebug = true;
//   kDemoOnlyMunicipalityId = null;  // all LGUs; or 'oroquieta' to limit
//   → Scan works without traveling.
//
// Also prefer betaTestingMode = true in beta_testing_config.dart for full bypass.
//
// REVERT (production — must scan on site with GPS):
//   kQrScanBypassGeofenceInDebug = false;
//   kDemoOnlyMunicipalityId = null;
//   betaTestingMode = false;
//   → Release/profile builds always enforce GPS; bypass flags are ignored when
//     kDebugMode is false (except betaTestingMode which applies when true).
// =============================================================================

/// Skip GPS proximity in **debug** only (office / laptop demo). Ignored in release.
/// DEMO ONLY — set false before production.
const bool kQrScanBypassGeofenceInDebug = false;

/// When non-null and [kDebugMode], only this municipality id may check in via QR.
/// Set to `null` to allow all LGUs during debug.
const String? kDemoOnlyMunicipalityId = null;

/// Pilot rule: only Oroquieta City spot/LGU QR codes may check in.
const bool kQrCheckInOroquietaOnly = false;

/// Dummy QR codes (LGU Debug data → Demo QR) skip the on-site GPS and
/// screen-preview rules so they can be scanned anywhere, on any device.
/// Set false to disable every dummy QR at once.
const bool kDemoQrEnabled = true;

/// Must match the `demo` query value inside a dummy QR.
const String kDemoQrToken = 'ATMOS-DEMO-2026';

/// Added to QR codes shown on a dashboard screen; scanning them is refused
/// (tourists must scan the official printed QR on site).
const String kQrScreenPreviewParam = 'preview';

/// Check-in radius around a tourist spot's Firestore coordinates (meters).
/// Scans farther than this from the spot are refused.
const double kQrScanSpotMaxDistanceMeters = 50.0;

/// "QR near you" radius: when the app opens within this distance of a spot,
/// the tourist gets a nearby notification (meters).
const double kNearbySpotNotifyRadiusMeters = 1000.0;

/// The same spot is not announced again within this window.
const Duration kNearbySpotNotifyCooldown = Duration(hours: 12);

/// Minimum gap between nearby checks (app open / resume).
const Duration kNearbySpotCheckInterval = Duration(minutes: 5);

/// Cached tourist-spot coordinates are refreshed from Firestore after this age.
const Duration kSpotLocationCacheMaxAge = Duration(hours: 6);

/// Extra allowance for GPS inaccuracy so on-site scans are not rejected (meters).
const double kQrScanSpotGpsAccuracyBufferMeters = 12.0;

/// If reported GPS accuracy is worse than this and the fix cannot prove the
/// device is outside the radius, ask the user to wait for a better fix.
const double kQrScanRejectIfAccuracyWorseThanMeters = 80.0;

/// A GPS fix this recent is reused so scans don't wait for GPS. A reused fix
/// that fails the radius check is always re-read fresh before refusing.
const Duration kQrScanPositionReuseWindow = Duration(seconds: 60);

/// Max distance between coordinates embedded in the QR URL and Firestore spot coords.
/// Blocks re-printed codes that were generated for a different anchor.
const double kQrScanQrVsFirestoreMaxMismatchMeters = 40.0;

/// Max distance when the LGU QR does not embed coordinates and we only have the
/// municipality center (approximate). Still blocks someone scanning from another town.
const double kQrScanLguCenterMaxDistanceMeters = 2500.0;

/// Max distance when the LGU QR includes explicit anchor coordinates
/// (`ATMOS-TRS-LGU:id:lat:lng`), e.g. printed at the municipal hall desk.
const double kQrScanLguAnchoredMaxDistanceMeters = 75.0;
