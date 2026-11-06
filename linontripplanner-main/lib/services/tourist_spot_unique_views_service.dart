import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../data.dart';
import 'firebase_functions_config.dart';

const String kTouristSpotViewsCollection = 'touristSpotViews';
const String kTouristSpotViewCountsCollection = 'touristSpotViewCounts';

/// Candidate Firestore ids for a spot (doc id + stable name key).
///
/// Older sessions may have written under either key; we resolve both so
/// logout/login never "loses" a persisted count due to id drift.
Set<String> touristSpotUniqueViewCandidateIds(TouristSpot spot) {
  final ids = <String>{};
  void add(String? raw) {
    final id = (raw ?? '').trim();
    if (id.isEmpty || id.contains('/')) return;
    ids.add(id);
  }

  add(spot.firestoreDocId);
  add(normalizeTourismNameKey(spot.name));

  // Prefer catalog match so cards without a local doc id still hit the
  // same counter written from SpotDetailScreen.
  final linked = findTouristSpotByNameFuzzy(spot.name);
  if (linked != null) {
    add(linked.firestoreDocId);
    add(normalizeTourismNameKey(linked.name));
  }
  return ids;
}

/// Canonical id used when creating a new unique-view record.
String touristSpotUniqueViewSpotId(TouristSpot spot) {
  final linked = findTouristSpotByNameFuzzy(spot.name) ?? spot;
  final docId = (linked.firestoreDocId ?? '').trim();
  if (docId.isNotEmpty && !docId.contains('/')) return docId;
  final nameKey = normalizeTourismNameKey(linked.name);
  if (nameKey.isNotEmpty) return nameKey;
  return normalizeTourismNameKey(spot.name);
}

String formatUniqueViewCount(int count) {
  final n = count < 0 ? 0 : count;
  final raw = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final remaining = raw.length - i;
    if (i > 0 && remaining % 3 == 0) buf.write(',');
    buf.write(raw[i]);
  }
  final formatted = buf.toString();
  return n == 1 ? '$formatted view' : '$formatted views';
}

