import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint, kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../data.dart';
import '../firestore_loader.dart' show kTouristCollection;

/// Explicit repeat-visit preference for a previously visited spot.
enum RepeatVisitPreference {
  /// User has not answered yet.
  unknown,

  /// Strong positive: wants to visit again.
  yes,

  /// Soft negative: prefer other spots for now.
  no,
}

/// Local + Firestore-backed interaction signals used by home recommendations.
class SpotInteractionHistoryStore {
  SpotInteractionHistoryStore._();
  static final SpotInteractionHistoryStore instance =
      SpotInteractionHistoryStore._();

  static const _prefsKey = 'spot_repeat_visit_prefs_v1';
  static const _viewedKey = 'spot_viewed_keys_v1';
  static const _searchedKey = 'spot_searched_keys_v1';
  static const _favoritedKey = 'spot_favorited_keys_v1';
  static const _itineraryKey = 'spot_itinerary_keys_v1';

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final Map<String, RepeatVisitPreference> _repeatPrefs = {};
  final Set<String> _viewed = {};
  final Set<String> _searched = {};
  final Set<String> _favorited = {};
  final Set<String> _itinerary = {};
  final Set<String> _visitedFromVisits = {};

  Map<String, RepeatVisitPreference> get repeatPrefs =>
      Map.unmodifiable(_repeatPrefs);
  Set<String> get viewedKeys => Set.unmodifiable(_viewed);
  Set<String> get searchedKeys => Set.unmodifiable(_searched);
  Set<String> get favoritedKeys => Set.unmodifiable(_favorited);
  Set<String> get itineraryKeys => Set.unmodifiable(_itinerary);
  Set<String> get visitedKeys => Set.unmodifiable(_visitedFromVisits);

  RepeatVisitPreference preferenceFor(String spotNameOrId) {
    final key = normalizeTourismNameKey(spotNameOrId);
    return _repeatPrefs[key] ?? RepeatVisitPreference.unknown;
  }

  bool isVisited(String spotNameOrId) {
    final key = normalizeTourismNameKey(spotNameOrId);
    return _visitedFromVisits.contains(key) ||
        _itinerary.contains(key) ||
        _viewed.contains(key) && _repeatPrefs.containsKey(key);
  }

