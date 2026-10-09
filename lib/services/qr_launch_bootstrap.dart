import 'package:atmos_trs_system/config/beta_testing_config.dart';
import 'package:atmos_trs_system/config/qr_scan_geofence_config.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/utils/qr_launch_query.dart';
import 'package:atmos_trs_system/utils/spot_qr_helper.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

/// Applies pending LGU/spot check-in from a camera / App Link QR URL.
class QrLaunchBootstrap {
  QrLaunchBootstrap._();

  static bool appliedFromLaunchUrl = false;

  /// Set when the launch URL was a retired establishment stay QR.
  static bool retiredEstablishmentQr = false;

  /// Web cold start: parse [Uri.base] (path query or hash `#/landing?…`).
  static Future<bool> applyPendingFromLaunchUrl() async {
    if (!kIsWeb) return false;
    final raw = launchUrlStringForQrParsing();
    if (raw.isEmpty) return false;
    return applyFromRawUrl(raw);
  }

  /// Native / web: parse any https (or legacy) QR payload and persist pending.
  static Future<bool> applyFromRawUrl(String rawUrl) async {
    final raw = _normalizeIncomingUrl(rawUrl.trim());
    if (raw.isEmpty) return false;
    if (isScreenPreviewQr(raw)) {
      debugPrint('[QR launch] ignored on-screen preview QR');
      return false;
    }
    final isDemoQr = isDemoQrPayload(raw);
    final oroquietaOnly =
        kQrCheckInOroquietaOnly &&
        !BetaTestingGuard.bypassValidation &&
        !isDemoQr;

    if (parseEstablishmentQrPayload(raw) != null) {
      retiredEstablishmentQr = true;
      debugPrint('[QR launch] retired establishment QR ignored');
      return false;
    }

    final lgu = parseLguQrPayload(raw);
    if (lgu != null) {
      if (oroquietaOnly &&
          lgu.municipalityId.trim().toLowerCase() != 'oroquieta') {
        await PendingSpotCheckInStorage.clear();
        await PendingLguCheckInStorage.clear();
        return false;
      }
      var displayName = lgu.municipalityId;
      for (final m in getMisamisOccidentalMunicipalities()) {
        if (m.id == lgu.municipalityId) {
          displayName = m.name;
          break;
        }
      }
      final municipalityId = lgu.municipalityId;
      await PendingSpotCheckInStorage.clear();
      await PendingLguCheckInStorage.save(
        municipalityId: municipalityId,
        displayName: displayName,
        anchorLat: lgu.hasEmbeddedAnchor ? lgu.anchorLat : null,
        anchorLng: lgu.hasEmbeddedAnchor ? lgu.anchorLng : null,
        isDemoQr: isDemoQr,
      );
      appliedFromLaunchUrl = true;
      debugPrint(
        '[QR launch] pending LGU check-in: ${lgu.municipalityId} ($displayName)',
      );
      return true;
    }

    final spot = parseSpotCheckInPayload(raw);
    if (spot != null && spot.spotId.isNotEmpty) {
      final scannedMid = (spot.municipalityId ?? '').trim().isNotEmpty
          ? (spot.municipalityId ?? '').trim()
          : 'oroquieta';
      if (oroquietaOnly && scannedMid.toLowerCase() != 'oroquieta') {
        await PendingSpotCheckInStorage.clear();
        await PendingLguCheckInStorage.clear();
        return false;
      }
      final mid = scannedMid;
      await PendingLguCheckInStorage.clear();
      await PendingSpotCheckInStorage.save(
        municipalityId: mid,
        spotId: spot.spotId,
        spotName: null,
        municipality: null,
        isDemoQr: isDemoQr,
      );
      appliedFromLaunchUrl = true;
      debugPrint(
        '[QR launch] pending spot check-in: ${spot.spotId} municipality=$mid',
      );
      return true;
    }

    final spotIdOnly = extractSpotIdFromCheckInDeepLink(raw);
    if (spotIdOnly != null && spotIdOnly.isNotEmpty) {
      await PendingLguCheckInStorage.clear();
      await PendingSpotCheckInStorage.save(
        municipalityId: 'oroquieta',
        spotId: spotIdOnly,
        spotName: null,
      );
      appliedFromLaunchUrl = true;
      debugPrint(
        '[QR launch] pending spot check-in (spot_id only): $spotIdOnly',
      );
      return true;
    }

    return false;
  }

  /// True when any pending camera-QR check-in is stored.
  static Future<bool> hasPendingCheckIn() async {
    final spot = await PendingSpotCheckInStorage.peek();
    if (spot != null) return true;
    final lgu = await PendingLguCheckInStorage.peek();
    return lgu != null;
  }

  /// Builds a shareable `/checkin?…` URL from current pending storage (for Play referrer).
  static Future<String?> pendingAsCheckInUrl() async {
    final spot = await PendingSpotCheckInStorage.peek();
    if (spot != null) {
      return spot.isDemoQr
          ? demoSpotQrData(
              municipalityId: spot.municipalityId,
              spotId: spot.spotId,
            )
          : spotQrData(spot.municipalityId, spot.spotId);
    }
    final lgu = await PendingLguCheckInStorage.peek();
    if (lgu != null) {
      if (lgu.isDemoQr) {
        return demoLguQrData(municipalityId: lgu.municipalityId);
      }
      return lguQrData(
        lgu.municipalityId,
        anchorLat: lgu.anchorLat,
        anchorLng: lgu.anchorLng,
      );
    }
    return null;
  }

  /// Reconstructs a check-in URL from Play Install Referrer query (`atmos_q=…`).
  static String? checkInUrlFromInstallReferrer(String referrer) {
    final decoded = Uri.splitQueryString(referrer);
    final q = (decoded['atmos_q'] ?? decoded['utm_content'] ?? '').trim();
    if (q.isEmpty) return null;
    // atmos_q is the raw query string: type=spot&spot_id=…
    if (q.contains('://')) return q;
    return Uri.parse(
      kPublicCheckInBaseUrl,
    ).replace(query: q.startsWith('?') ? q.substring(1) : q).toString();
  }

  static String _normalizeIncomingUrl(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return raw;
    if (uri.scheme == 'atmos' &&
        (uri.host == 'checkin' || uri.path.contains('checkin'))) {
      return Uri.https(
        'atmos-trs-system.web.app',
        '/checkin',
        uri.queryParameters.isEmpty ? null : uri.queryParameters,
      ).toString();
    }
    return raw;
  }
}
