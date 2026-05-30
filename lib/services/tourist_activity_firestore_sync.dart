import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:atmos_trs_system/services/user_activity_service.dart';

/// Cloud backup for [UserActivityService] visits and badges (`tourist_activity/{uid}`).
class TouristActivityFirestoreSync {
  TouristActivityFirestoreSync._();

  static const String _collection = 'tourist_activity';

  static String? _lastMergedUid;

  /// Pulls server data, merges with [SharedPreferences], re-uploads merged snapshot.
  static Future<void> mergeFromCloud(String uid) async {
    if (uid.isEmpty || Firebase.apps.isEmpty) return;
    if (_lastMergedUid == uid) return;

    try {
      final snap =
          await FirebaseFirestore.instance.collection(_collection).doc(uid).get();
      final localV = await UserActivityService.getVisitedSpots();
      final localB = await UserActivityService.getEarnedBadges();

      if (!snap.exists || snap.data() == null) {
        if (localV.isNotEmpty || localB.isNotEmpty) {
          await UserActivityService.pushVisitAndBadgeSnapshotToCloud(uid);
        }
        _lastMergedUid = uid;
        return;
      }

      final data = snap.data()!;
      final remoteV = _parseVisits(data['visits']);
      final remoteB = _parseBadges(data['badges']);
      final localRv = await UserActivityService.getRecentlyViewed();
      final remoteRv = _parseVisits(data['recentlyViewed']);
      final localSaved = await UserActivityService.getSavedSpotIds();
      final remoteSaved = _parseSavedSpotIds(data['savedSpots']);
      final mergedV = _mergeVisits(localV, remoteV);
      final mergedB = _mergeBadges(localB, remoteB);
      final mergedRv = _mergeRecentlyViewed(localRv, remoteRv);
      final mergedSaved = _mergeSavedSpotIds(localSaved, remoteSaved);
      await UserActivityService.applyMergedActivityFromCloud(
        visits: mergedV,
        badges: mergedB,
        recentlyViewed: mergedRv,
        savedSpotIds: mergedSaved,
        uid: uid,
      );
      _lastMergedUid = uid;
    } catch (e) {
      debugPrint('TouristActivityFirestoreSync.mergeFromCloud: $e');
    }
  }

  static List<VisitRecord> _parseVisits(dynamic raw) {
    if (raw is! List) return [];
    final out = <VisitRecord>[];
    for (final e in raw) {
      if (e is Map<String, dynamic>) {
        out.add(VisitRecord.fromJson(e));
      } else if (e is Map) {
        out.add(VisitRecord.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return out;
  }

  static List<Badge> _parseBadges(dynamic raw) {
    if (raw is! List) return [];
    final out = <Badge>[];
    for (final e in raw) {
      if (e is Map<String, dynamic>) {
        out.add(Badge.fromJson(e));
      } else if (e is Map) {
        out.add(Badge.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return out;
  }

  static List<String> _parseSavedSpotIds(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .map((e) => e?.toString().trim() ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Same calendar day + spot counts as one visit; keep latest timestamp.
  static List<VisitRecord> _mergeVisits(List<VisitRecord> a, List<VisitRecord> b) {
    final map = <String, VisitRecord>{};
    for (final v in [...a, ...b]) {
      final d = v.visitedAt;
      final key = '${v.spotId}_${d.year}_${d.month}_${d.day}';
      final existing = map[key];
      if (existing == null || v.visitedAt.isAfter(existing.visitedAt)) {
        map[key] = v;
      }
    }
    final list = map.values.toList()
      ..sort((x, y) => y.visitedAt.compareTo(x.visitedAt));
    return list;
  }

  static List<Badge> _mergeBadges(List<Badge> a, List<Badge> b) {
    final map = <String, Badge>{};
    for (final x in [...a, ...b]) {
      final existing = map[x.id];
      if (existing == null || x.earnedAt.isAfter(existing.earnedAt)) {
        map[x.id] = x;
      }
    }
    return map.values.toList();
  }

  static List<String> _mergeSavedSpotIds(List<String> a, List<String> b) {
    final out = <String>{};
    for (final x in [...a, ...b]) {
      final v = x.trim();
      if (v.isNotEmpty) out.add(v);
    }
    return out.toList();
  }

  /// Deduplicate by spot id; keep latest open timestamp.
  static List<VisitRecord> _mergeRecentlyViewed(
    List<VisitRecord> a,
    List<VisitRecord> b,
  ) {
    final map = <String, VisitRecord>{};
    for (final v in [...a, ...b]) {
      if (v.spotId.trim().isEmpty) continue;
      final existing = map[v.spotId];
      if (existing == null || v.visitedAt.isAfter(existing.visitedAt)) {
        map[v.spotId] = v;
      }
    }
    final list = map.values.toList()
      ..sort((x, y) => y.visitedAt.compareTo(x.visitedAt));
    if (list.length > 30) return list.sublist(0, 30);
    return list;
  }
}
