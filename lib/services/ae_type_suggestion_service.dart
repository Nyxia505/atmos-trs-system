import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:atmos_trs_system/config/ae_register_schema.dart';
import 'package:atmos_trs_system/services/establishment_category_service.dart';
import 'package:atmos_trs_system/services/establishment_firestore_write.dart';
import 'package:atmos_trs_system/services/firestore_auth_gate.dart';

/// DOT accommodation-type suggestions (Profile → Type of Accommodation).
///
/// Official built-ins live in [AeTypeCatalog]. Hotels may suggest a new type;
/// OPTACA / provincial tourism publish it to [officialCollection] before it
/// appears in the shared dropdown. Establishments cannot approve their own
/// suggestions.
abstract final class AeTypeSuggestionService {
  static const suggestionsCollection = 'ae_type_suggestions';
  static const officialCollection = 'ae_types';

  static const statusPending = 'pending';
  static const statusApproved = 'approved';
  static const statusRejected = 'rejected';

  /// OPTACA-approved extras for the Type of Accommodation dropdown.
  static Future<List<String>> loadApprovedExtras() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(officialCollection)
          .limit(200)
          .get();
      final names = <String>[];
      for (final doc in snap.docs) {
        final name = (doc.data()['name'] as String?)?.trim() ?? '';
        if (name.isNotEmpty && !AeTypeCatalog.isOfficial(name)) {
          names.add(name);
        }
      }
      return EstablishmentCategoryNames.merge(builtIn: const [], extras: names);
    } catch (e) {
      debugPrint('[AE-TYPE] load approved extras failed: $e');
      return const [];
    }
  }

  /// Latest suggestion for this establishment (any status), if any.
  static Future<AeTypeSuggestion?> latestForEstablishment(String establishmentId) async {
    final id = establishmentId.trim();
    if (id.isEmpty) return null;
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    try {
      // Constrain by createdByUid so Firestore list rules can be proven.
      final uid = authUid.isNotEmpty ? authUid : id;
      final snap = await FirebaseFirestore.instance
          .collection(suggestionsCollection)
          .where('createdByUid', isEqualTo: uid)
          .limit(25)
          .get();
      if (snap.docs.isEmpty) return null;
      final list = snap.docs
          .map(AeTypeSuggestion.fromDoc)
          .where((s) => s.establishmentId == id || s.createdByUid == id)
          .toList()
        ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
      return list.isEmpty ? null : list.first;
    } catch (e) {
      debugPrint('[AE-TYPE] load suggestion failed: $e');
      return null;
    }
  }

  static Stream<List<AeTypeSuggestion>> watchPending() {
    return FirebaseFirestore.instance
        .collection(suggestionsCollection)
        .where('status', isEqualTo: statusPending)
        .limit(100)
        .snapshots()
        .map((s) {
      final list = s.docs.map(AeTypeSuggestion.fromDoc).toList()
        ..sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
      return list;
    });
  }

  static String? validateSuggestion({
    required String raw,
    required Iterable<String> official,
    String? alreadyPending,
  }) {
    final cleaned = EstablishmentCategoryNames.cleaned(raw);
    if (cleaned == null) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return 'Enter an accommodation type name.';
      return 'Use 2–40 letters or numbers for the type name.';
    }
    if (AeTypeCatalog.isOfficial(cleaned)) {
      final name = AeTypeCatalog.officialName(cleaned) ?? cleaned;
      return '"$name" is already on the official DOT list. Select it instead.';
    }
    final officialMatch =
        EstablishmentCategoryNames.canonicalMatch(cleaned, official);
    if (officialMatch != null) {
      return '"$officialMatch" is already approved. Select it instead.';
    }
    if (alreadyPending != null && alreadyPending.trim().isNotEmpty) {
      final pendingMatch = EstablishmentCategoryNames.canonicalMatch(
        cleaned,
        [alreadyPending],
      );
      if (pendingMatch != null) {
        return '"$pendingMatch" is already awaiting OPTACA review.';
      }
    }
    return null;
  }

  static String _friendlyPermissionError(Object e) {
    final s = e.toString();
    if (s.contains('permission-denied') || s.contains('PERMISSION_DENIED')) {
      return 'Could not save the suggestion (permission denied). '
          'Sign in as this establishment and ask your admin to deploy '
          'the latest Firestore rules for ae_type_suggestions.';
    }
    return s.replaceFirst(RegExp(r'^(\[.*?\]\s*)?'), '');
  }

  /// Stores a pending suggestion. Does not publish to the shared list or
  /// change the establishment's current approved aeType.
  static Future<String> submitPending({
    required String name,
    required String establishmentId,
    String businessName = '',
  }) async {
    final cleaned = EstablishmentCategoryNames.cleaned(name);
    if (cleaned == null) {
      throw StateError('Enter a valid accommodation type name (2–40 characters).');
    }
    final key = EstablishmentCategoryNames.keyOf(cleaned);
    if (key.isEmpty) throw StateError('Invalid type name.');

    final tokenOk = await FirestoreAuthGate.ensureFreshIdToken();
    if (!tokenOk) {
      throw StateError(FirestoreAuthGate.missingAuthMessage());
    }

    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final estId = establishmentId.trim();
    if (authUid.isEmpty) {
      throw StateError('Sign in again to suggest a type.');
    }
    if (estId.isEmpty || authUid != estId) {
      throw StateError('Sign in as this establishment to suggest a type.');
    }

    final official = await loadApprovedExtras();
    final err = validateSuggestion(
      raw: cleaned,
      official: [
        ...AeTypeCatalog.types.keys,
        ...official,
      ],
    );
    if (err != null) throw StateError(err);

    final id = '${estId}_$key';
    final payload = <String, dynamic>{
      'name': cleaned,
      'nameKey': key,
      'status': statusPending,
      'createdByUid': authUid,
      'establishmentId': estId,
      'businessName': businessName.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      // Merge so re-submitting the same pending name is an allowed owner update.
      await FirebaseFirestore.instance
          .collection(suggestionsCollection)
          .doc(id)
          .set(payload, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[AE-TYPE] suggestion write failed: $e');
      throw StateError(_friendlyPermissionError(e));
    }

    // Mirror status onto the AE profile (does not change approved aeType).
    try {
      await EstablishmentFirestoreWrite.mergeFields(estId, {
        'aeTypeSuggestion': cleaned,
        'aeTypeSuggestionId': id,
        'aeTypeSuggestionStatus': statusPending,
      });
    } catch (e) {
      // Suggestion doc is already saved; profile mirror is best-effort.
      debugPrint('[AE-TYPE] profile mirror skipped: $e');
    }

    return id;
  }

  static Future<void> approve({
    required String suggestionId,
    required String name,
    String establishmentId = '',
  }) async {
    final cleaned = EstablishmentCategoryNames.cleaned(name);
    if (cleaned == null) throw StateError('Invalid type name');
    final key = EstablishmentCategoryNames.keyOf(cleaned);
    if (key.isEmpty) throw StateError('Invalid type name');
    final staffUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (staffUid.isEmpty) throw StateError('Sign in required.');

    final db = FirebaseFirestore.instance;
    final batch = db.batch();
    batch.set(
      db.collection(officialCollection).doc(key),
      {
        'name': cleaned,
        'nameKey': key,
        'sourceSuggestionId': suggestionId.trim(),
        'approvedByUid': staffUid,
        'approvedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    final sid = suggestionId.trim();
    if (sid.isNotEmpty) {
      batch.set(
        db.collection(suggestionsCollection).doc(sid),
        {
          'status': statusApproved,
          'name': cleaned,
          'reviewedAt': FieldValue.serverTimestamp(),
          'reviewedByUid': staffUid,
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();

    final estId = establishmentId.trim();
    if (estId.isNotEmpty) {
      try {
        await EstablishmentFirestoreWrite.mergeFields(estId, {
          'aeTypeSuggestionStatus': statusApproved,
          'aeTypeSuggestion': cleaned,
        });
      } catch (e) {
        debugPrint('[AE-TYPE] approve profile mirror skipped: $e');
      }
    }
    debugPrint('[AE-TYPE] approved "$cleaned" by $staffUid');
  }

  static Future<void> reject({
    required String suggestionId,
    String establishmentId = '',
    String reason = '',
  }) async {
    final staffUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (staffUid.isEmpty) throw StateError('Sign in required.');
    final sid = suggestionId.trim();
    if (sid.isEmpty) throw StateError('Missing suggestion id.');

    await FirebaseFirestore.instance.collection(suggestionsCollection).doc(sid).set(
      {
        'status': statusRejected,
        'rejectReason': reason.trim(),
        'reviewedAt': FieldValue.serverTimestamp(),
        'reviewedByUid': staffUid,
      },
      SetOptions(merge: true),
    );

    final estId = establishmentId.trim();
    if (estId.isNotEmpty) {
      try {
        await EstablishmentFirestoreWrite.mergeFields(estId, {
          'aeTypeSuggestionStatus': statusRejected,
        });
      } catch (e) {
        debugPrint('[AE-TYPE] reject profile mirror skipped: $e');
      }
    }
  }
}

class AeTypeSuggestion {
  const AeTypeSuggestion({
    required this.id,
    required this.name,
    required this.status,
    required this.establishmentId,
    required this.businessName,
    required this.createdByUid,
    this.createdAtMs = 0,
  });

  final String id;
  final String name;
  final String status;
  final String establishmentId;
  final String businessName;
  final String createdByUid;
  final int createdAtMs;

  bool get isPending => status == AeTypeSuggestionService.statusPending;
  bool get isApproved => status == AeTypeSuggestionService.statusApproved;
  bool get isRejected => status == AeTypeSuggestionService.statusRejected;

  factory AeTypeSuggestion.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final m = doc.data() ?? const <String, dynamic>{};
    final created = m['createdAt'];
    var ms = 0;
    if (created is Timestamp) ms = created.millisecondsSinceEpoch;
    return AeTypeSuggestion(
      id: doc.id,
      name: (m['name'] ?? '').toString(),
      status: (m['status'] ?? '').toString(),
      establishmentId: (m['establishmentId'] ?? '').toString(),
      businessName: (m['businessName'] ?? '').toString(),
      createdByUid: (m['createdByUid'] ?? '').toString(),
      createdAtMs: ms,
    );
  }
}
