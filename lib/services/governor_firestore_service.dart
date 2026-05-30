import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Provincial analytics loaded from Firestore for the Governor portal.
class GovernorFirestoreSnapshot {
  const GovernorFirestoreSnapshot({
    required this.tourists,
    required this.checkIns,
    required this.touristSpots,
    required this.announcements,
    this.loadWarnings = const [],
  });

  final List<Map<String, dynamic>> tourists;
  final List<Map<String, dynamic>> checkIns;
  final List<Map<String, dynamic>> touristSpots;
  final List<Map<String, dynamic>> announcements;
  final List<String> loadWarnings;
}

/// Loads and normalizes Firestore data for [GovernorDashboard].
class GovernorFirestoreService {
  GovernorFirestoreService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const GetOptions _serverGet = GetOptions(source: Source.server);

  Future<GovernorFirestoreSnapshot> loadProvincialSnapshot() async {
    final warnings = <String>[];

    List<Map<String, dynamic>> spots = [];
    try {
      final snap =
          await _firestore.collection('tourist_spots').get(_serverGet);
      spots = snap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .where(_isTouristSpotInProvince)
          .toList();
    } catch (e) {
      debugPrint('[GovernorFirestore] tourist_spots: $e');
      warnings.add('Could not load tourist spots.');
    }

    final spotsById = {for (final s in spots) s['id']?.toString() ?? '': s};

    List<Map<String, dynamic>> tourists = [];
    try {
      final snap = await _firestore.collection('tourists').get(_serverGet);
      tourists = snap.docs
          .map((d) => {'id': d.id, ...d.data()})
          .where(_isTouristInProvinceScope)
          .toList();
    } catch (e) {
      debugPrint('[GovernorFirestore] tourists: $e');
      warnings.add('Could not load tourists (check sign-in / Firestore rules).');
    }

    final checkIns = await _loadAllCheckIns(spotsById, warnings);

    List<Map<String, dynamic>> announcements = [];
    try {
      final snap = await _firestore
          .collection('announcements')
          .orderBy('createdAt', descending: true)
          .get(_serverGet);
      announcements =
          snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      debugPrint('[GovernorFirestore] announcements orderBy: $e');
      try {
        final snap =
            await _firestore.collection('announcements').get(_serverGet);
        announcements =
            snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
      } catch (e2) {
        debugPrint('[GovernorFirestore] announcements: $e2');
        warnings.add('Could not load announcements.');
      }
    }

    return GovernorFirestoreSnapshot(
      tourists: tourists,
      checkIns: checkIns,
      touristSpots: spots,
      announcements: announcements,
      loadWarnings: warnings,
    );
  }

  Future<List<Map<String, dynamic>>> _loadAllCheckIns(
    Map<String, Map<String, dynamic>> spotsById,
    List<String> warnings,
  ) async {
    final byId = <String, Map<String, dynamic>>{};

    Future<void> ingest(
      String collection, {
      bool legacyOptional = false,
    }) async {
      try {
        final snap =
            await _firestore.collection(collection).get(_serverGet);
        _mergeCheckInDocs(
          snap.docs,
          collection: collection,
          spotsById: spotsById,
          byId: byId,
        );
      } catch (e) {
        final denied = e.toString().contains('permission-denied');
        if (legacyOptional && denied) {
          debugPrint(
            '[GovernorFirestore] $collection: skipped (legacy collection; '
            'qr_checkins/check_ins already loaded)',
          );
          return;
        }
        debugPrint(
          '[GovernorFirestore] $collection: $e '
          '(uid=${FirebaseAuth.instance.currentUser?.uid})',
        );
        if (collection == 'qr_checkins') {
          try {
            await _ingestQrCheckInsByMunicipality(
              spotsById: spotsById,
              byId: byId,
            );
            return;
          } catch (e2) {
            debugPrint('[GovernorFirestore] qr_checkins fallback: $e2');
          }
        }
      }
    }

    await ingest('qr_checkins');
    await ingest('checkins', legacyOptional: true);
    // Legacy underscore collection (tourism web); app writes `checkins` + `qr_checkins`.
    await ingest('check_ins', legacyOptional: true);

    if (byId.isEmpty) {
      warnings.add(
        'Could not load check-in records. Sign in as governor, then deploy '
        'Firestore rules (`firebase deploy --only firestore:rules`) and '
        'Cloud Function `ensureStaffAccess` if needed.',
      );
    }

    final list = byId.values.toList();
    list.sort((a, b) {
      final ta = parseCheckInTime(a);
      final tb = parseCheckInTime(b);
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });
    return list;
  }

