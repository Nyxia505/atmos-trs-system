import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'data.dart';
import 'firestore_loader.dart';
import 'misamis_occidental_fare_matrix.dart';
import 'municipal_road_distances.dart';
import 'municipality_bus_terminals.dart';
import 'services/auth_role_claims.dart';
import 'services/firestore_gate.dart';
import 'services/public_firestore_read.dart';
import 'transportation_fee.dart';

/// Firestore collection for inter-municipality fares (Misamis Occidental matrix).
///
/// ## Schema (one document per directed route)
/// | Field | Type | Purpose |
/// |-------|------|---------|
/// | fromMunicipality | string | Canonical LGU name (matches `municipalities`) |
/// | toMunicipality | string | Destination LGU name |
/// | fromMunicipalitySlug | string | Query/sort key for origin |
/// | toMunicipalitySlug | string | Query/sort key for destination |
/// | fare | int | Official estimated fare (PHP) from provincial matrix |
/// | currency | string | Always `PHP` |
/// | endpointType | string | `terminal` or `stop` at destination |
/// | endpointName | string | Human-readable hub name at destination |
/// | routeType | string | `jeepney`, `bus`, or `provincial` (distance-based) |
/// | estimatedDistance | number | Road km between town centers (fallback: haversine hub-to-hub × 1.25) |
/// | createdAt | timestamp | First upload |
/// | updatedAt | timestamp | Last matrix sync |
///
/// Document id: `{fromSlug}__{toSlug}` — O(1) fare lookup without composite index.
///
/// ## Sample document (`aloran__ozamiz_city`)
/// ```json
/// {
///   "fromMunicipality": "Aloran",
///   "toMunicipality": "Ozamiz City",
///   "fromMunicipalitySlug": "aloran",
///   "toMunicipalitySlug": "ozamiz_city",
///   "fare": 50,
///   "currency": "PHP",
///   "endpointType": "terminal",
///   "endpointName": "Ozamiz bus terminal",
///   "routeType": "jeepney",
///   "estimatedDistance": 28.4,
///   "createdAt": "<server>",
///   "updatedAt": "<server>"
/// }
/// ```
///
/// ## Query examples
/// ```dart
/// // 1) Direct fare lookup (fastest)
/// final doc = await FirebaseFirestore.instance
///     .collection(kTransportationFeesCollection)
///     .doc(transportationFeeDocId('Aloran', 'Ozamiz City'))
///     .get();
///
/// // 2) All routes from one LGU
/// final fromOzamiz = await FirebaseFirestore.instance
///     .collection(kTransportationFeesCollection)
///     .where('fromMunicipalitySlug', isEqualTo: municipalitySlug('Ozamiz City'))
///     .get();
///
/// // 3) Routes into a municipality
/// final toJimenez = await FirebaseFirestore.instance
///     .collection(kTransportationFeesCollection)
///     .where('toMunicipalitySlug', isEqualTo: municipalitySlug('Jimenez'))
///     .get();
///
/// // 4) Only routes ending at bus terminals
/// final terminalsOnly = await FirebaseFirestore.instance
///     .collection(kTransportationFeesCollection)
///     .where('endpointType', isEqualTo: 'terminal')
///     .get();
///
/// // 5) Only routes ending at bus stops
/// final stopsOnly = await FirebaseFirestore.instance
///     .collection(kTransportationFeesCollection)
///     .where('endpointType', isEqualTo: 'stop')
///     .get();
/// ```
const String kTransportationFeesCollection = 'transportation_fees';

/// In-memory cache after [loadTransportationFeesFromFirestore].
final Map<String, TransportationFee> transportationFeesByDocId = {};

String transportationFeeDocId(String fromMunicipality, String toMunicipality) {
  return '${municipalitySlug(fromMunicipality)}__${municipalitySlug(toMunicipality)}';
}

String routeTypeForEstimatedDistanceKm(double km) {
  if (km >= 55) return 'provincial';
  if (km >= 28) return 'bus';
  return 'jeepney';
}

