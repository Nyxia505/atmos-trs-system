import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:atmos_trs_system/services/establishment_registration_service.dart';

/// Official extra establishment types (OPTACA-approved) plus applicant suggestions.
///
/// Built-in types stay in [EstablishmentRegistrationService.categoryTypes].
/// Applicants cannot publish to the shared list; they store a pending suggestion
/// tied to their application until OPTACA / provincial tourism approves it.
abstract final class EstablishmentCategoryService {
  static const suggestionsCollection = 'establishment_category_suggestions';
  static const officialCollection = 'establishment_categories';

  static const statusPending = 'pending';
  static const statusApproved = 'approved';
  static const statusRejected = 'rejected';

  static List<String> mergeOfficial({Iterable<String> extras = const []}) {
    return EstablishmentCategoryNames.merge(
      builtIn: EstablishmentRegistrationService.categoryTypes,
      extras: extras,
    );
  }

  /// Public read of OPTACA-approved extras for the signup dropdown.
  static Future<List<String>> loadApprovedExtras() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(officialCollection)
          .limit(200)
          .get();
      final names = <String>[];
      for (final doc in snap.docs) {
        final name = (doc.data()['name'] as String?)?.trim() ?? '';
        if (name.isNotEmpty) names.add(name);
      }
      return names;
    } catch (e) {
      debugPrint('[AE-CATEGORY] load approved extras failed: $e');
      return const [];
    }
  }

  /// Client-side check used by the signup dialog (no Firestore write).
  static String? validateSuggestion({
    required String raw,
    required Iterable<String> official,
    String? alreadySuggested,
  }) {
    final cleaned = EstablishmentCategoryNames.cleaned(raw);
    if (cleaned == null) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return 'Enter a category name.';
      return 'Use 2–40 letters or numbers for the category name.';
    }
    final officialMatch =
        EstablishmentCategoryNames.canonicalMatch(cleaned, official);
    if (officialMatch != null) {
      return '"$officialMatch" is already on the official list. Select it instead.';
    }
    if (alreadySuggested != null && alreadySuggested.trim().isNotEmpty) {
      final pendingMatch = EstablishmentCategoryNames.canonicalMatch(
        cleaned,
        [alreadySuggested],
      );
      if (pendingMatch != null) {
        return '"$pendingMatch" is already your suggested category.';
      }
    }
    return null;
  }

  /// Stores a pending suggestion after Auth (uid exists). Does not publish.
  static Future<String?> submitPendingSuggestion({
    required String uid,
    required String name,
    required String establishmentId,
    String businessName = '',
  }) async {
    final cleaned = EstablishmentCategoryNames.cleaned(name);
    if (cleaned == null) return null;
    final key = EstablishmentCategoryNames.keyOf(cleaned);
    if (key.isEmpty) return null;
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (authUid.isEmpty || authUid != uid) {
      debugPrint('[AE-CATEGORY] skip suggestion write: no matching auth uid');
      return null;
    }
    final id = '${uid}_$key';
    try {
      await FirebaseFirestore.instance
          .collection(suggestionsCollection)
          .doc(id)
          .set({
        'name': cleaned,
        'nameKey': key,
        'status': statusPending,
        'createdByUid': uid,
        'establishmentId': establishmentId,
        'businessName': businessName.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      return id;
    } catch (e) {
      debugPrint('[AE-CATEGORY] pending suggestion write failed: $e');
      return null;
    }
  }

  /// OPTACA / provincial: publish the name to the official shared list.
  static Future<void> approveSuggestion({
    required String name,
    String suggestionId = '',
    String establishmentId = '',
  }) async {
    final cleaned = EstablishmentCategoryNames.cleaned(name);
    if (cleaned == null) {
      throw StateError('Invalid category name');
    }
    final key = EstablishmentCategoryNames.keyOf(cleaned);
    if (key.isEmpty) throw StateError('Invalid category name');
    final staffUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final db = FirebaseFirestore.instance;
    final batch = db.batch();

    batch.set(
      db.collection(officialCollection).doc(key),
      {
        'name': cleaned,
        'nameKey': key,
        if (suggestionId.trim().isNotEmpty) 'sourceSuggestionId': suggestionId.trim(),
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

    final estId = establishmentId.trim();
    if (estId.isNotEmpty) {
      batch.set(
        db
            .collection(
              EstablishmentRegistrationService.establishmentsCollection,
            )
            .doc(estId),
        {
          'category': cleaned,
          'type': cleaned,
          'categoryPendingReview': false,
          'suggestedCategory': cleaned,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
    debugPrint('[AE-CATEGORY] approved "$cleaned" by $staffUid');
  }
}

/// Name cleanup and duplicate checks shared by the form and tests.
class EstablishmentCategoryNames {
  EstablishmentCategoryNames._();

  static final _allowed = RegExp(r"^[A-Za-z0-9][A-Za-z0-9 '&./-]{1,39}$");

  static String? cleaned(String raw) {
    final collapsed = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (collapsed.length < 2 || collapsed.length > 40) return null;
    if (collapsed.toLowerCase() == 'all') return null;
    if (!_allowed.hasMatch(collapsed)) return null;
    return collapsed;
  }

  static String keyOf(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  static String? canonicalMatch(String candidate, Iterable<String> existing) {
    final key = keyOf(candidate);
    if (key.isEmpty) return null;
    for (final name in existing) {
      if (keyOf(name) == key) return name;
    }
    return null;
  }

  static List<String> merge({
    required Iterable<String> builtIn,
    Iterable<String> extras = const [],
  }) {
    final ordered = <String>[];
    final seen = <String>{};

    void add(String raw) {
      final name = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (name.isEmpty || name.toLowerCase() == 'all') return;
      final key = keyOf(name);
      if (key.isEmpty || !seen.add(key)) return;
      ordered.add(name);
    }

    for (final name in builtIn) {
      add(name);
    }
    for (final name in extras) {
      add(name);
    }
    return ordered;
  }
}