  void _mergeCheckInDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required String collection,
    required Map<String, Map<String, dynamic>> spotsById,
    required Map<String, Map<String, dynamic>> byId,
  }) {
    for (final doc in docs) {
      final normalized = normalizeCheckInRow(
        doc.id,
        doc.data(),
        spotsById: spotsById,
        sourceCollection: collection,
      );
      if (normalized == null) continue;
      if (!_isCheckInInProvince(normalized)) continue;
      byId['$collection:${doc.id}'] = normalized;
    }
  }

  /// Same query shape as LGU tourism dashboards (municipalityId filter).
  Future<void> _ingestQrCheckInsByMunicipality({
    required Map<String, Map<String, dynamic>> spotsById,
    required Map<String, Map<String, dynamic>> byId,
  }) async {
    final queryIds = <String>{};
    for (final m in getMisamisOccidentalMunicipalities()) {
      queryIds.addAll(municipalityIdsForQuery(m.id));
    }
    final ids = queryIds.toList();
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, min(i + 10, ids.length));
      final Query<Map<String, dynamic>> q = chunk.length == 1
          ? _firestore
              .collection('qr_checkins')
              .where('municipalityId', isEqualTo: chunk.first)
          : _firestore
              .collection('qr_checkins')
              .where('municipalityId', whereIn: chunk);
      final snap = await q.get(_serverGet);
      _mergeCheckInDocs(
        snap.docs,
        collection: 'qr_checkins',
        spotsById: spotsById,
        byId: byId,
      );
    }
  }

  static bool _isTouristSpotInProvince(Map<String, dynamic> spot) {
    if (isMisamisOccidentalMunicipalityId(spot['municipalityId']?.toString())) {
      return true;
    }
    final fromName = getMunicipalityIdFromName(spot['municipality']?.toString());
    return fromName.isNotEmpty && isMisamisOccidentalMunicipalityId(fromName);
  }

  /// Provincial registry: include tourists unless explicitly registered outside Misamis Occidental.
  static bool _isTouristInProvinceScope(Map<String, dynamic> t) {
    final prov = t['province']?.toString().toLowerCase().trim() ?? '';
    if (prov.isNotEmpty &&
        !prov.contains('misamis occidental') &&
        !prov.contains('misocc')) {
      return false;
    }
    return true;
  }

  static bool _isCheckInInProvince(Map<String, dynamic> c) {
    if (isMisamisOccidentalMunicipalityId(c['municipalityId']?.toString())) {
      return true;
    }
    final fromName = getMunicipalityIdFromName(c['municipality']?.toString());
    if (fromName.isNotEmpty && isMisamisOccidentalMunicipalityId(fromName)) {
      return true;
    }
    return false;
  }

  /// Normalizes qr_checkins, check_ins, and checkins into one dashboard row shape.
  static Map<String, dynamic>? normalizeCheckInRow(
    String docId,
    Map<String, dynamic> raw, {
    required Map<String, Map<String, dynamic>> spotsById,
    required String sourceCollection,
  }) {
    Map<String, dynamic> row;
    if (sourceCollection == 'checkins') {
      final spotId = raw['location_id']?.toString() ?? '';
      row = {
        'id': docId,
        'userId': raw['user_id']?.toString() ?? '',
        'tourist_id': raw['user_id']?.toString() ?? '',
        'spotId': spotId,
        'spot_id': spotId,
        'timestamp': raw['checkin_time'] ?? raw['timestamp'],
      };
    } else if (sourceCollection == 'check_ins') {
      row = {
        'id': docId,
        'userId':
            raw['userId']?.toString() ?? raw['user_id']?.toString() ?? '',
        'tourist_id':
            raw['tourist_id']?.toString() ??
            raw['userId']?.toString() ??
            raw['user_id']?.toString() ??
            '',
        'spotId':
            raw['spotId']?.toString() ??
            raw['spot_id']?.toString() ??
            raw['location_id']?.toString() ??
            '',
        'spot_id':
            raw['spot_id']?.toString() ??
            raw['spotId']?.toString() ??
            raw['location_id']?.toString() ??
            '',
        'municipalityId': raw['municipalityId']?.toString() ?? '',
        'municipality': raw['municipality']?.toString() ?? '',
        'spot_name': raw['spot_name']?.toString() ?? '',
        'spotCategory': raw['spotCategory']?.toString() ?? raw['category']?.toString() ?? '',
        'timestamp': raw['timestamp'] ?? raw['checkin_time'] ?? raw['checkedInAt'],
      };
    } else {
      row = {'id': docId, ...raw};
    }

    final spotId =
        row['spotId']?.toString().trim() ??
        row['spot_id']?.toString().trim() ??
        '';
    if (spotId.isNotEmpty) {
      final spot = spotsById[spotId];
      if (spot != null) {
        if ((row['municipalityId']?.toString().trim().isEmpty ?? true) &&
            spot['municipalityId'] != null) {
          row['municipalityId'] = spot['municipalityId'];
        }
        if ((row['municipality']?.toString().trim().isEmpty ?? true) &&
            spot['municipality'] != null) {
          row['municipality'] = spot['municipality'];
        }
        if ((row['spotCategory']?.toString().trim().isEmpty ?? true) &&
            spot['category'] != null) {
          row['spotCategory'] = spot['category'];
        }
        if ((row['spot_name']?.toString().trim().isEmpty ?? true) &&
            spot['name'] != null) {
          row['spot_name'] = spot['name'];
        }
      }
    }

    final uid =
        row['userId']?.toString().trim() ??
        row['tourist_id']?.toString().trim() ??
        '';
    if (uid.isEmpty && spotId.isEmpty) return null;

    row['userId'] = uid.isNotEmpty ? uid : row['userId'];
    row['tourist_id'] = uid.isNotEmpty ? uid : row['tourist_id'];
    return row;
  }

  static DateTime? parseCheckInTime(Map<String, dynamic> c) {
    final t = c['timestamp'] ?? c['checkin_time'] ?? c['checkedInAt'] ?? c['createdAt'];
    if (t == null) return null;
    if (t is Timestamp) return t.toDate();
    if (t is DateTime) return t;
    if (t is int) {
      return DateTime.fromMillisecondsSinceEpoch(
        t > 9999999999 ? t : t * 1000,
      );
    }
    final s = t.toString().trim();
    if (s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  static String checkInUserId(Map<String, dynamic> c) {
    return c['userId']?.toString().trim() ??
        c['tourist_id']?.toString().trim() ??
        c['user_id']?.toString().trim() ??
        '';
  }
}
