import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:atmos_trs_system/services/establishment_registration_service.dart';
import 'package:atmos_trs_system/services/notification_firestore_service.dart';
import 'package:atmos_trs_system/utils/establishment_capability.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Normalized registry status for OPTACA review.
abstract final class EstablishmentRegistryStatus {
  static const pending = 'pending';
  static const active = 'active';
  static const rejected = 'rejected';
  static const needsRevision = 'needs_revision';

  static String normalize(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    if (s.isEmpty || s == 'pending') return pending;
    if (s == 'active' || s == 'approved' || s == 'approve') return active;
    if (s == 'rejected' || s == 'denied') return rejected;
    if (s == 'needs_revision' ||
        s == 'needs-revision' ||
        s == 'revision' ||
        s == 'needs revision') {
      return needsRevision;
    }
    // Do not map legacy "inactive" into rejected for registry display —
    // login already blocks deactivated accounts separately.
    return s;
  }

  static bool isPending(String? raw) => normalize(raw) == pending;
  static bool isActive(String? raw) => normalize(raw) == active;
  static bool isRejected(String? raw) => normalize(raw) == rejected;
  static bool needsRevisionStatus(String? raw) =>
      normalize(raw) == needsRevision;

  /// Dashboard is allowed only for verified + active (or blank legacy status).
  static bool allowsDashboardAccess({
    required bool isVerified,
    required String status,
  }) {
    if (!isVerified) return false;
    final raw = status.trim().toLowerCase();
    if (raw.isEmpty) return true; // legacy approved rows without status
    return isActive(raw);
  }

  /// Post-verification holding route while OPTACA decides.
  static bool requiresOptacaHold(String? status) {
    final raw = (status ?? '').trim().toLowerCase();
    if (raw.isEmpty) return false;
    final n = normalize(raw);
    return n == pending || n == rejected || n == needsRevision;
  }
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
    this.categoryPendingReview = false,
    this.suggestedCategory = '',
    this.categorySuggestionId = '',
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
  /// Applicant suggested a type that is not yet on the official list.
  final bool categoryPendingReview;
  final String suggestedCategory;
  final String categorySuggestionId;

