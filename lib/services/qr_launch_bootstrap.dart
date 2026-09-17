import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import 'package:atmos_trs_system/config/beta_testing_config.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/utils/qr_launch_query.dart';
import 'package:atmos_trs_system/utils/spot_qr_helper.dart';

/// Applies pending LGU/spot check-in from a QR that opened the web app in the browser.
class QrLaunchBootstrap {
  QrLaunchBootstrap._();

  static bool appliedFromLaunchUrl = false;

  static Future<void> applyPendingFromLaunchUrl() async {
    if (!kIsWeb) return;

    final raw = launchUrlStringForQrParsing();
    if (raw.isEmpty) return;

    final lgu = parseLguQrPayload(raw);
    if (lgu != null) {
      if (!BetaTestingGuard.bypassValidation &&
          lgu.municipalityId.trim().toLowerCase() != 'oroquieta') {
        await PendingSpotCheckInStorage.clear();
        await PendingLguCheckInStorage.clear();
        return;
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
      );
      appliedFromLaunchUrl = true;
      debugPrint(
        '[QR launch] pending LGU check-in: ${lgu.municipalityId} ($displayName)',
      );
      return;
    }

    final spot = parseSpotCheckInPayload(raw);
    if (spot != null && spot.spotId.isNotEmpty) {
      final scannedMid = (spot.municipalityId ?? '').trim().isNotEmpty
          ? (spot.municipalityId ?? '').trim()
          : 'oroquieta';
      if (!BetaTestingGuard.bypassValidation &&
          scannedMid.toLowerCase() != 'oroquieta') {
        await PendingSpotCheckInStorage.clear();
        await PendingLguCheckInStorage.clear();
        return;
      }
      final mid = scannedMid;
      await PendingLguCheckInStorage.clear();
      await PendingSpotCheckInStorage.save(
        municipalityId: mid,
        spotId: spot.spotId,
        spotName: null,
        municipality: null,
      );
      appliedFromLaunchUrl = true;
      debugPrint(
        '[QR launch] pending spot check-in: ${spot.spotId} '
        'municipality=$mid',
      );
      return;
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
      debugPrint('[QR launch] pending spot check-in (spot_id only): $spotIdOnly');
    }
  }
}