/// Builds all directed fee payloads from the official matrix (excludes same-LGU).
List<TransportationFee> buildTransportationFeesFromFareMatrix() {
  applyDefaultMunicipalityBusTerminals();

  final byMatrixKey = <String, Municipality>{};
  for (final m in municipalities) {
    byMatrixKey[fareMatrixKeyForMunicipalityName(m.name)] = m;
  }

  final fees = <TransportationFee>[];
  for (var fromIdx = 0; fromIdx < kFareMatrixMunicipalityKeys.length; fromIdx++) {
    final fromKey = kFareMatrixMunicipalityKeys[fromIdx];
    final fromMunicipality = byMatrixKey[fromKey];
    if (fromMunicipality == null) continue;
    final fromCanonical = canonicalMunicipalityNameFromMatrixKey(fromKey);
    final fromEndpoint = transportEndpointFor(fromMunicipality);

    for (var toIdx = 0; toIdx < kFareMatrixMunicipalityKeys.length; toIdx++) {
      if (fromIdx == toIdx) continue;

      final toKey = kFareMatrixMunicipalityKeys[toIdx];
      final toMunicipality = byMatrixKey[toKey];
      if (toMunicipality == null) continue;

      final fare = kMisamisOccidentalFareMatrixPhp[fromIdx][toIdx];
      final toCanonical = canonicalMunicipalityNameFromMatrixKey(toKey);
      final toEndpoint = transportEndpointFor(toMunicipality);

      final straightKm = haversineDistanceKm(
        fromEndpoint.latitude,
        fromEndpoint.longitude,
        toEndpoint.latitude,
        toEndpoint.longitude,
      );
      final roadKm = roadDistanceKmBetween(fromCanonical, toCanonical);
      final estimatedKm = roadKm ?? (straightKm * 1.25 * 10).round() / 10;

      fees.add(
        TransportationFee(
          id: transportationFeeDocId(fromCanonical, toCanonical),
          fromMunicipality: fromCanonical,
          toMunicipality: toCanonical,
          fromMunicipalitySlug: municipalitySlug(fromCanonical),
          toMunicipalitySlug: municipalitySlug(toCanonical),
          fare: fare,
          endpointType: toEndpoint.kind,
          endpointName: toEndpoint.name,
          routeType: routeTypeForEstimatedDistanceKm(estimatedKm),
          estimatedDistance: estimatedKm,
        ),
      );
    }
  }
  return fees;
}

/// Uploads all fares via Cloud Function (admin/staff Auth token). Prefer when
/// the `transportation_fees` collection does not exist yet.
Future<int> seedTransportationFeesViaCloudFunction() async {
  final callable =
      FirebaseFunctions.instance.httpsCallable('seedTransportationFees');
  final result = await callable.call();
  final data = result.data is Map
      ? Map<String, dynamic>.from(result.data as Map)
      : <String, dynamic>{};
  final uploaded = data['uploaded'];
  if (uploaded is int) return uploaded;
  if (uploaded is num) return uploaded.round();
  return 0;
}

/// Batch-uploads matrix fares. Uses stable doc ids — safe to re-run for updates.
Future<int> syncAllTransportationFeesToFirestore() async {
  final fees = buildTransportationFeesFromFareMatrix();
  final firestore = FirebaseFirestore.instance;
  final col = firestore.collection(kTransportationFeesCollection);

  const batchLimit = 450;
  var uploaded = 0;

  for (var offset = 0; offset < fees.length; offset += batchLimit) {
    final chunk = fees.skip(offset).take(batchLimit).toList();
    final batch = firestore.batch();
    for (final fee in chunk) {
      batch.set(
        col.doc(fee.id),
        fee.toFirestoreMap(),
        SetOptions(merge: true),
      );
    }
    await batch.commit();
    uploaded += chunk.length;
  }

  transportationFeesByDocId
    ..clear()
    ..addEntries(fees.map((f) => MapEntry(f.id, f)));

  return uploaded;
}

bool _isFirestorePermissionDenied(Object error) {
  return error.toString().contains('permission-denied');
}

bool _isFirestoreWebClientAssertion(Object error) {
  final s = error.toString();
  return s.contains('INTERNAL ASSERTION FAILED') ||
      s.contains('Unexpected state');
}

/// Fills [transportationFeesByDocId] from the provincial matrix when Firestore is empty or unavailable.
void seedTransportationFeesFromEmbeddedMatrixIfEmpty() {
  if (transportationFeesByDocId.isNotEmpty) return;
  final fees = buildTransportationFeesFromFareMatrix();
  transportationFeesByDocId.addEntries(
    fees.map((f) => MapEntry(f.id, f)),
  );
}

Future<void> loadTransportationFeesFromFirestore() async {
  return runFirestore(() async {
  try {
    final snapshot =
        await fetchPublicFirestoreCollection(kTransportationFeesCollection);

    transportationFeesByDocId.clear();
    for (final doc in snapshot.docs) {
      transportationFeesByDocId[doc.id] = TransportationFee.fromFirestore(
        doc.id,
        doc.data(),
      );
    }
    if (transportationFeesByDocId.isEmpty) {
      seedTransportationFeesFromEmbeddedMatrixIfEmpty();
    }
  } catch (e) {
    if (_isFirestorePermissionDenied(e) || _isFirestoreWebClientAssertion(e)) {
      seedTransportationFeesFromEmbeddedMatrixIfEmpty();
      return;
    }
    rethrow;
  }
  });
}

