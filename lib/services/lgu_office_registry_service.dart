import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/services/user_directory_service.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Public record of which municipality already has an LGU tourism office.
///
/// Documents live in `lgu_offices/{municipalityId}`. Existing `users` profiles
/// are never updated here. A missing document means the municipality can still
/// be chosen on signup. The first office to sign in (or a governor / provincial
/// login) creates the document; later writes are ignored.
class LguOfficeRegistryService {
  LguOfficeRegistryService._();

  static const String collection = 'lgu_offices';

  /// Taken municipality ids, or null when the list could not be read.
  static Future<Set<String>?> takenMunicipalityIds() async {
    if (Firebase.apps.isEmpty) return null;
    try {
      final snap =
          await FirebaseFirestore.instance.collection(collection).get();
      return {
        for (final doc in snap.docs) normalizeMunicipalityId(doc.id),
      }..remove('');
    } catch (e) {
      debugPrint('[LGU-OFFICE] could not read office list: $e');
      return null;
    }
  }

  /// Records the signed-in office, or every existing tourism office when the
  /// signed-in user is governor or provincial tourism.
  static Future<void> syncForCurrentUser() async {
    if (Firebase.apps.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final profile = await UserDirectoryService.getProfileByUid(
        user.uid,
        preferServer: false,
      );
      if (profile == null) return;
      if (profile.isGovernor || profile.isProvincialTourism) {
        await recordExistingOffices();
        return;
      }
      if (!profile.isTourismOffice) return;
      await _createIfAbsent(
        municipalityId: _idFor(
          municipalityId: profile.municipalityId,
          municipalityName: profile.municipality,
        ),
        holderUid: profile.uid,
      );
    } catch (e) {
      debugPrint('[LGU-OFFICE] sync skipped: $e');
    }
  }

  /// Creates one office document per municipality already stored on `users`.
  /// Does not change those user documents.
  static Future<void> recordExistingOffices() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection(UserDirectoryService.collectionId)
          .where('role', whereIn: const ['tourism', 'tourism_office'])
          .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        await _createIfAbsent(
          municipalityId: _idFor(
            municipalityId: (data['municipalityId'] ?? '').toString(),
            municipalityName: (data['municipality'] ?? '').toString(),
          ),
          holderUid: doc.id,
        );
      }
    } catch (e) {
      debugPrint('[LGU-OFFICE] existing-office sync skipped: $e');
    }
  }

  static String _idFor({
    required String municipalityId,
    required String municipalityName,
  }) {
    var id = normalizeMunicipalityId(municipalityId);
    if (id.isEmpty) id = getMunicipalityIdFromName(municipalityName);
    if (!isMisamisOccidentalMunicipalityId(id)) return '';
    return id;
  }

  static String _catalogName(String municipalityId) {
    for (final municipality in getMisamisOccidentalMunicipalities()) {
      if (normalizeMunicipalityId(municipality.id) == municipalityId) {
        return municipality.name;
      }
    }
    return '';
  }

  static Future<void> _createIfAbsent({
    required String municipalityId,
    required String holderUid,
  }) async {
    if (municipalityId.isEmpty || holderUid.isEmpty) return;
    final name = _catalogName(municipalityId);
    if (name.isEmpty) return;
    final ref =
        FirebaseFirestore.instance.collection(collection).doc(municipalityId);
    try {
      final existing = await ref.get();
      if (existing.exists) return;
      await ref.set({
        'municipalityId': municipalityId,
        'municipality': name,
        'holderUid': holderUid,
      });
    } catch (e) {
      debugPrint('[LGU-OFFICE] claim $municipalityId skipped: $e');
    }
  }
}
