import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:atmos_trs_system/services/establishment_stay_service.dart';
import 'package:atmos_trs_system/utils/establishment_capability.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Fetches confirmed + checked-out establishment stays for DOT/DAE Analytics.
Future<List<Map<String, dynamic>>> fetchConfirmedEstablishmentStays({
  required DateTime startDate,
  required DateTime endDate,
  String? municipalityId,
}) async {
  final start = DateTime(startDate.year, startDate.month, startDate.day);
  final endExclusive = DateTime(endDate.year, endDate.month, endDate.day)
      .add(const Duration(days: 1));

  Query<Map<String, dynamic>> q = FirebaseFirestore.instance
      .collection(EstablishmentStayService.collection)
      .where(
        'status',
        whereIn: [
          EstablishmentStayStatus.confirmed,
          EstablishmentStayStatus.checkedOut,
        ],
      );

  final mid = normalizeMunicipalityId(municipalityId ?? '');
  if (mid.isNotEmpty) {
    q = q.where('municipalityId', isEqualTo: mid);
  }

  final snap = await q.get();
  final out = <Map<String, dynamic>>[];
  for (final doc in snap.docs) {
    final stay = EstablishmentStayRequest.fromDoc(doc);
    final when = stay.checkInAt ?? stay.confirmedAt ?? stay.createdAt;
    if (when == null) continue;
    if (when.isBefore(start) || !when.isBefore(endExclusive)) continue;
    out.add(confirmedStayToReportEvent(stay));
  }
  return out;
}

/// Shape compatible with check-in aggregators / tourist profile joins.
Map<String, dynamic> confirmedStayToReportEvent(EstablishmentStayRequest stay) {
  final when = stay.checkInAt ?? stay.confirmedAt ?? stay.createdAt;
  final category = stay.establishmentCategory;
  return <String, dynamic>{
    'id': stay.id,
    'source': 'establishment_stay',
    'status': stay.status,
    'userId': stay.touristId,
    'touristId': stay.touristId,
    'uid': stay.touristId,
    'municipality': stay.municipality,
    'municipalityId': stay.municipalityId,
    'spot_name': stay.establishmentName,
    'establishmentId': stay.establishmentId,
    'establishmentName': stay.establishmentName,
    'establishmentCategory': category,
    'typeClass': EstablishmentCapability.typeClassFor(category),
    'roomsAvailable': stay.roomsAvailable,
    'partySize': stay.partySize,
    'femaleCount': stay.femaleCount,
    'maleCount': stay.maleCount,
    'filipinoCount': stay.filipinoCount,
    'foreignCount': stay.foreignCount,
    'nightsStayed': stay.nightsStayed,
    'roomsOccupied': stay.roomsOccupied,
    'roomNumbers': stay.roomNumbers,
    'timestamp': when,
    'checkInAt': stay.checkInAt,
    'confirmedAt': stay.confirmedAt,
    'checkedOutAt': stay.checkedOutAt,
    // Snapshot so aggregators don't need a live profile join.
    'touristProfile': <String, dynamic>{
      'sex': stay.touristSex,
      'nationality': stay.touristNationality,
      'country': stay.touristCountry,
      'province': stay.touristProvince,
      'city': stay.touristCity,
      if (stay.touristIsLocal != null) 'isLocal': stay.touristIsLocal,
      'localOrForeign': stay.touristLocalOrForeign,
    },
  };
}

/// Parses check-in / stay event timestamps for DAE / DOT range filters.
DateTime? parseStayEventTimestamp(Map<String, dynamic> event) {
  final raw = event['timestamp'] ??
      event['checkInAt'] ??
      event['confirmedAt'] ??
      event['createdAt'];
  if (raw == null) return null;
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  return DateTime.tryParse(raw.toString());
}