/// Unique authenticated views for tourist spots (one user → one count).
///
/// Global totals live in Firestore `touristSpotViewCounts` and must survive
/// logout / account switches. Local maps are only a display cache.
class TouristSpotUniqueViewsService {
  TouristSpotUniqueViewsService._() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      // Drop only per-user session dedupe. Keep global counts in memory so
      // Recommended for You does not flash 0 while Firestore reloads.
      _recordedThisSession.clear();
      if (user != null) {
        // Force a fresh pull of denormalized counters after login.
        unawaited(refreshKnownCounts());
      }
    });
  }

  static final TouristSpotUniqueViewsService instance =
      TouristSpotUniqueViewsService._();

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// spotId → confirmed global unique view count (from Firestore or commit).
  final Map<String, int> _counts = {};

  /// spotIds currently being fetched (not yet confirmed).
  final Set<String> _inflightPrefetch = {};

  /// Per auth-session dedupe: spotId_uid already recorded this process.
  final Set<String> _recordedThisSession = {};

  /// Held for process lifetime so auth changes keep global counts stable.
  StreamSubscription<User?>? _authSub;

  /// True when we have a confirmed Firestore (or write) value for [spotId].
  bool hasConfirmedCount(String spotId) => _counts.containsKey(spotId);

  bool hasConfirmedCountForSpot(TouristSpot spot) {
    for (final id in touristSpotUniqueViewCandidateIds(spot)) {
      if (_counts.containsKey(id)) return true;
    }
    return false;
  }

  int cachedCount(String spotId) => _counts[spotId] ?? 0;

  /// Best-known global count across candidate ids. Returns 0 only when a
  /// confirmed empty counter exists, or when nothing is cached yet (callers
  /// should use [hasConfirmedCountForSpot] to avoid flashing 0).
  int cachedCountForSpot(TouristSpot spot) {
    var best = 0;
    var found = false;
    for (final id in touristSpotUniqueViewCandidateIds(spot)) {
      final v = _counts[id];
      if (v == null) continue;
      found = true;
      if (v > best) best = v;
    }
    return found ? best : 0;
  }

  /// Display count: prefers confirmed cache; null means still loading.
  int? displayCountForSpot(TouristSpot spot) {
    if (hasConfirmedCountForSpot(spot)) return cachedCountForSpot(spot);
    return null;
  }

  void _setCount(String spotId, int count, {Iterable<String>? aliases}) {
    final next = count < 0 ? 0 : count;
    var changed = false;
    void write(String id) {
      if (id.isEmpty) return;
      if (_counts[id] == next) return;
      // Never overwrite a higher confirmed value with a lower speculative one
      // unless the caller intentionally refreshed from Firestore.
      _counts[id] = next;
      changed = true;
    }

    write(spotId);
    if (aliases != null) {
      for (final a in aliases) {
        write(a);
      }
    }
    if (changed) revision.value++;
  }

  /// Mirrors [count] onto every candidate id for [spot] so UI lookups agree.
  void _mirrorCountForSpot(TouristSpot spot, int count) {
    final ids = touristSpotUniqueViewCandidateIds(spot);
    final canonical = touristSpotUniqueViewSpotId(spot);
    ids.add(canonical);
    _setCount(canonical, count, aliases: ids);
  }

  Future<int?> _readCounterDoc(String spotId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection(kTouristSpotViewCountsCollection)
          .doc(spotId)
          .get();
      if (!snap.exists) return 0;
      final raw = snap.data()?['count'];
      final count = raw is num ? raw.toInt() : 0;
      return count < 0 ? 0 : count;
    } catch (e) {
      debugPrint('TouristSpotUniqueViewsService.readCounter($spotId): $e');
      // Preserve prior cache on failure — never invent a zero.
      return null;
    }
  }

  /// Reads all candidate counter docs and returns the highest existing count.
  Future<int?> _readBestCounter(Iterable<String> ids) async {
    var best = 0;
    var anySuccess = false;
    for (final id in ids) {
      if (id.isEmpty) continue;
      final count = await _readCounterDoc(id);
      if (count == null) continue;
      anySuccess = true;
      if (count > best) best = count;
    }
    return anySuccess ? best : null;
  }

  /// Force-refresh counters already known (e.g. after login).
  Future<void> refreshKnownCounts() async {
    final ids = _counts.keys.toList(growable: false);
    if (ids.isEmpty) return;
    await prefetchIds(ids, force: true);
  }

  /// Loads denormalized counters. Does not clear existing cache on logout.
  Future<void> prefetchForSpots(
    Iterable<TouristSpot> spots, {
    bool force = false,
  }) async {
    final ids = <String>{};
    for (final spot in spots) {
      ids.addAll(touristSpotUniqueViewCandidateIds(spot));
    }
    await prefetchIds(ids, force: force);
  }

  Future<void> prefetchIds(
    Iterable<String> rawIds, {
    bool force = false,
  }) async {
    final ids = <String>{};
    for (final raw in rawIds) {
      final id = raw.trim();
      if (id.isEmpty || id.contains('/')) continue;
      if (!force && _counts.containsKey(id)) continue;
      if (_inflightPrefetch.contains(id)) continue;
      ids.add(id);
    }
    if (ids.isEmpty) return;
    _inflightPrefetch.addAll(ids);
    try {
      final snaps = await Future.wait([
        for (final id in ids)
          FirebaseFirestore.instance
              .collection(kTouristSpotViewCountsCollection)
              .doc(id)
              .get(),
      ]);
      var changed = false;
      for (final snap in snaps) {
        final id = snap.id;
        final next = !snap.exists
            ? 0
            : () {
                final raw = snap.data()?['count'];
                final count = raw is num ? raw.toInt() : 0;
                return count < 0 ? 0 : count;
              }();
        if (_counts[id] == next) continue;
        // On forced refresh, accept Firestore value (including 0).
        // On first load, store confirmed value.
        _counts[id] = next;
        changed = true;
      }
      if (changed) revision.value++;
    } catch (e) {
      debugPrint('TouristSpotUniqueViewsService.prefetch: $e');
      // Do not write zeros on failure — keep prior confirmed values and let
      // UI keep showing them (or stay in loading state).
    } finally {
      _inflightPrefetch.removeAll(ids);
      // Nudge listeners so loading badges can settle even if unchanged.
      revision.value++;
    }
  }

  /// Creates the unique-view doc and increments the counter in one batch.
  Future<int?> _recordViaClientBatch({
    required String spotId,
    required String uid,
    required TouristSpot spot,
  }) async {
    final db = FirebaseFirestore.instance;
    final candidateIds = touristSpotUniqueViewCandidateIds(spot)..add(spotId);

    // Idempotent across id aliases: if this user already viewed under any
    // historical spot id, do not create a second unique view.
    final existingViews = await Future.wait([
      for (final id in candidateIds)
        db.collection(kTouristSpotViewsCollection).doc('${id}_$uid').get(),
    ]);
    final alreadyViewed = existingViews.any((s) => s.exists);
    if (alreadyViewed) {
      final count = await _readBestCounter(candidateIds);
      if (count != null) _mirrorCountForSpot(spot, count);
      return cachedCountForSpot(spot);
    }

    final viewRef =
        db.collection(kTouristSpotViewsCollection).doc('${spotId}_$uid');
    final countRef =
        db.collection(kTouristSpotViewCountsCollection).doc(spotId);

    final batch = db.batch();
    batch.set(viewRef, {
      'spotId': spotId,
      'userId': uid,
      'viewedAt': FieldValue.serverTimestamp(),
    });
    batch.set(
      countRef,
      {
        'spotId': spotId,
        'count': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();

    final prior = cachedCountForSpot(spot);
    final optimistic = prior + 1;
    _mirrorCountForSpot(spot, optimistic);

    final actual = await _readBestCounter(candidateIds);
    if (actual != null && actual > 0) {
      _mirrorCountForSpot(spot, actual);
    }
    return cachedCountForSpot(spot);
  }

  /// Records a unique view when [spot] details open successfully.
  Future<int> recordUniqueView(TouristSpot spot) async {
    final spotId = touristSpotUniqueViewSpotId(spot);
    if (spotId.isEmpty) return cachedCountForSpot(spot);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await prefetchForSpots([spot], force: true);
      return cachedCountForSpot(spot);
    }

    final sessionKey = '${spotId}_${user.uid}';
    if (_recordedThisSession.contains(sessionKey)) {
      return cachedCountForSpot(spot);
    }

    // Client batch first: works without deploying the callable, and avoids
    // expensive aggregation count() queries that hit Spark quotas.
    try {
      final count = await _recordViaClientBatch(
        spotId: spotId,
        uid: user.uid,
        spot: spot,
      );
      _recordedThisSession.add(sessionKey);
      // Also mark name-key session aliases so remounts with id drift don't
      // double-submit in the same auth session.
      for (final id in touristSpotUniqueViewCandidateIds(spot)) {
        _recordedThisSession.add('${id}_${user.uid}');
      }
      if (count != null) return count;
    } on FirebaseException catch (e) {
      debugPrint(
        'recordTouristSpotUniqueView client batch: ${e.code} ${e.message}',
      );
    } catch (e) {
      debugPrint('recordTouristSpotUniqueView client batch: $e');
    }

    // Optional Cloud Function path (atomic server-side).
    try {
      final callable = tourismCloudFunctions()
          .httpsCallable('recordTouristSpotUniqueView');
      final result = await callable.call(<String, dynamic>{'spotId': spotId});
      final data = result.data;
      if (data is Map) {
        final raw = data['uniqueViews'];
        final count =
            raw is num ? raw.toInt() : cachedCountForSpot(spot);
        _mirrorCountForSpot(spot, count);
        _recordedThisSession.add(sessionKey);
        for (final id in touristSpotUniqueViewCandidateIds(spot)) {
          _recordedThisSession.add('${id}_${user.uid}');
        }
        return cachedCountForSpot(spot);
      }
    } on FirebaseFunctionsException catch (e) {
      debugPrint(
        'recordTouristSpotUniqueView callable failed: ${e.code} ${e.message}',
      );
    } catch (e) {
      debugPrint('recordTouristSpotUniqueView callable failed: $e');
    }

    _recordedThisSession.add(sessionKey);
    final fallback = await _readBestCounter(
      touristSpotUniqueViewCandidateIds(spot)..add(spotId),
    );
    if (fallback != null) _mirrorCountForSpot(spot, fallback);
    return cachedCountForSpot(spot);
  }

  /// Logout cleanup: drop only auth-session dedupe keys.
  /// Never clears global view counts or writes zeros to Firestore.
  void clearAuthSessionOnly() {
    _recordedThisSession.clear();
  }

  @visibleForTesting
  void debugReset() {
    _authSub?.cancel();
    _authSub = null;
    _counts.clear();
    _inflightPrefetch.clear();
    _recordedThisSession.clear();
    revision.value++;
  }
}
