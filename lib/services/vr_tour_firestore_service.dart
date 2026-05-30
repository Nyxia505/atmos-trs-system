import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:atmos_trs_system/config/vr_tour_config.dart';
import 'package:atmos_trs_system/models/tourist_spot.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

const String _collectionId = 'vr_tours';

/// VR on tourist spots: [tourist_spots.vr_link] is the only link LGUs edit.
/// [vr_tours] is optional analytics (view counts) keyed by spot id.
class VrTourFirestoreService {
  VrTourFirestoreService._();

  static bool get _ready {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static Map<String, dynamic> normalizeDoc(String id, Map<String, dynamic> raw) {
    final views = raw['views'];
    return {
      'id': id,
      'name': raw['name']?.toString().trim() ??
          raw['title']?.toString().trim() ??
          'VR Tour',
      'spotId': raw['spotId']?.toString().trim() ??
          raw['spot_id']?.toString().trim() ??
          '',
      'spotName': raw['spotName']?.toString().trim() ??
          raw['spot_name']?.toString().trim() ??
          '',
      'vrUrl': raw['vrUrl']?.toString().trim() ??
          raw['vr_url']?.toString().trim() ??
          raw['vr_link']?.toString().trim() ??
          '',
      'thumbnail': raw['thumbnail']?.toString().trim() ??
          raw['image_url']?.toString().trim() ??
          '',
      'municipalityId': normalizeMunicipalityId(
        raw['municipalityId']?.toString() ?? raw['municipality_id']?.toString(),
      ),
      'views': views is int
          ? views
          : (views is num ? views.toInt() : int.tryParse('$views') ?? 0),
      'status': raw['status']?.toString().trim().isNotEmpty == true
          ? raw['status'].toString().trim()
          : 'Active',
      'fromSpotOnly': true,
    };
  }

  /// Lists VR entries from [spots] that have [TouristSpot.vrLink] set (single source of truth).
  static Future<List<Map<String, dynamic>>> loadForTourism({
    String? municipalityId,
    List<TouristSpot> spots = const [],
  }) async {
    final mid = normalizeMunicipalityId(municipalityId);
    final viewCounts = await _loadViewCountsBySpotId();
    final list = <Map<String, dynamic>>[];

    for (final spot in spots) {
      final link = spot.vrLink?.trim() ?? '';
      if (link.isEmpty) continue;
      if (mid.isNotEmpty && normalizeMunicipalityId(spot.municipalityId) != mid) {
        continue;
      }
      list.add(
        normalizeDoc(
          'spot_${spot.id}',
          {
            'name': spot.name,
            'spotId': spot.id,
            'spotName': spot.name,
            'vrUrl': link,
            'municipalityId': spot.municipalityId,
            'status': spot.status,
            'views': viewCounts[spot.id] ?? 0,
          },
        ),
      );
    }

    list.sort(
      (a, b) =>
          (a['spotName']?.toString() ?? '').compareTo(b['spotName']?.toString() ?? ''),
    );
    return list;
  }

  static Future<Map<String, int>> _loadViewCountsBySpotId() async {
    final counts = <String, int>{};
    if (!_ready) return counts;
    try {
      final snap = await _db.collection(_collectionId).get();
      for (final doc in snap.docs) {
        final row = normalizeDoc(doc.id, doc.data());
        final sid = row['spotId']?.toString() ?? '';
        if (sid.isEmpty) continue;
        counts[sid] = row['views'] is int ? row['views'] as int : 0;
      }
    } catch (e) {
      debugPrint('[VrTourFirestore] view counts: $e');
    }
    return counts;
  }

  /// After saving [vr_link] on a tourist spot, keep analytics doc in sync (views only).
  static Future<void> syncAnalyticsDocForSpot({
    required String spotId,
    required String spotName,
    required String vrUrl,
    required String municipalityId,
  }) async {
    if (!_ready || spotId.isEmpty || vrUrl.trim().isEmpty) return;
    final url = vrUrl.trim();
    final mid = normalizeMunicipalityId(municipalityId);
    try {
      for (final field in ['spotId', 'spot_id']) {
        final q = await _db
            .collection(_collectionId)
            .where(field, isEqualTo: spotId)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          await q.docs.first.reference.set({
            'spotId': spotId,
            'spot_id': spotId,
            'spotName': spotName,
            'spot_name': spotName,
            'name': spotName,
            'vrUrl': url,
            'vr_url': url,
            'vr_link': url,
            'municipalityId': mid,
            'hasVR': true,
          }, SetOptions(merge: true));
          return;
        }
      }
      await _db.collection(_collectionId).add({
        'spotId': spotId,
        'spot_id': spotId,
        'spotName': spotName,
        'spot_name': spotName,
        'name': spotName,
        'vrUrl': url,
        'vr_url': url,
        'vr_link': url,
        'municipalityId': mid,
        'views': 0,
        'status': 'Active',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[VrTourFirestore] syncAnalytics: $e');
    }
  }

  /// Removes VR link from the tourist spot (does not delete the spot).
  static Future<bool> clearVrLinkForSpot(String spotId) async {
    if (!_ready || spotId.isEmpty) return false;
    try {
      await _db.collection('tourist_spots').doc(spotId).set({
        'vr_link': FieldValue.delete(),
        'hasVR': false,
      }, SetOptions(merge: true));
      for (final field in ['spotId', 'spot_id']) {
        final q = await _db
            .collection(_collectionId)
            .where(field, isEqualTo: spotId)
            .get();
        for (final doc in q.docs) {
          await doc.reference.delete();
        }
      }
      return true;
    } catch (e) {
      debugPrint('[VrTourFirestore] clearVrLink: $e');
      return false;
    }
  }

  /// Resolves VR URL for a spot: Firestore `tourist_spots.vr_link`, then known defaults.
  static Future<String?> resolveVrUrlForSpot(
    String spotId, {
    String? spotName,
  }) async {
    if (!_ready || spotId.trim().isEmpty) return null;
    final id = spotId.trim();
    try {
      final spotDoc = await _db.collection('tourist_spots').doc(id).get();
      if (spotDoc.exists && spotDoc.data() != null) {
        final d = spotDoc.data()!;
        final name = d['name']?.toString() ?? spotName ?? '';
        final known = vrUrlForSpotId(id, spotName: name);
        if (known != null) return known;
        final link = (d['vr_link'] ?? d['vrLink'] ?? '').toString().trim();
        if (link.isNotEmpty) return link;
      }
    } catch (e) {
      debugPrint('[VrTourFirestore] resolveVrUrlForSpot: $e');
    }
    return vrUrlForSpotId(id, spotName: spotName);
  }

  /// Writes the current [kOroquietaCityPlazaVrUrl] to the canonical Oroquieta spot (Tourism / mobile).
  static Future<bool> syncOroquietaPlazaVrLink() async {
    if (!_ready) return false;
    const docId = kOroquietaPlazaSpotDocId;
    const url = kOroquietaCityPlazaVrUrl;
    try {
      await _db.collection('tourist_spots').doc(docId).set({
        'vr_link': url,
        'hasVR': true,
      }, SetOptions(merge: true));
      await syncAnalyticsDocForSpot(
        spotId: docId,
        spotName: 'Oroquieta City Boulevard And People\u2019s Park \u2013 Oroquieta City',
        vrUrl: url,
        municipalityId: 'oroquieta',
      );
      return true;
    } catch (e) {
      debugPrint('[VrTourFirestore] syncOroquietaPlazaVrLink: $e');
      return false;
    }
  }

  static Future<void> incrementViewsForSpot(String spotId) async {
    if (!_ready || spotId.isEmpty) return;
    try {
      for (final field in ['spotId', 'spot_id']) {
        final q = await _db
            .collection(_collectionId)
            .where(field, isEqualTo: spotId)
            .limit(1)
            .get();
        if (q.docs.isNotEmpty) {
          await q.docs.first.reference.set({
            'views': FieldValue.increment(1),
          }, SetOptions(merge: true));
          return;
        }
      }
      await _db.collection(_collectionId).add({
        'spotId': spotId,
        'spot_id': spotId,
        'views': 1,
        'status': 'Active',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[VrTourFirestore] incrementViews: $e');
    }
  }
}
