import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data.dart';
import '../firestore_loader.dart';

/// Persists tourist spot reviews locally and in Firestore `spot_ratings`.
class SpotRatingsStore {
  SpotRatingsStore._();
  static final SpotRatingsStore instance = SpotRatingsStore._();

  static const _key = 'spot_user_reviews_v1';

  SharedPreferences? _prefs;
  bool _loaded = false;
  bool _remoteLoaded = false;

  /// Bumped whenever [spotRatings] changes so spot detail pages rebuild.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<SharedPreferences> _sp() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  String _dedupeKey(SpotRating r) {
    if (r.id.trim().isNotEmpty) return 'id:${r.id.trim()}';
    return '${r.userId}|${r.spotName}|${r.rating}|${r.description}';
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final raw = (await _sp()).getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        final loaded = <SpotRating>[];
        for (final item in list) {
          if (item is Map<String, dynamic>) {
            loaded.add(SpotRating.fromJson(item));
          } else if (item is Map) {
            loaded.add(
              SpotRating.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        }
        mergeRemote(loaded);
      } catch (e) {
        debugPrint('SpotRatingsStore load failed: $e');
      }
    }
    await refreshFromFirestore();
  }

  Future<void> refreshFromFirestore() async {
    try {
      final remote = await fetchSpotRatingsFromFirestore();
      if (remote.isEmpty && _remoteLoaded) return;
      mergeRemote(remote);
      _remoteLoaded = true;
    } catch (e) {
      debugPrint('SpotRatingsStore Firestore refresh failed: $e');
    }
  }

  /// Merges [remote] into [spotRatings] without wiping local-only entries.
  void mergeRemote(List<SpotRating> remote) {
    if (remote.isEmpty) return;
    final keys = <String>{
      for (final r in spotRatings) _dedupeKey(r),
    };
    var added = 0;
    for (final r in remote) {
      if (keys.add(_dedupeKey(r))) {
        spotRatings.add(r);
        added++;
      }
    }
    if (added > 0) revision.value++;
  }

  Future<void> _persist() async {
    final sp = await _sp();
    await sp.setString(
      _key,
      jsonEncode(spotRatings.map((r) => r.toJson()).toList()),
    );
  }

  /// Saves rating + optional comment locally and to Firestore when possible.
  Future<void> add(SpotRating rating) async {
    await ensureLoaded();
    var toSave = rating.createdAt != null
        ? rating
        : rating.copyWith(createdAt: DateTime.now());

    final authUid = FirebaseAuth.instance.currentUser?.uid;
    if (authUid != null &&
        authUid.isNotEmpty &&
        (toSave.userId.isEmpty || toSave.userId != authUid)) {
      toSave = toSave.copyWith(userId: authUid);
    }

    // Keep UI snappy: persist locally first, then sync to Firestore.
    final localKey = _dedupeKey(toSave);
    spotRatings.removeWhere((r) => _dedupeKey(r) == localKey);
    spotRatings.add(toSave);
    revision.value++;
    await _persist();

    try {
      final docId = await upsertSpotRatingToFirestore(toSave);
      if (docId.isNotEmpty && docId != toSave.id) {
        final idx = spotRatings.indexWhere((r) => _dedupeKey(r) == localKey);
        if (idx >= 0) {
          spotRatings[idx] = toSave.copyWith(id: docId);
          revision.value++;
          await _persist();
        }
      }
    } catch (e) {
      debugPrint('SpotRatingsStore Firestore save failed: $e');
    }
  }

  List<SpotRating> forSpot(String spotName) {
    final key = spotName.trim().toLowerCase();
    return spotRatings
        .where((r) => r.spotName.trim().toLowerCase() == key)
        .toList()
        .reversed
        .toList();
  }

  /// Name + photo fields for the signed-in tourist (or guest fallback).
  static ({String name, String userId, String photo}) currentReviewer() {
    final auth = FirebaseAuth.instance.currentUser;
    final appUser = findAppUserByFirebaseUid(auth?.uid);
    final name = (appUser?.name.trim().isNotEmpty == true)
        ? appUser!.name.trim()
        : (auth?.displayName?.trim().isNotEmpty == true)
            ? auth!.displayName!.trim()
            : (auth?.email?.split('@').first.trim().isNotEmpty == true)
                ? auth!.email!.split('@').first.trim()
                : 'Traveler';
    final userId = auth?.uid ?? appUser?.profilePhotoLookupId ?? '';
    final photo = (appUser?.profilePhotoPath.trim().isNotEmpty == true)
        ? appUser!.profilePhotoPath.trim()
        : (auth?.photoURL?.trim() ?? '');
    return (name: name, userId: userId, photo: photo);
  }
}
