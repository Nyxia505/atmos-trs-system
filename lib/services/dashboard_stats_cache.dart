import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Cached LGU dashboard headline stats for instant paint on repeat login.
class LguDashboardStatsCache {
  const LguDashboardStatsCache({
    required this.todayCheckIns,
    required this.totalTourists,
    required this.activeSpots,
    required this.totalVrTours,
    this.municipalityName,
    this.profileName,
    this.savedAtMs,
  });

  final int todayCheckIns;
  final int totalTourists;
  final int activeSpots;
  final int totalVrTours;
  final String? municipalityName;
  final String? profileName;
  final int? savedAtMs;

  Map<String, dynamic> toJson() => {
        'todayCheckIns': todayCheckIns,
        'totalTourists': totalTourists,
        'activeSpots': activeSpots,
        'totalVrTours': totalVrTours,
        if (municipalityName != null) 'municipalityName': municipalityName,
        if (profileName != null) 'profileName': profileName,
        'savedAtMs': savedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      };

  static LguDashboardStatsCache? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return LguDashboardStatsCache(
      todayCheckIns: (json['todayCheckIns'] as num?)?.toInt() ?? 0,
      totalTourists: (json['totalTourists'] as num?)?.toInt() ?? 0,
      activeSpots: (json['activeSpots'] as num?)?.toInt() ?? 0,
      totalVrTours: (json['totalVrTours'] as num?)?.toInt() ?? 0,
      municipalityName: json['municipalityName'] as String?,
      profileName: json['profileName'] as String?,
      savedAtMs: (json['savedAtMs'] as num?)?.toInt(),
    );
  }
}

/// Cached Governor dashboard headline stats for instant paint on repeat login.
class GovernorDashboardStatsCache {
  const GovernorDashboardStatsCache({
    required this.totalTourists,
    required this.totalCheckIns,
    required this.uniqueTouristsToday,
    required this.activeSpots,
    this.profileName,
    this.savedAtMs,
  });

  final int totalTourists;
  final int totalCheckIns;
  final int uniqueTouristsToday;
  final int activeSpots;
  final String? profileName;
  final int? savedAtMs;

  Map<String, dynamic> toJson() => {
        'totalTourists': totalTourists,
        'totalCheckIns': totalCheckIns,
        'uniqueTouristsToday': uniqueTouristsToday,
        'activeSpots': activeSpots,
        if (profileName != null) 'profileName': profileName,
        'savedAtMs': savedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      };

  static GovernorDashboardStatsCache? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return GovernorDashboardStatsCache(
      totalTourists: (json['totalTourists'] as num?)?.toInt() ?? 0,
      totalCheckIns: (json['totalCheckIns'] as num?)?.toInt() ?? 0,
      uniqueTouristsToday: (json['uniqueTouristsToday'] as num?)?.toInt() ?? 0,
      activeSpots: (json['activeSpots'] as num?)?.toInt() ?? 0,
      profileName: json['profileName'] as String?,
      savedAtMs: (json['savedAtMs'] as num?)?.toInt(),
    );
  }
}

/// Persists last-known dashboard stats in SharedPreferences.
class DashboardStatsCache {
  DashboardStatsCache._();

  static String _lguKey(String? municipalityId) =>
      'lgu_dashboard_stats_${municipalityId ?? 'all'}';

  static const _governorKey = 'governor_dashboard_stats';

  static Future<LguDashboardStatsCache?> loadLgu(String? municipalityId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lguKey(municipalityId));
    if (raw == null || raw.isEmpty) return null;
    try {
      return LguDashboardStatsCache.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveLgu(
    String? municipalityId,
    LguDashboardStatsCache stats,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lguKey(municipalityId), jsonEncode(stats.toJson()));
  }

  static Future<GovernorDashboardStatsCache?> loadGovernor() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_governorKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return GovernorDashboardStatsCache.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveGovernor(GovernorDashboardStatsCache stats) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_governorKey, jsonEncode(stats.toJson()));
  }
}
