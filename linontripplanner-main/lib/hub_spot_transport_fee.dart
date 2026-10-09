import 'package:cloud_firestore/cloud_firestore.dart';

/// Local leg between a bus hub and a tourist spot.
enum HubSpotLegDirection {
  hubToSpot('hub_to_spot'),
  spotToHub('spot_to_hub');

  final String firestoreValue;
  const HubSpotLegDirection(this.firestoreValue);

  static HubSpotLegDirection fromFirestoreValue(String? raw, String docId) {
    switch (raw?.trim()) {
      case 'spot_to_hub':
        return HubSpotLegDirection.spotToHub;
      case 'hub_to_spot':
        return HubSpotLegDirection.hubToSpot;
    }
    if (docId.endsWith('__spot_to_hub')) return HubSpotLegDirection.spotToHub;
    return HubSpotLegDirection.hubToSpot;
  }
}

/// Fare between a municipality bus terminal/stop and a tourist spot.
class HubSpotTransportFee {
  final String id;
  final String fromEndpointName;
  final String fromEndpointType;
  final String municipality;
  final String municipalitySlug;
  final String toTouristSpotSlug;
  final String toTouristSpotName;
  final int fareMin;
  final int fareMax;
  final int fare;
  final String routeType;
  final HubSpotLegDirection direction;

  const HubSpotTransportFee({
    required this.id,
    required this.fromEndpointName,
    required this.fromEndpointType,
    required this.municipality,
    required this.municipalitySlug,
    required this.toTouristSpotSlug,
    required this.toTouristSpotName,
    required this.fareMin,
    required this.fareMax,
    required this.fare,
    this.routeType = 'tricycle',
    this.direction = HubSpotLegDirection.hubToSpot,
  });

  factory HubSpotTransportFee.fromFirestore(
    String docId,
    Map<String, dynamic> data,
  ) {
    final min = _readInt(data['fareMin']);
    final max = _readInt(data['fareMax']);
    final fare = _readInt(data['fare']);
    return HubSpotTransportFee(
      id: docId,
      fromEndpointName: (data['fromEndpointName'] as String?) ?? '',
      fromEndpointType: (data['fromEndpointType'] as String?) ?? 'terminal',
      municipality: (data['municipality'] as String?) ?? '',
      municipalitySlug: (data['municipalitySlug'] as String?) ?? '',
      toTouristSpotSlug: (data['toTouristSpotSlug'] as String?) ?? '',
      toTouristSpotName: (data['toTouristSpotName'] as String?) ?? '',
      fareMin: min,
      fareMax: max,
      fare: fare > 0 ? fare : ((min + max) / 2).round(),
      routeType: (data['routeType'] as String?) ?? 'tricycle',
      direction: HubSpotLegDirection.fromFirestoreValue(
        data['direction'] as String?,
        docId,
      ),
    );
  }

  HubSpotTransportFee copyWith({
    int? fareMin,
    int? fareMax,
    int? fare,
    String? fromEndpointName,
    String? fromEndpointType,
    String? municipality,
    String? municipalitySlug,
    String? toTouristSpotSlug,
    String? toTouristSpotName,
  }) {
    return HubSpotTransportFee(
      id: id,
      fromEndpointName: fromEndpointName ?? this.fromEndpointName,
      fromEndpointType: fromEndpointType ?? this.fromEndpointType,
      municipality: municipality ?? this.municipality,
      municipalitySlug: municipalitySlug ?? this.municipalitySlug,
      toTouristSpotSlug: toTouristSpotSlug ?? this.toTouristSpotSlug,
      toTouristSpotName: toTouristSpotName ?? this.toTouristSpotName,
      fareMin: fareMin ?? this.fareMin,
      fareMax: fareMax ?? this.fareMax,
      fare: fare ?? this.fare,
      routeType: routeType,
      direction: direction,
    );
  }

  Map<String, dynamic> toFirestoreMap() => {
        ...toFirestoreUpdateMap(),
        'createdAt': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toFirestoreUpdateMap() => {
        'fromEndpointName': fromEndpointName,
        'fromEndpointType': fromEndpointType,
        'municipality': municipality,
        'municipalitySlug': municipalitySlug,
        'toTouristSpotSlug': toTouristSpotSlug,
        'toTouristSpotName': toTouristSpotName,
        'fareMin': fareMin,
        'fareMax': fareMax,
        'fare': fare,
        'currency': 'PHP',
        'routeType': routeType,
        'direction': direction.firestoreValue,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static int _readInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
    return 0;
  }
}
