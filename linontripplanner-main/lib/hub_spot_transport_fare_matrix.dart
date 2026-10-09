import 'data.dart';
import 'firestore_loader.dart';
import 'hub_spot_transport_fee.dart';
import 'municipality_bus_terminals.dart';

export 'hub_spot_transport_fee.dart' show HubSpotLegDirection;

/// One row: terminal/stop → tourist spot slug with PHP range (min, max).
class HubSpotFareMatrixRow {
  final String municipalityName;
  final String touristSpotSlug;
  final String touristSpotDisplayName;
  final int fareMin;
  final int fareMax;

  const HubSpotFareMatrixRow({
    required this.municipalityName,
    required this.touristSpotSlug,
    required this.touristSpotDisplayName,
    required this.fareMin,
    required this.fareMax,
  });

  int get fareMidpoint => ((fareMin + fareMax) / 2).round();
}

/// Official hub → tourist spot fares (Misamis Occidental).
const List<HubSpotFareMatrixRow> kHubSpotTransportFareMatrix = [
  HubSpotFareMatrixRow(
    municipalityName: 'Aloran',
    touristSpotSlug: 'aloran_viewpoint',
    touristSpotDisplayName: 'Aloran Viewpoint',
    fareMin: 20,
    fareMax: 40,
  ),
  HubSpotFareMatrixRow(
    municipalityName: 'Baliangao',
    touristSpotSlug: 'baliangao_protected_landscape',
    touristSpotDisplayName: 'Baliangao Protected Landscape',
    fareMin: 50,
    fareMax: 80,
  ),
  HubSpotFareMatrixRow(
    municipalityName: 'Calamba',
    touristSpotSlug: 'calamba_green_hills',
    touristSpotDisplayName: 'Calamba Green Hills',
    fareMin: 15,
    fareMax: 30,
  ),
  HubSpotFareMatrixRow(
    municipalityName: 'Clarin',
    touristSpotSlug: 'clarin_lake_duminagat',
    touristSpotDisplayName: 'Clarin Lake Duminagat',
    fareMin: 80,
    fareMax: 150,
  ),
  HubSpotFareMatrixRow(
    municipalityName: 'Jimenez',
    touristSpotSlug: 'jimenez_st_john_the_baptist_church',
    touristSpotDisplayName: "Jimenez St. John the Baptist Church",
    fareMin: 10,
    fareMax: 20,
  ),
  HubSpotFareMatrixRow(
    municipalityName: 'Lopez Jaena',
    touristSpotSlug: 'lopez_jaena_beachfront',
    touristSpotDisplayName: 'Lopez Jaena Beachfront',
    fareMin: 15,
    fareMax: 30,
  ),
  HubSpotFareMatrixRow(
    municipalityName: 'Oroquieta City (Provincial Capital)',
    touristSpotSlug: 'oroquieta_city_boulevard_and_peoples_park',
    touristSpotDisplayName: "Oroquieta City Boulevard and People's Park",
    fareMin: 10,
    fareMax: 20,
  ),
  HubSpotFareMatrixRow(
    municipalityName: 'Ozamiz City',
    touristSpotSlug: 'ozamiz_cotta_fort_wellness_park',
    touristSpotDisplayName: 'Ozamiz Cotta Fort Wellness Park',
    fareMin: 15,
    fareMax: 25,
  ),
  HubSpotFareMatrixRow(
    municipalityName: 'Panaon',
    touristSpotSlug: 'panaon_seaside',
    touristSpotDisplayName: 'Panaon Seaside',
    fareMin: 15,
    fareMax: 35,
  ),
  HubSpotFareMatrixRow(
    municipalityName: 'Plaridel',
    touristSpotSlug: 'plaridel_resort',
    touristSpotDisplayName: 'Plaridel Resort',
    fareMin: 20,
    fareMax: 40,
  ),
  HubSpotFareMatrixRow(
    municipalityName: 'Sapang Dalaga',
    touristSpotSlug: 'sapang_dalaga_floating_cottages',
    touristSpotDisplayName: 'Sapang Dalaga Floating Cottages',
    fareMin: 30,
    fareMax: 60,
  ),
  HubSpotFareMatrixRow(
    municipalityName: 'Sinacaban',
    touristSpotSlug: 'sinacaban_asenso_aquamarine_park',
    touristSpotDisplayName: 'Sinacaban Asenso Aquamarine Park',
    fareMin: 20,
    fareMax: 40,
  ),
  HubSpotFareMatrixRow(
    municipalityName: 'Tangub City',
    touristSpotSlug: 'tangub_asenso_global_gardens',
    touristSpotDisplayName: 'Tangub Asenso Global Gardens',
    fareMin: 30,
    fareMax: 50,
  ),
  HubSpotFareMatrixRow(
    municipalityName: 'Tudela',
    touristSpotSlug: 'tudela_highland_resort_eco_park',
    touristSpotDisplayName: 'Tudela Highland Resort Eco Park',
    fareMin: 40,
    fareMax: 80,
  ),
];

Municipality? _municipalityByName(String name) {
  for (final m in municipalities) {
    if (m.name == name || m.shortName == name) return m;
  }
  return null;
}

String hubSpotTransportFeeDocId(
  String endpointSlug,
  String spotSlug,
  HubSpotLegDirection direction,
) =>
    '${endpointSlug}__${spotSlug}__${direction.firestoreValue}';

HubSpotTransportFee hubSpotFeeFromMatrixRow({
  required HubSpotFareMatrixRow row,
  required Municipality muni,
  required MunicipalityBusTerminal hub,
  required HubSpotLegDirection direction,
  String? spotDisplayName,
}) {
  final endpointSlug = municipalitySlug(hub.name);
  return HubSpotTransportFee(
    id: hubSpotTransportFeeDocId(
      endpointSlug,
      row.touristSpotSlug,
      direction,
    ),
    fromEndpointName: hub.name,
    fromEndpointType: hub.kind,
    municipality: muni.name,
    municipalitySlug: municipalitySlug(muni.name),
    toTouristSpotSlug: row.touristSpotSlug,
    toTouristSpotName: spotDisplayName ?? row.touristSpotDisplayName,
    fareMin: row.fareMin,
    fareMax: row.fareMax,
    fare: row.fareMidpoint,
    routeType: 'tricycle',
    direction: direction,
  );
}

/// Builds Firestore payloads (hub → spot and spot → hub) from the matrix.
List<HubSpotTransportFee> buildHubSpotTransportFeesFromMatrix() {
  final fees = <HubSpotTransportFee>[];
  for (final row in kHubSpotTransportFareMatrix) {
    final muni = _municipalityByName(row.municipalityName);
    if (muni == null) continue;
    final hub = defaultBusTerminalFor(muni) ?? transportEndpointFor(muni);
    for (final direction in HubSpotLegDirection.values) {
      fees.add(
        hubSpotFeeFromMatrixRow(
          row: row,
          muni: muni,
          hub: hub,
          direction: direction,
        ),
      );
    }
  }
  return fees;
}

HubSpotFareMatrixRow? matrixRowForSpotSlug(String spotSlug) {
  for (final row in kHubSpotTransportFareMatrix) {
    if (row.touristSpotSlug == spotSlug) return row;
  }
  return null;
}
