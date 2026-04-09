/// Proximity rules for QR check-in (anti-abuse: remote scanning of a photo of the code).
///
/// Phone GPS is often ±5–20 m accuracy; very small values cause false rejections.
///
/// Debug/testing override:
/// - true  => skip proximity checks in debug builds only.
/// - false => enforce normal geofence checks.
/// Release/profile builds always enforce geofencing.
const bool kQrScanBypassGeofenceInDebug = true;

/// Max distance from a **tourist spot** anchor (exact coordinates from Firestore / QR).
const double kQrScanSpotMaxDistanceMeters = 75.0;

/// Max distance when the LGU QR does not embed coordinates and we only have the
/// municipality center (approximate). Still blocks someone scanning from another town.
const double kQrScanLguCenterMaxDistanceMeters = 2500.0;

/// Max distance when the LGU QR includes explicit anchor coordinates
/// (`ATMOS-TRS-LGU:id:lat:lng`), e.g. printed at the municipal hall desk.
const double kQrScanLguAnchoredMaxDistanceMeters = 75.0;
