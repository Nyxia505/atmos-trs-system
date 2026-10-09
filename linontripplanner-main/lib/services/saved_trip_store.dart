import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data.dart';

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
  });

  int get spotCount =>
      daySpotNames.fold<int>(0, (sum, day) => sum + day.length);

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
        'daySpotNames': daySpotNames,
      };

  factory SavedTripPlan.fromJson(Map<String, dynamic> json) {
    final daysRaw = json['daySpotNames'];
    final days = <List<String>>[];
    if (daysRaw is List) {
      for (final d in daysRaw) {
        if (d is List) {
          days.add(d.map((e) => '$e').toList());
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
    );
  }
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
      revision.value++;
    } catch (e) {
      debugPrint('SavedTripStore load failed: $e');
    }
  }

  Future<void> _persist() async {
    await (await _sp()).setString(
      _key,
      jsonEncode(trips.map((t) => t.toJson()).toList()),
    );
  }

  Future<SavedTripPlan> save(SavedTripPlan trip) async {
    await ensureLoaded();
    trips.insert(0, trip);
    revision.value++;
    await _persist();
    return trip;
  }

  Future<void> remove(String id) async {
    await ensureLoaded();
    trips.removeWhere((t) => t.id == id);
    revision.value++;
    await _persist();
  }
}

/// Home shell listens; set to Trips tab index (2) after finishing a plan.
final ValueNotifier<int?> tourismShellTabRequest = ValueNotifier<int?>(null);
