import 'package:cloud_firestore/cloud_firestore.dart';

/// One directed route between two LGUs ending at a bus terminal or stop.
class TransportationFee {
  final String id;
  final String fromMunicipality;
  final String toMunicipality;
  final String fromMunicipalitySlug;
  final String toMunicipalitySlug;
  final int fare;
  final String endpointType;
  final String endpointName;
  final String routeType;
  final double estimatedDistance;
  final DateTime? createdAt;

  const TransportationFee({
    required this.id,
    required this.fromMunicipality,
    required this.toMunicipality,
    required this.fromMunicipalitySlug,
    required this.toMunicipalitySlug,
    required this.fare,
    required this.endpointType,
    required this.endpointName,
    required this.routeType,
    required this.estimatedDistance,
    this.createdAt,
  });

  factory TransportationFee.fromFirestore(
    String docId,
    Map<String, dynamic> data,
  ) {
    final created = data['createdAt'];
    DateTime? createdAt;
    if (created is Timestamp) {
      createdAt = created.toDate();
    }
    return TransportationFee(
      id: docId,
      fromMunicipality: (data['fromMunicipality'] as String?) ?? '',
      toMunicipality: (data['toMunicipality'] as String?) ?? '',
      fromMunicipalitySlug: (data['fromMunicipalitySlug'] as String?) ?? '',
      toMunicipalitySlug: (data['toMunicipalitySlug'] as String?) ?? '',
      fare: _readInt(data['fare']),
      endpointType: (data['endpointType'] as String?) ?? 'terminal',
      endpointName: (data['endpointName'] as String?) ?? '',
      routeType: (data['routeType'] as String?) ?? 'jeepney',
      estimatedDistance: _readDouble(
        data['estimatedDistance'] ?? data['estimatedDistanceKm'],
      ),
      createdAt: createdAt,
    );
  }

  TransportationFee copyWith({
    String? fromMunicipality,
    String? toMunicipality,
    String? fromMunicipalitySlug,
    String? toMunicipalitySlug,
    int? fare,
    String? endpointType,
    String? endpointName,
    String? routeType,
    double? estimatedDistance,
  }) {
    return TransportationFee(
      id: id,
      fromMunicipality: fromMunicipality ?? this.fromMunicipality,
      toMunicipality: toMunicipality ?? this.toMunicipality,
      fromMunicipalitySlug:
          fromMunicipalitySlug ?? this.fromMunicipalitySlug,
      toMunicipalitySlug: toMunicipalitySlug ?? this.toMunicipalitySlug,
      fare: fare ?? this.fare,
      endpointType: endpointType ?? this.endpointType,
      endpointName: endpointName ?? this.endpointName,
      routeType: routeType ?? this.routeType,
      estimatedDistance: estimatedDistance ?? this.estimatedDistance,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toFirestoreMap() => {
        ...toFirestoreUpdateMap(),
        'createdAt': FieldValue.serverTimestamp(),
      };

  Map<String, dynamic> toFirestoreUpdateMap() => {
        'fromMunicipality': fromMunicipality,
        'toMunicipality': toMunicipality,
        'fromMunicipalitySlug': fromMunicipalitySlug,
        'toMunicipalitySlug': toMunicipalitySlug,
        'fare': fare,
        'currency': 'PHP',
        'endpointType': endpointType,
        'endpointName': endpointName,
        'routeType': routeType,
        'estimatedDistance': estimatedDistance,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static int _readInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
    return 0;
  }

  static double _readDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }
}