  /// True when we should ask "visit again?" (visited, no answer yet).
  bool shouldAskVisitAgain(TouristSpot spot) {
    final key = normalizeTourismNameKey(spot.name);
    final visited = _visitedFromVisits.contains(key) ||
        _itinerary.contains(key);
    if (!visited) return false;
    return preferenceFor(spot.name) == RepeatVisitPreference.unknown;
  }

  Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    _repeatPrefs
      ..clear()
      ..addAll(_decodePrefs(sp.getString(_prefsKey)));
    _viewed
      ..clear()
      ..addAll(sp.getStringList(_viewedKey) ?? const []);
    _searched
      ..clear()
      ..addAll(sp.getStringList(_searchedKey) ?? const []);
    _favorited
      ..clear()
      ..addAll(sp.getStringList(_favoritedKey) ?? const []);
    _itinerary
      ..clear()
      ..addAll(sp.getStringList(_itineraryKey) ?? const []);

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection(kTouristCollection)
            .doc(uid)
            .get();
        if (doc.exists) {
          _mergeFirestoreTouristDoc(doc.data() ?? {});
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('SpotInteractionHistoryStore load tourist: $e');
        }
      }
      try {
        await _loadTouristVisits(uid);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('SpotInteractionHistoryStore load visits: $e');
        }
      }
    }
    revision.value++;
  }

  /// Drops in-memory signals on logout so the next account starts clean.
  /// SharedPreferences stay put; [load] reloads them for the next session.
  void clearMemoryForLogout() {
    _repeatPrefs.clear();
    _viewed.clear();
    _searched.clear();
    _favorited.clear();
    _itinerary.clear();
    _visitedFromVisits.clear();
    revision.value++;
  }

  void _mergeFirestoreTouristDoc(Map<String, dynamic> d) {
    final raw = d['repeatVisitPreferences'] ?? d['repeat_visit_preferences'];
    if (raw is Map) {
      for (final e in raw.entries) {
        final key = normalizeTourismNameKey(e.key.toString());
        if (key.isEmpty) continue;
        final v = e.value.toString().toLowerCase().trim();
        if (v == 'yes' || v == 'visit_again' || v == 'true') {
          _repeatPrefs[key] = RepeatVisitPreference.yes;
        } else if (v == 'no' || v == 'skip' || v == 'false') {
          _repeatPrefs[key] = RepeatVisitPreference.no;
        }
      }
    }
    void addList(dynamic raw, Set<String> target) {
      if (raw is! List) return;
      for (final item in raw) {
        final s = item.toString().trim();
        if (s.isEmpty) continue;
        target.add(normalizeTourismNameKey(s));
      }
    }

    addList(d['viewedSpotKeys'] ?? d['viewed_spot_keys'], _viewed);
    addList(d['favoritedSpotKeys'] ?? d['favorited_spot_keys'], _favorited);
    addList(d['itinerarySpotKeys'] ?? d['itinerary_spot_keys'], _itinerary);
    addList(d['visitedSpotKeys'] ?? d['visited_spot_keys'], _visitedFromVisits);
  }

  Future<void> _loadTouristVisits(String uid) async {
    final snap = await FirebaseFirestore.instance
        .collection('tourist_visits')
        .where('firebaseUid', isEqualTo: uid)
        .limit(100)
        .get();
    for (final doc in snap.docs) {
      final d = doc.data();
      for (final key in const [
        'spotName',
        'spot_name',
        'touristSpotName',
        'name',
        'spotId',
        'spot_id',
      ]) {
        final v = d[key];
        if (v == null) continue;
        final s = v.toString().trim();
        if (s.isEmpty) continue;
        _visitedFromVisits.add(normalizeTourismNameKey(s));
        break;
      }
    }
  }

  Future<void> setRepeatVisitPreference({
    required TouristSpot spot,
    required bool visitAgain,
  }) async {
    final key = normalizeTourismNameKey(spot.name);
    if (key.isEmpty) return;
    _repeatPrefs[key] = visitAgain
        ? RepeatVisitPreference.yes
        : RepeatVisitPreference.no;
    _visitedFromVisits.add(key);

    final sp = await SharedPreferences.getInstance();
    await sp.setString(_prefsKey, _encodePrefs(_repeatPrefs));

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        final prefValue = visitAgain ? 'yes' : 'no';
        await FirebaseFirestore.instance
            .collection(kTouristCollection)
            .doc(uid)
            .set({
          'repeatVisitPreferences': {key: prefValue},
          'visitedSpotKeys': FieldValue.arrayUnion([key]),
          'spotInteractionHistory': FieldValue.arrayUnion([
            {
              'spotKey': key,
              'spotId': spot.firestoreDocId ?? '',
              'spotName': spot.name,
              'interactionType':
                  visitAgain ? 'repeat_visit_yes' : 'repeat_visit_no',
              'visited': true,
              'repeatVisitPreference': prefValue,
              'timestamp': DateTime.now().toUtc().toIso8601String(),
            },
          ]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('setRepeatVisitPreference Firestore: $e');
        }
      }
    }
    revision.value++;
  }

  Future<void> recordViewed(TouristSpot spot) async {
    final key = normalizeTourismNameKey(spot.name);
    if (key.isEmpty || !_viewed.add(key)) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_viewedKey, _viewed.toList());
    revision.value++;
  }

  Future<void> recordSearchedNames(Iterable<String> names) async {
    var changed = false;
    for (final n in names) {
      final key = normalizeTourismNameKey(n);
      if (key.isEmpty) continue;
      if (_searched.add(key)) changed = true;
    }
    if (!changed) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_searchedKey, _searched.toList());
    revision.value++;
  }

  Future<void> recordFavorited(TouristSpot spot, {required bool favorited}) async {
    final key = normalizeTourismNameKey(spot.name);
    if (key.isEmpty) return;
    if (favorited) {
      _favorited.add(key);
    } else {
      _favorited.remove(key);
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_favoritedKey, _favorited.toList());
    revision.value++;
  }

  Future<void> recordItinerarySpots(Iterable<TouristSpot> spots) async {
    var changed = false;
    for (final s in spots) {
      final key = normalizeTourismNameKey(s.name);
      if (key.isEmpty) continue;
      if (_itinerary.add(key)) changed = true;
      _visitedFromVisits.add(key);
    }
    if (!changed) return;
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_itineraryKey, _itinerary.toList());
    revision.value++;
  }

  /// Merge registration / CF visited spot keys (name-normalized).
  void mergeVisitedKeys(Iterable<String> keys) {
    var changed = false;
    for (final raw in keys) {
      final key = normalizeTourismNameKey(raw);
      if (key.isEmpty) continue;
      if (_visitedFromVisits.add(key)) changed = true;
    }
    if (changed) revision.value++;
  }

  static Map<String, RepeatVisitPreference> _decodePrefs(String? raw) {
    final out = <String, RepeatVisitPreference>{};
    if (raw == null || raw.isEmpty) return out;
    for (final part in raw.split('|')) {
      final bits = part.split('=');
      if (bits.length != 2) continue;
      final key = bits[0].trim();
      if (key.isEmpty) continue;
      final v = bits[1].trim();
      out[key] = v == 'yes'
          ? RepeatVisitPreference.yes
          : v == 'no'
              ? RepeatVisitPreference.no
              : RepeatVisitPreference.unknown;
    }
    return out;
  }

  static String _encodePrefs(Map<String, RepeatVisitPreference> map) {
    return map.entries
        .where((e) => e.value != RepeatVisitPreference.unknown)
        .map((e) =>
            '${e.key}=${e.value == RepeatVisitPreference.yes ? 'yes' : 'no'}')
        .join('|');
  }
}
