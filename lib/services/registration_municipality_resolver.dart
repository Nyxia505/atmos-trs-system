import 'package:atmos_trs_system/config/beta_testing_config.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Home-LGU ownership for the municipal "Registered tourists" registry.
///
/// Product rule: a tourist belongs to an LGU by **signup address** (city /
/// municipality in Misamis Occidental), not by where they later scan QR.
/// QR check-ins feed visit / DOT analytics only.
class RegistrationMunicipalityResolver {
  RegistrationMunicipalityResolver._();

  /// Home LGU id from signup address. Foreign / non-MisOcc address → null.
  static String? fromHomeAddress({
    String? country,
    String? province,
    String? city,
    String? municipality,
  }) {
    if (BetaTestingGuard.isActive) {
      return BetaTestingGuard.registrationMunicipalityId(null);
    }

    final countryNorm = (country ?? '').trim().toLowerCase();
    if (countryNorm.isNotEmpty &&
        countryNorm != 'philippines' &&
        countryNorm != 'ph' &&
        countryNorm != 'phl') {
      return null;
    }

    for (final raw in [city, municipality]) {
      final mid = getMunicipalityIdFromName(raw);
      if (mid.isNotEmpty && isMisamisOccidentalMunicipalityId(mid)) {
        return mid;
      }
    }

    final prov = (province ?? '').trim().toLowerCase();
    if (prov.isNotEmpty &&
        !prov.contains('misamis occidental') &&
        !prov.contains('misocc')) {
      return null;
    }
    return null;
  }

  /// @Deprecated Use [fromHomeAddress]. Kept for call-site compatibility.
  /// Previously used pending QR / prior destinations — that inflated LGU
  /// "registered" counts with scanners, not residents.
  static Future<String?> resolveForSignup({
    String? priorDestination1,
    String? priorDestination2,
    String? priorDestination3,
    String? country,
    String? province,
    String? city,
    String? municipality,
  }) async {
    return fromHomeAddress(
      country: country,
      province: province,
      city: city,
      municipality: municipality,
    );
  }

  /// True when [tourist] belongs on an LGU **Registered tourists** list.
  ///
  /// Matches by home address (`city` / `municipality`) and/or
  /// `registrationMunicipalityId` written at signup from that address.
  /// Does **not** match QR check-in UIDs.
  static bool touristMatchesMunicipality({
    required Map<String, dynamic> tourist,
    required List<String> queryIds,
    @Deprecated('Ignored — registered tourists are address-based only')
    Set<String>? checkInUserIds,
  }) {
    if (queryIds.isEmpty) return false;

    for (final field in ['city', 'municipality', 'registrationMunicipality']) {
      final fromName = getMunicipalityIdFromName(tourist[field]?.toString());
      if (fromName.isNotEmpty && queryIds.contains(fromName)) return true;
    }

    final regMid = normalizeMunicipalityId(
      tourist['registrationMunicipalityId']?.toString(),
    );
    if (regMid.isNotEmpty && queryIds.contains(regMid)) return true;

    return false;
  }
}