  bool get isPending => EstablishmentRegistryStatus.isPending(status);
  bool get isActive => EstablishmentRegistryStatus.isActive(status);
  bool get isRejected => EstablishmentRegistryStatus.isRejected(status);
  bool get needsRevision =>
      EstablishmentRegistryStatus.needsRevisionStatus(status);

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
      categoryPendingReview: d['categoryPendingReview'] == true,
      suggestedCategory: (d['suggestedCategory'] ?? '').toString(),
      categorySuggestionId: (d['categorySuggestionId'] ?? '').toString(),
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
    final reason = notes.trim();
    if (reason.isEmpty) {
      throw StateError('A rejection reason is required.');
    }
    await _setStatus(
      estId,
      EstablishmentRegistryStatus.rejected,
      notes: reason,
    );
  }

  static Future<void> requestRevision(String estId, {String notes = ''}) async {
    final reason = notes.trim();
    if (reason.isEmpty) {
      throw StateError('Describe what the establishment must correct.');
    }
    await _setStatus(
      estId,
      EstablishmentRegistryStatus.needsRevision,
      notes: reason,
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
        'reviewNotes': notes.trim(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
    debugPrint('[EstApproval] $id → $status by $staffUid');

    String businessName = '';
    try {
      final snap = await _col.doc(id).get();
      final d = snap.data() ?? const <String, dynamic>{};
      businessName =
          (d['businessName'] ?? d['name'] ?? '').toString();
    } catch (_) {}

    unawaited(
      NotificationFirestoreService.createEstablishmentDecisionNotification(
        userId: id,
        businessName: businessName,
        status: status,
        reviewNotes: notes,
      ),
    );
    unawaited(
      NotificationFirestoreService.resolveOptacaEstablishmentRegistrationAlert(
        id,
        status: status,
      ),
    );
  }

  /// OPTACA edits the establishment profile. Login email stays on the Auth account.
  static Future<void> updateProfile({
    required String estId,
    required String businessName,
    required String ownerName,
    required String municipalityId,
    required String municipality,
    required String category,
    String contactNumber = '',
    String barangay = '',
    String businessPermitNo = '',
    int? roomCount,
    bool clearPendingCategory = false,
  }) async {
    final id = estId.trim();
    if (id.isEmpty) throw StateError('Missing establishment id');
    final name = businessName.trim();
    final owner = ownerName.trim();
    final placeId = normalizeMunicipalityId(municipalityId);
    final place = municipality.trim();
    final type = category.trim();
    if (name.isEmpty) throw StateError('Business name is required.');
    if (owner.isEmpty) throw StateError('Owner name is required.');
    if (placeId.isEmpty || place.isEmpty) {
      throw StateError('Choose a municipality in Misamis Occidental.');
    }
    if (type.isEmpty) throw StateError('Category is required.');

    final location = [
      barangay.trim(),
      place,
      'Misamis Occidental',
    ].where((part) => part.isNotEmpty).join(', ');
    final estPatch = <String, dynamic>{
      'businessName': name,
      'name': name,
      'ownerName': owner,
      'category': type,
      'type': type,
      'municipalityId': placeId,
      'municipality': place,
      'barangay': barangay.trim(),
      'location': location,
      'contactNumber': contactNumber.trim(),
      'businessPermitNo': businessPermitNo.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (roomCount != null) estPatch['roomCount'] = roomCount;
    if (clearPendingCategory) {
      estPatch['categoryPendingReview'] = false;
      estPatch['suggestedCategory'] = FieldValue.delete();
    }
    final userPatch = <String, dynamic>{
      'businessName': name,
      'fullName': owner,
      'category': type,
      'municipalityId': placeId,
      'municipality': place,
      'barangay': barangay.trim(),
      'contactNumber': contactNumber.trim(),
      'businessPermitNo': businessPermitNo.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    final batch = FirebaseFirestore.instance.batch();
    batch.set(_col.doc(id), estPatch, SetOptions(merge: true));
    batch.set(
      FirebaseFirestore.instance.collection('users').doc(id),
      userPatch,
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// Removes the establishment registry and user profile.
  ///
  /// Returns whether the Firebase login was deleted too. That step needs the
  /// deployed `optacaManageAccount` delete action; without it the email stays
  /// reserved in Authentication.
  static Future<bool> deleteAccount(String estId) async {
    final id = estId.trim();
    if (id.isEmpty) throw StateError('Missing establishment id');
    final loginRemoved = await _deleteLoginViaFunction(id);
    if (!loginRemoved) {
      await _deleteAccountDocs(id);
    }
    return loginRemoved;
  }

  static Future<bool> _deleteLoginViaFunction(String uid) async {
    try {
      final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
      await functions
          .httpsCallable(
            'optacaManageAccount',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
          )
          .call(<String, dynamic>{'action': 'delete', 'uid': uid});
      return true;
    } on FirebaseFunctionsException catch (e) {
      final message = (e.message ?? '').toLowerCase();
      final missing = e.code == 'not-found' ||
          e.code == 'unavailable' ||
          e.code == 'unimplemented' ||
          message.contains('unknown account action');
      if (missing) return false;
      throw StateError(
        (e.message ?? '').trim().isEmpty
            ? 'Could not delete the establishment login.'
            : e.message!.trim(),
      );
    }
  }

  static Future<void> _deleteAccountDocs(String uid) async {
    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    batch.delete(db.collection('users').doc(uid));
    batch.delete(_col.doc(uid));
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw StateError(
          'OPTACA cannot delete this account until the latest Firestore rules are published.',
        );
      }
      throw StateError(e.message ?? 'Could not delete the establishment account.');
    }

    try {
      final owned = await db
          .collection('usernames')
          .where('uid', isEqualTo: uid)
          .limit(5)
          .get();
      for (final doc in owned.docs) {
        try {
          await doc.reference.delete();
        } catch (e) {
          debugPrint('[EstApproval] username delete ${doc.id}: $e');
        }
      }
    } catch (e) {
      debugPrint('[EstApproval] username lookup: $e');
    }
  }
}
