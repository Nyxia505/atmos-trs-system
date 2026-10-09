import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'data.dart';
import 'hub_spot_transport_fare_matrix.dart';
import 'hub_spot_transport_fee.dart';
import 'municipality_bus_terminals.dart';
import 'services/auth_role_claims.dart';
import 'services/firestore_gate.dart';
import 'services/public_firestore_read.dart';

const String kHubSpotTransportFeesCollection = 'hub_spot_transport_fees';

final Map<String, HubSpotTransportFee> hubSpotTransportFeesByDocId = {};

bool _isFirestorePermissionDenied(Object error) {
  return error.toString().contains('permission-denied');
}

bool _isFirestoreWebClientAssertion(Object error) {
  final s = error.toString();
  return s.contains('INTERNAL ASSERTION FAILED') ||
      s.contains('Unexpected state');
}

/// Fills [hubSpotTransportFeesByDocId] from the embedded matrix when Firestore is empty or unavailable.
void seedHubSpotTransportFeesFromEmbeddedMatrixIfEmpty() {
  if (hubSpotTransportFeesByDocId.isNotEmpty) return;
  final fees = buildHubSpotTransportFeesFromMatrix();
  hubSpotTransportFeesByDocId.addEntries(
    fees.map((f) => MapEntry(f.id, f)),
  );
}

Future<void> loadHubSpotTransportFeesFromFirestore() async {
  return runFirestore(() async {
  try {
    final snapshot = await fetchPublicFirestoreCollection(
      kHubSpotTransportFeesCollection,
    );
    hubSpotTransportFeesByDocId.clear();
    for (final doc in snapshot.docs) {
      hubSpotTransportFeesByDocId[doc.id] = HubSpotTransportFee.fromFirestore(
        doc.id,
        doc.data(),
      );
    }
    if (hubSpotTransportFeesByDocId.isEmpty) {
      seedHubSpotTransportFeesFromEmbeddedMatrixIfEmpty();
    }
  } catch (e) {
    if (_isFirestorePermissionDenied(e) || _isFirestoreWebClientAssertion(e)) {
      seedHubSpotTransportFeesFromEmbeddedMatrixIfEmpty();
      return;
    }
    rethrow;
  }
  });
}

Future<Map<String, HubSpotTransportFee>> fetchHubSpotTransportFeesByDocIds(
  List<String> docIds,
) async {
  final unique = docIds.toSet().toList();
  if (unique.isEmpty) return {};

  final result = <String, HubSpotTransportFee>{};
  final missing = <String>[];

  for (final id in unique) {
    final cached = hubSpotTransportFeesByDocId[id];
    if (cached != null) {
      result[id] = cached;
    } else {
      missing.add(id);
    }
  }

  if (missing.isEmpty) return result;

  try {
    final col =
        FirebaseFirestore.instance.collection(kHubSpotTransportFeesCollection);
    for (var i = 0; i < missing.length; i += 10) {
      final chunk = missing.skip(i).take(10).toList();
      final snapshot =
          await col.where(FieldPath.documentId, whereIn: chunk).get();
      for (final doc in snapshot.docs) {
        final fee = HubSpotTransportFee.fromFirestore(doc.id, doc.data());
        hubSpotTransportFeesByDocId[doc.id] = fee;
        result[doc.id] = fee;
      }
    }
  } catch (e) {
    if (!_isFirestorePermissionDenied(e)) rethrow;
  }

  return result;
}

/// Saves one hub ↔ spot fare (merge). Updates in-memory cache.
Future<void> saveHubSpotTransportFeeToFirestore(HubSpotTransportFee fee) async {
  await ensurePermanentStaffRoleForCatalogWrite();
  final ref = FirebaseFirestore.instance
      .collection(kHubSpotTransportFeesCollection)
      .doc(fee.id);
  final snap = await ref.get();
  final payload = fee.toFirestoreUpdateMap();
  if (!snap.exists) {
    payload['createdAt'] = FieldValue.serverTimestamp();
  }
  await ref.set(payload, SetOptions(merge: true));
  hubSpotTransportFeesByDocId[fee.id] = fee;
}

Future<void> deleteHubSpotTransportFeeFromFirestore(String docId) async {
  await ensurePermanentStaffRoleForCatalogWrite();
  await FirebaseFirestore.instance
      .collection(kHubSpotTransportFeesCollection)
      .doc(docId)
      .delete();
  hubSpotTransportFeesByDocId.remove(docId);
}

Future<HubSpotTransportFee?> fetchHubSpotTransportFee({
  required String endpointSlug,
  required String touristSpotSlug,
  HubSpotLegDirection direction = HubSpotLegDirection.hubToSpot,
}) async {
  final id = hubSpotTransportFeeDocId(endpointSlug, touristSpotSlug, direction);
  final cached = hubSpotTransportFeesByDocId[id];
  if (cached != null) return cached;

  try {
    final doc = await FirebaseFirestore.instance
        .collection(kHubSpotTransportFeesCollection)
        .doc(id)
        .get();
    if (!doc.exists) return null;
    final fee = HubSpotTransportFee.fromFirestore(doc.id, doc.data()!);
    hubSpotTransportFeesByDocId[id] = fee;
    return fee;
  } catch (e) {
    if (_isFirestorePermissionDenied(e)) return null;
    rethrow;
  }
}

/// Matrix fallback when a Firestore doc is missing.
HubSpotTransportFee? hubSpotFeeFromMatrixForSpot(
  TouristSpot spot,
  HubSpotLegDirection direction,
) {
  final slug = touristSpotProfileStorageSlug(spot.name);
  HubSpotFareMatrixRow? row = matrixRowForSpotSlug(slug);
  if (row == null) {
    for (final r in kHubSpotTransportFareMatrix) {
      if (spot.name.toLowerCase().contains(
            r.touristSpotDisplayName.split(' ').first.toLowerCase(),
          )) {
        row = r;
        break;
      }
    }
  }
  if (row == null) return null;

  Municipality? muni;
  for (final m in municipalities) {
    if (m.name == row.municipalityName || m.shortName == row.municipalityName) {
      muni = m;
      break;
    }
  }
  if (muni == null) return null;
  final hub = defaultBusTerminalFor(muni) ?? transportEndpointFor(muni);
  return hubSpotFeeFromMatrixRow(
    row: row,
    muni: muni,
    hub: hub,
    direction: direction,
    spotDisplayName: spot.name.isNotEmpty ? spot.name : null,
  );
}

Future<int> syncAllHubSpotTransportFeesToFirestore() async {
  final fees = buildHubSpotTransportFeesFromMatrix();
  final col = FirebaseFirestore.instance.collection(
    kHubSpotTransportFeesCollection,
  );

  const batchLimit = 450;
  var uploaded = 0;
  for (var offset = 0; offset < fees.length; offset += batchLimit) {
    final chunk = fees.skip(offset).take(batchLimit).toList();
    final batch = FirebaseFirestore.instance.batch();
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

  hubSpotTransportFeesByDocId
    ..clear()
    ..addEntries(fees.map((f) => MapEntry(f.id, f)));
  return uploaded;
}

Future<int> seedHubSpotTransportFeesViaCloudFunction() async {
  final callable =
      FirebaseFunctions.instance.httpsCallable('seedHubSpotTransportFees');
  final result = await callable.call();
  final data = result.data is Map
      ? Map<String, dynamic>.from(result.data as Map)
      : <String, dynamic>{};
  final uploaded = data['uploaded'];
  if (uploaded is int) return uploaded;
  if (uploaded is num) return uploaded.round();
  return 0;
}