/// Loads only the given doc ids (cache first, then batched Firestore `whereIn`).
Future<Map<String, TransportationFee>> fetchTransportationFeesByDocIds(
  List<String> docIds,
) async {
  final unique = docIds.toSet().toList();
  if (unique.isEmpty) return {};

  final result = <String, TransportationFee>{};
  final missing = <String>[];

  for (final id in unique) {
    final cached = transportationFeesByDocId[id];
    if (cached != null) {
      result[id] = cached;
    } else {
      missing.add(id);
    }
  }

  if (missing.isEmpty) return result;

  try {
    final col = FirebaseFirestore.instance.collection(
      kTransportationFeesCollection,
    );
    for (var i = 0; i < missing.length; i += 10) {
      final chunk = missing.skip(i).take(10).toList();
      final snapshot = await col.where(FieldPath.documentId, whereIn: chunk).get();
      for (final doc in snapshot.docs) {
        final fee = TransportationFee.fromFirestore(doc.id, doc.data());
        transportationFeesByDocId[doc.id] = fee;
        result[doc.id] = fee;
      }
    }
  } catch (e) {
    if (!_isFirestorePermissionDenied(e)) rethrow;
  }

  return result;
}

/// O(1) lookup from cache, then Firestore doc id.
/// Saves one inter-LGU fare (merge). Updates in-memory cache.
Future<void> saveTransportationFeeToFirestore(TransportationFee fee) async {
  await ensurePermanentStaffRoleForCatalogWrite();
  final normalized = fee.copyWith(
    routeType: routeTypeForEstimatedDistanceKm(fee.estimatedDistance),
  );
  final ref = FirebaseFirestore.instance
      .collection(kTransportationFeesCollection)
      .doc(normalized.id);
  final snap = await ref.get();
  final payload = normalized.toFirestoreUpdateMap();
  if (!snap.exists) {
    payload['createdAt'] = FieldValue.serverTimestamp();
  }
  await ref.set(payload, SetOptions(merge: true));
  transportationFeesByDocId[normalized.id] = normalized;
}

Future<void> deleteTransportationFeeFromFirestore(String docId) async {
  await ensurePermanentStaffRoleForCatalogWrite();
  await FirebaseFirestore.instance
      .collection(kTransportationFeesCollection)
      .doc(docId)
      .delete();
  transportationFeesByDocId.remove(docId);
}

Future<TransportationFee?> fetchTransportationFee({
  required String fromMunicipality,
  required String toMunicipality,
}) async {
  final id = transportationFeeDocId(fromMunicipality, toMunicipality);
  final cached = transportationFeesByDocId[id];
  if (cached != null) return cached;

  try {
    final doc = await FirebaseFirestore.instance
        .collection(kTransportationFeesCollection)
        .doc(id)
        .get();
    if (!doc.exists) return null;
    final fee = TransportationFee.fromFirestore(doc.id, doc.data()!);
    transportationFeesByDocId[id] = fee;
    return fee;
  } catch (e) {
    if (_isFirestorePermissionDenied(e)) return null;
    rethrow;
  }
}

/// Matrix fare in PHP (falls back to in-memory build if Firestore empty).
int? estimatedFarePhp(String fromMunicipality, String toMunicipality) {
  final fromKey = fareMatrixKeyForMunicipalityName(fromMunicipality);
  final toKey = fareMatrixKeyForMunicipalityName(toMunicipality);
  return farePhpBetweenMatrixKeys(fromKey, toKey);
}

/// Routes from [fromMunicipality] filtered by destination hub type.
Future<List<TransportationFee>> queryRoutesFromMunicipality({
  required String fromMunicipality,
  String? endpointType,
}) async {
  final slug = municipalitySlug(fromMunicipality);
  Query<Map<String, dynamic>> q = FirebaseFirestore.instance
      .collection(kTransportationFeesCollection)
      .where('fromMunicipalitySlug', isEqualTo: slug);
  if (endpointType != null && endpointType.trim().isNotEmpty) {
    q = q.where('endpointType', isEqualTo: endpointType.trim().toLowerCase());
  }
  final snap = await q.get();
  return snap.docs
      .map((d) => TransportationFee.fromFirestore(d.id, d.data()))
      .toList();
}

/// Routes into [toMunicipality], optionally filtered by hub type.
Future<List<TransportationFee>> queryRoutesToMunicipality({
  required String toMunicipality,
  String? endpointType,
}) async {
  final slug = municipalitySlug(toMunicipality);
  Query<Map<String, dynamic>> q = FirebaseFirestore.instance
      .collection(kTransportationFeesCollection)
      .where('toMunicipalitySlug', isEqualTo: slug);
  if (endpointType != null && endpointType.trim().isNotEmpty) {
    q = q.where('endpointType', isEqualTo: endpointType.trim().toLowerCase());
  }
  final snap = await q.get();
  return snap.docs
      .map((d) => TransportationFee.fromFirestore(d.id, d.data()))
      .toList();
}
