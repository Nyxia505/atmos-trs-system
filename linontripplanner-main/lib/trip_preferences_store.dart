import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists trip-planner choices and lightweight behavior signals for personalization.
class TripPreferencesStore {
  TripPreferencesStore._();
  static final TripPreferencesStore instance = TripPreferencesStore._();

  static const _keyInterestWeights = 'trip_interest_weights';
  static const _keyLastTransport = 'trip_last_transport';
  static const _keyLastInterests = 'trip_last_interests';
  static const _keyLastBudgetTier = 'trip_last_budget_tier';
  static const _keyTrackedEventIds = 'trip_tracked_event_ids';
  static const _keyRatedSpotTypes = 'trip_rated_spot_types';

  SharedPreferences? _prefs;

  Future<SharedPreferences> _sp() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<Map<String, double>> loadInterestWeights() async {
    final raw = (await _sp()).getString(_keyInterestWeights);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (k, v) => MapEntry(k, (v is num) ? v.toDouble() : 0.0),
      );
    } catch (_) {
      return {};
    }
  }

  Future<void> recordTripInputs({
    required String transportMode,
    required List<String> interests,
    required String budgetTierName,
  }) async {
    final sp = await _sp();
    await sp.setString(_keyLastTransport, transportMode);
    await sp.setStringList(_keyLastInterests, interests);
    await sp.setString(_keyLastBudgetTier, budgetTierName);

    final weights = await loadInterestWeights();
    for (final interest in interests) {
      weights[interest] = (weights[interest] ?? 0) + 1.0;
    }
    await sp.setString(_keyInterestWeights, jsonEncode(weights));
  }

  Future<void> recordSpotRating(String spotType, double rating) async {
    if (spotType.isEmpty || rating < 3.5) return;
    final sp = await _sp();
    final raw = sp.getString(_keyRatedSpotTypes);
    final counts = <String, int>{};
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final e in decoded.entries) {
          counts[e.key] = (e.value as num?)?.toInt() ?? 0;
        }
      } catch (_) {}
    }
    counts[spotType] = (counts[spotType] ?? 0) + 1;
    await sp.setString(_keyRatedSpotTypes, jsonEncode(counts));
  }

  Future<Map<String, int>> loadRatedSpotTypeCounts() async {
    final raw = (await _sp()).getString(_keyRatedSpotTypes);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0));
    } catch (_) {
      return {};
    }
  }

  Future<String?> loadLastTransport() async =>
      (await _sp()).getString(_keyLastTransport);

  Future<List<String>> loadLastInterests() async =>
      (await _sp()).getStringList(_keyLastInterests) ?? [];

  Future<String?> loadLastBudgetTier() async =>
      (await _sp()).getString(_keyLastBudgetTier);

  Future<Set<String>> loadTrackedEventIds() async {
    final list = (await _sp()).getStringList(_keyTrackedEventIds) ?? [];
    return list.toSet();
  }

  Future<void> setEventTracked(String eventId, bool tracked) async {
    final sp = await _sp();
    final ids = await loadTrackedEventIds();
    if (tracked) {
      ids.add(eventId);
    } else {
      ids.remove(eventId);
    }
    await sp.setStringList(_keyTrackedEventIds, ids.toList());
  }

  Future<bool> isEventTracked(String eventId) async {
    final ids = await loadTrackedEventIds();
    return ids.contains(eventId);
  }

  static const _keyRouteStart = 'trip_last_route_start';
  static const _keyRouteEnd = 'trip_last_route_end';
  static const _keyRouteAlong = 'trip_last_route_along';

  Future<void> recordRouteContext({
    String? startMunicipality,
    String? endMunicipality,
    List<String> alongMunicipalities = const [],
  }) async {
    final sp = await _sp();
    if (startMunicipality != null) {
      await sp.setString(_keyRouteStart, startMunicipality.trim());
    }
    if (endMunicipality != null) {
      await sp.setString(_keyRouteEnd, endMunicipality.trim());
    }
    if (alongMunicipalities.isNotEmpty) {
      await sp.setStringList(
        _keyRouteAlong,
        alongMunicipalities.map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      );
    }
  }

  Future<({String? start, String? end, List<String> along})>
      loadRouteContext() async {
    final sp = await _sp();
    return (
      start: sp.getString(_keyRouteStart),
      end: sp.getString(_keyRouteEnd),
      along: sp.getStringList(_keyRouteAlong) ?? const <String>[],
    );
  }
}
