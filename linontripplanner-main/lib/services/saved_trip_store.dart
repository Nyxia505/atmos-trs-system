import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data.dart';

/// Finished plans from Plan my trip → Finish.
const String kTouristTripCollection = 'tourist_trip';

/// One finished trip plan saved from Plan my trip → Finish.
class SavedTripPlan {
  final String id;
  final DateTime createdAt;
  final String startName;
  final String endName;
  final DateTime? arrivalDate;
  final DateTime? departureDate;
  final int tripDays;
  final int travelers;
  final String transportMode;
  final double budgetPhp;
  final int estimatedTotalPhp;
  /// Spot names per day (resolve via [allSpots] when displaying).
  final List<List<String>> daySpotNames;

  /// `coastal` or `highland` only when the tourist selected that route.
  /// Empty when the choice was not stored. Analytics must not infer it.
  final String routeType;

  const SavedTripPlan({
    required this.id,
    required this.createdAt,
    required this.startName,
    required this.endName,
    required this.arrivalDate,
    required this.departureDate,
    required this.tripDays,
    required this.travelers,
    required this.transportMode,
    required this.budgetPhp,
    required this.estimatedTotalPhp,
    required this.daySpotNames,
    this.routeType = '',
  });

  int get spotCount =>
      daySpotNames.fold<int>(0, (sum, day) => sum + day.length);

  /// Where [dayIndex] begins: the trip start, or the previous day's last spot.
  String _startsFrom(int dayIndex) {
    if (dayIndex <= 0) return startName;
    for (var d = dayIndex - 1; d >= 0; d--) {
      if (d < daySpotNames.length && daySpotNames[d].isNotEmpty) {
        return daySpotNames[d].last;
      }
    }
    return startName;
  }

  List<List<TouristSpot>> resolveDays() {
    return [
      for (final day in daySpotNames)
        [
          for (final name in day)
            if (findTouristSpotByNameFuzzy(name) != null)
              findTouristSpotByNameFuzzy(name)!,
        ],
    ];
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'startName': startName,
        'endName': endName,
        'arrivalDate': arrivalDate?.toIso8601String(),
        'departureDate': departureDate?.toIso8601String(),
        'tripDays': tripDays,
        'travelers': travelers,
        'transportMode': transportMode,
        'budgetPhp': budgetPhp,
        'estimatedTotalPhp': estimatedTotalPhp,
        if (routeType == 'coastal' || routeType == 'highland')
          'routeType': routeType,
        // Firestore rejects nested arrays, so each day is a map.
        // [startsFrom] is the previous day's last spot (the trip start on day 1).
        'daySpotNames': [
          for (var i = 0; i < daySpotNames.length; i++)
            {'spots': daySpotNames[i], 'startsFrom': _startsFrom(i)},
        ],
      };

  factory SavedTripPlan.fromJson(Map<String, dynamic> json) {
    final daysRaw = json['daySpotNames'];
    final days = <List<String>>[];
    if (daysRaw is List) {
      for (final d in daysRaw) {
        if (d is List) {
          days.add(d.map((e) => '$e').toList());
        } else if (d is Map) {
          final spots = d['spots'];
          if (spots is List) {
            days.add(spots.map((e) => '$e').toList());
          }
        }
      }
    }
    return SavedTripPlan(
      id: '${json['id'] ?? ''}',
      createdAt: DateTime.tryParse('${json['createdAt']}') ?? DateTime.now(),
      startName: '${json['startName'] ?? ''}',
      endName: '${json['endName'] ?? ''}',
      arrivalDate: DateTime.tryParse('${json['arrivalDate'] ?? ''}'),
      departureDate: DateTime.tryParse('${json['departureDate'] ?? ''}'),
      tripDays: (json['tripDays'] as num?)?.toInt() ?? days.length,
      travelers: (json['travelers'] as num?)?.toInt() ?? 1,
      transportMode: '${json['transportMode'] ?? 'Public Transport'}',
      budgetPhp: (json['budgetPhp'] as num?)?.toDouble() ?? 0,
      estimatedTotalPhp: (json['estimatedTotalPhp'] as num?)?.toInt() ?? 0,
      daySpotNames: days,
      routeType: _storedRouteType(json),
    );
  }
}

/// Only a route type the tourist actually chose. Never inferred.
String _storedRouteType(Map<String, dynamic> json) {
  for (final key in const ['routeType', 'routeDirection', 'direction']) {
    final value = '${json[key] ?? ''}'.trim().toLowerCase();
    if (value == 'coastal' || value == 'highland') return value;
  }
  return '';
}

/// Persists finished trips and notifies the Trips tab.
class SavedTripStore {
  SavedTripStore._();
  static final SavedTripStore instance = SavedTripStore._();

  static const _key = 'saved_trip_plans_v1';

  SharedPreferences? _prefs;
  bool _loaded = false;
  final List<SavedTripPlan> trips = [];
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Future<SharedPreferences> _sp() async =>
      _prefs ??= await SharedPreferences.getInstance();

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = (await _sp()).getString(_key);
      if (raw == null || raw.isEmpty) return;
      final list = jsonDecode(raw) as List<dynamic>;
      trips
        ..clear()
        ..addAll(
          list.whereType<Map>().map(
                (e) => SavedTripPlan.fromJson(Map<String, dynamic>.from(e)),
              ),
        );
      await _mergeFromFirestore();
      revision.value++;
    } catch (e) {
      debugPrint('SavedTripStore load failed: $e');
    }
  }

  Future<void> _mergeFromFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    final snap = await FirebaseFirestore.instance
        .collection(kTouristTripCollection)
        .where('touristId', isEqualTo: uid)
        .get();
    final ids = trips.map((t) => t.id).toSet();
    for (final doc in snap.docs) {
      final trip = SavedTripPlan.fromJson(doc.data());
      if (trip.id.isEmpty || !ids.add(trip.id)) continue;
      trips.add(trip);
    }
    trips.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> _writeFirestore(SavedTripPlan trip) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('Sign in to save your trip.');
    }
    final id = trip.id.trim().isEmpty
        ? FirebaseFirestore.instance.collection(kTouristTripCollection).doc().id
        : trip.id.trim();
    await FirebaseFirestore.instance
        .collection(kTouristTripCollection)
        .doc(id)
        .set({
      ...trip.toJson(),
      'id': id,
      'touristId': uid,
    });
  }

  Future<void> _persist() async {
    await (await _sp()).setString(
      _key,
      jsonEncode(trips.map((t) => t.toJson()).toList()),
    );
  }

  Future<SavedTripPlan> save(SavedTripPlan trip) async {
    await _writeFirestore(trip);
    await ensureLoaded();
    trips.removeWhere((t) => t.id == trip.id);
    trips.insert(0, trip);
    revision.value++;
    await _persist();
    return trip;
  }

  Future<void> remove(String id) async {
    await ensureLoaded();
    final existing = trips.where((t) => t.id == id).toList();
    trips.removeWhere((t) => t.id == id);
    revision.value++;
    await _persist();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty || existing.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection(kTouristTripCollection)
          .doc(id)
          .delete();
    } catch (e) {
      debugPrint('SavedTripStore firebase remove failed: $e');
    }
  }
}

/// Home shell listens; set to Trips tab index (2) after finishing a plan.
final ValueNotifier<int?> tourismShellTabRequest = ValueNotifier<int?>(null);
