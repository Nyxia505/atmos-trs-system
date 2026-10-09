import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:atmos_trs_system/services/establishment_registration_service.dart';
import 'package:atmos_trs_system/utils/establishment_capability.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Normalized registry status for OPTACA review.
abstract final class EstablishmentRegistryStatus {
  static const pending = 'pending';
  static const active = 'active';
  static const rejected = 'rejected';

  static String normalize(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s.isEmpty || s == 'pending') return pending;
    if (s == 'active' || s == 'approved' || s == 'approve') return active;
    if (s == 'rejected' || s == 'inactive' || s == 'denied') return rejected;
    return s;
  }

  static bool isPending(String? raw) => normalize(raw) == pending;
  static bool isActive(String? raw) => normalize(raw) == active;
  static bool isRejected(String? raw) => normalize(raw) == rejected;
}

class EstablishmentRegistryEntry {
  const EstablishmentRegistryEntry({
    required this.id,
    required this.businessName,
    required this.category,
    required this.ownerName,
    required this.municipality,
    required this.municipalityId,
    required this.status,
    this.email = '',
    this.contactNumber = '',
    this.barangay = '',
    this.yearEstablished,
    this.businessPermitNo = '',
    this.businessPermitUrl = '',
    this.roomCount,
    this.checkInTime = '',
    this.checkOutTime = '',
    this.reviewedAt,
    this.reviewNotes = '',
    this.hostsMice = false,
  });

  final String id;
  final String businessName;
  final String category;
  final String ownerName;
  final String municipality;
  final String municipalityId;
  final String status;
  final String email;
  final String contactNumber;
  final String barangay;
  final int? yearEstablished;
  final String businessPermitNo;
  final String businessPermitUrl;
  final int? roomCount;
  /// Lodging standard check-in clock (`HH:mm`), empty for non-lodging.
  final String checkInTime;
  /// Lodging standard check-out clock (`HH:mm`), empty for non-lodging.
  final String checkOutTime;
  final DateTime? reviewedAt;
  final String reviewNotes;
  /// Hosts MICE events (CUS MICE survey) — field `hostsMice`, category default.
  final bool hostsMice;

  bool get isPending => EstablishmentRegistryStatus.isPending(status);
  bool get isActive => EstablishmentRegistryStatus.isActive(status);
  bool get isRejected => EstablishmentRegistryStatus.isRejected(status);

  factory EstablishmentRegistryEntry.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    int? year;
    final y = d['yearEstablished'];
    if (y is int) {
      year = y;
    } else if (y is num) {
      year = y.toInt();
    } else {
      year = int.tryParse(y?.toString() ?? '');
    }
    int? rooms;
    final r = d['roomCount'];
    if (r is int) {
      rooms = r;
    } else if (r is num) {
      rooms = r.toInt();
    } else {
      rooms = int.tryParse(r?.toString() ?? '');
    }
    DateTime? reviewed;
    final ra = d['reviewedAt'];
    if (ra is Timestamp) reviewed = ra.toDate();
    final category = (d['category'] ?? d['type'] ?? '').toString();
    return EstablishmentRegistryEntry(
      id: doc.id,
      businessName:
          (d['businessName'] ?? d['name'] ?? 'Establishment').toString(),
      category: category,
      hostsMice: EstablishmentCapability.hostsMice(category, d['hostsMice']),
      ownerName: (d['ownerName'] ?? '').toString(),
      municipality: (d['municipality'] ?? '').toString(),
      municipalityId: (d['municipalityId'] ?? '').toString(),
      status: EstablishmentRegistryStatus.normalize(d['status']?.toString()),
      email: (d['email'] ?? '').toString(),
      contactNumber: (d['contactNumber'] ?? '').toString(),
      barangay: (d['barangay'] ?? '').toString(),
      yearEstablished: year,
      businessPermitNo: (d['businessPermitNo'] ?? '').toString(),
      businessPermitUrl: (d['businessPermitUrl'] ?? '').toString(),
      roomCount: rooms,
      checkInTime: (d['checkInTime'] ?? '').toString().trim(),
      checkOutTime: (d['checkOutTime'] ?? '').toString().trim(),
      reviewedAt: reviewed,
      reviewNotes: (d['reviewNotes'] ?? '').toString(),
    );
  }
}

/// OPTACA / Provincial review of tourism establishment registrations.
class EstablishmentApprovalService {
  EstablishmentApprovalService._();

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(
        EstablishmentRegistrationService.establishmentsCollection,
      );

  static Stream<List<EstablishmentRegistryEntry>> watchAll() {
    return _col.snapshots().map((snap) {
      final list = snap.docs.map(EstablishmentRegistryEntry.fromDoc).toList()
        ..sort((a, b) {
          if (a.isPending && !b.isPending) return -1;
          if (!a.isPending && b.isPending) return 1;
          return a.businessName
              .toLowerCase()
              .compareTo(b.businessName.toLowerCase());
        });
      return list;
    });
  }

  /// LGU-scoped stream: only establishments in [municipalityId] (and aliases).
  static Stream<List<EstablishmentRegistryEntry>> watchForMunicipality(
    String municipalityId,
  ) {
    final queryIds = municipalityIdsForQuery(municipalityId);
    final canonical = normalizeMunicipalityId(municipalityId);
    return watchAll().map((all) {
      return all.where((e) {
        final id = normalizeMunicipalityId(e.municipalityId);
        if (id.isNotEmpty && queryIds.contains(id)) return true;
        // Fallback when registry only has display name.
        final fromName = getMunicipalityIdFromName(e.municipality);
        return fromName.isNotEmpty &&
            (fromName == canonical || queryIds.contains(fromName));
      }).toList();
    });
  }

  static Future<void> approve(String estId) async {
    await _setStatus(estId, EstablishmentRegistryStatus.active, notes: '');
  }

  static Future<void> reject(String estId, {String notes = ''}) async {
    await _setStatus(
      estId,
      EstablishmentRegistryStatus.rejected,
      notes: notes,
    );
  }

  static Future<void> _setStatus(
    String estId,
    String status, {
    required String notes,
  }) async {
    final id = estId.trim();
    if (id.isEmpty) throw StateError('Missing establishment id');
    final staffUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final patch = <String, dynamic>{
      'status': status,
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedByUid': staffUid,
      'reviewNotes': notes.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final batch = FirebaseFirestore.instance.batch();
    batch.set(_col.doc(id), patch, SetOptions(merge: true));
    batch.set(
      FirebaseFirestore.instance.collection('users').doc(id),
      {
        'status': status,
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedByUid': staffUid,
        if (notes.trim().isNotEmpty) 'reviewNotes': notes.trim(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
    debugPrint('[EstApproval] $id → $status by $staffUid');
  }
}
