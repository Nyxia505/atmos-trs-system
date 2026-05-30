import 'package:atmos_trs_system/services/pending_lgu_checkin_storage.dart';
import 'package:atmos_trs_system/services/pending_spot_checkin_storage.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Resolves which LGU should see this tourist on the municipal tourism dashboard.
///
/// Priority: pending QR scan (spot/LGU) → prior-destination LGU in Misamis Occidental.
class RegistrationMunicipalityResolver {
  RegistrationMunicipalityResolver._();

  static Future<String?> resolveForSignup({
    String? priorDestination1,
    String? priorDestination2,
    String? priorDestination3,
  }) async {
    final pendingSpot = await PendingSpotCheckInStorage.peek();
    if (pendingSpot != null) {
      final mid = normalizeMunicipalityId(pendingSpot.municipalityId);
      if (mid.isNotEmpty) return mid;
    }

    final pendingLgu = await PendingLguCheckInStorage.peek();
    if (pendingLgu != null) {
      final mid = normalizeMunicipalityId(pendingLgu.municipalityId);
      if (mid.isNotEmpty) return mid;
    }

    for (final dest in [
      priorDestination1,
      priorDestination2,
      priorDestination3,
    ]) {
      if (dest == null || dest.trim().isEmpty) continue;
      final mid = getMunicipalityIdFromName(dest);
      if (isMisamisOccidentalMunicipalityId(mid)) return mid;
    }
    return null;
  }

  /// True when [tourist] row belongs on an LGU dashboard for [queryIds].
  static bool touristMatchesMunicipality({
    required Map<String, dynamic> tourist,
    required List<String> queryIds,
    required Set<String> checkInUserIds,
  }) {
    if (queryIds.isEmpty) return false;

    final uid =
        tourist['firebaseUid']?.toString().trim() ??
        tourist['id']?.toString().trim() ??
        '';
    if (uid.isNotEmpty && checkInUserIds.contains(uid)) return true;

    final regMid = normalizeMunicipalityId(
      tourist['registrationMunicipalityId']?.toString(),
    );
    return regMid.isNotEmpty && queryIds.contains(regMid);
  }
}
