import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

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
      var displayName = lgu.municipalityId;
      for (final m in getMisamisOccidentalMunicipalities()) {
        if (m.id == lgu.municipalityId) {
          displayName = m.name;
          break;
        }
      }
      await PendingSpotCheckInStorage.clear();
      await PendingLguCheckInStorage.save(
        municipalityId: lgu.municipalityId,
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
      await PendingLguCheckInStorage.clear();
      await PendingSpotCheckInStorage.save(
        municipalityId: spot.municipalityId ?? '',
        spotId: spot.spotId,
        spotName: null,
        municipality: null,
      );
      appliedFromLaunchUrl = true;
      debugPrint(
        '[QR launch] pending spot check-in: ${spot.spotId} '
        'municipality=${spot.municipalityId ?? "(lookup)"}',
      );
      return;
    }

    final spotIdOnly = extractSpotIdFromCheckInDeepLink(raw);
    if (spotIdOnly != null && spotIdOnly.isNotEmpty) {
      await PendingLguCheckInStorage.clear();
      await PendingSpotCheckInStorage.save(
        municipalityId: '',
        spotId: spotIdOnly,
      );
      appliedFromLaunchUrl = true;
      debugPrint('[QR launch] pending spot check-in (spot_id only): $spotIdOnly');
    }
  }
}
