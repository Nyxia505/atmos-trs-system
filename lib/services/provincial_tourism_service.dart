import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/services/governor_firestore_service.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/production_data_filters.dart';
import 'package:atmos_trs_system/utils/provincial_report_builder.dart';

/// Severity for operational quality alerts.
enum ProvincialAlertSeverity { info, warning, critical }

class ProvincialAlert {
  const ProvincialAlert({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    this.municipalityId,
  });

  final String id;
  final String title;
  final String message;
  final ProvincialAlertSeverity severity;
  final String? municipalityId;
}

class ProvincialMunicipalityStats {
  const ProvincialMunicipalityStats({
    required this.id,
    required this.name,
    required this.arrivals,
    required this.previousArrivals,
    required this.spotCount,
    required this.activeSpotCount,
    required this.uniqueVisitors,
  });

  final String id;
  final String name;
  final int arrivals;
  final int previousArrivals;
  final int spotCount;
  final int activeSpotCount;
  final int uniqueVisitors;

  double get growthPercent {
    if (previousArrivals <= 0) {
      return arrivals > 0 ? 100.0 : 0.0;
    }
    return ((arrivals - previousArrivals) / previousArrivals) * 100.0;
  }

  bool get hasZeroActivity => arrivals == 0;
  bool get isUnderperforming => arrivals == 0 || growthPercent <= -25;
}

class ProvincialTourismSnapshot {
  const ProvincialTourismSnapshot({
    required this.tourists,
    required this.checkIns,
    required this.spots,
    required this.announcements,
    required this.campaigns,
    required this.loadWarnings,
  });

  final List<Map<String, dynamic>> tourists;
  final List<Map<String, dynamic>> checkIns;
  final List<Map<String, dynamic>> spots;
  final List<Map<String, dynamic>> announcements;
  final List<Map<String, dynamic>> campaigns;
  final List<String> loadWarnings;
}

/// Province-wide tourism ops data for the Provincial Tourism Office dashboard.
class ProvincialTourismService {
  ProvincialTourismService({
    FirebaseFirestore? firestore,
    GovernorFirestoreService? governorService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _governor = governorService ?? GovernorFirestoreService();

  final FirebaseFirestore _firestore;
  final GovernorFirestoreService _governor;

  static const _ackPrefsKey = 'provincial_tourism_alert_acks';

  Future<ProvincialTourismSnapshot> loadSnapshot({
    bool includeCheckIns = true,
  }) async {
    final gov = await _governor.loadProvincialSnapshotCacheFirst(
      includeCheckIns: includeCheckIns,
    );
    final campaigns = await loadCampaigns();
    return ProvincialTourismSnapshot(
      tourists: ProductionDataFilters.realTourists(gov.tourists),
      checkIns: ProductionDataFilters.realCheckIns(gov.checkIns),
      spots: gov.touristSpots,
      announcements: gov.announcements,
      campaigns: campaigns,
      loadWarnings: gov.loadWarnings,
    );
  }

  Future<List<Map<String, dynamic>>> loadCampaigns() async {
    try {
      final snap = await _firestore
          .collection('provincial_campaigns')
          .orderBy('updatedAt', descending: true)
          .get();
      return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      debugPrint('[ProvincialTourism] campaigns orderBy: $e');
      try {
        final snap =
            await _firestore.collection('provincial_campaigns').get();
        final list =
            snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
        list.sort((a, b) {
          final ta = _asDate(a['updatedAt']) ?? _asDate(a['createdAt']);
          final tb = _asDate(b['updatedAt']) ?? _asDate(b['createdAt']);
          if (ta == null && tb == null) return 0;
          if (ta == null) return 1;
          if (tb == null) return -1;
          return tb.compareTo(ta);
        });
        return list;
      } catch (e2) {
        debugPrint('[ProvincialTourism] campaigns: $e2');
        return const [];
      }
    }
  }

  Future<String?> saveCampaign({
    String? id,
    required String title,
    required DateTime start,
    required DateTime end,
    required List<String> targetMunicipalityIds,
    required String status,
    String? description,
  }) async {
    final payload = <String, dynamic>{
      'title': title.trim(),
      'description': (description ?? '').trim(),
      'startDate': Timestamp.fromDate(DateTime(start.year, start.month, start.day)),
      'endDate': Timestamp.fromDate(DateTime(end.year, end.month, end.day)),
      'targetMunicipalityIds': targetMunicipalityIds,
      'status': status.trim().toLowerCase(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    try {
      if (id == null || id.isEmpty) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        final ref =
            await _firestore.collection('provincial_campaigns').add(payload);
        return ref.id;
      }
      await _firestore.collection('provincial_campaigns').doc(id).set(
            payload,
            SetOptions(merge: true),
          );
      return id;
    } catch (e) {
      debugPrint('[ProvincialTourism] saveCampaign: $e');
      return null;
    }
  }

  Future<bool> setDestinationFeatured({
    required String spotId,
    required bool featured,
  }) async {
    if (spotId.isEmpty) return false;
    try {
      await _firestore.collection('tourist_spots').doc(spotId).set({
        'provincialFeatured': featured,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    } catch (e) {
      debugPrint('[ProvincialTourism] setDestinationFeatured: $e');
      return false;
    }
  }

  static DateTime? _asDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static ({DateTime start, DateTime end, DateTime prevStart, DateTime prevEnd})
      rangeForFilter(String filter) {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    late DateTime start;
    late DateTime prevStart;
    late DateTime prevEnd;
    switch (filter) {
      case 'This Week':
        final weekday = now.weekday; // Mon=1
        start = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: weekday - 1));
        prevEnd = start.subtract(const Duration(milliseconds: 1));
        prevStart = prevEnd.subtract(const Duration(days: 6));
        prevStart = DateTime(prevStart.year, prevStart.month, prevStart.day);
        break;
      case 'This Year':
        start = DateTime(now.year, 1, 1);
        prevStart = DateTime(now.year - 1, 1, 1);
        prevEnd = DateTime(now.year - 1, 12, 31, 23, 59, 59, 999);
        break;
      case 'This Month':
      default:
        start = DateTime(now.year, now.month, 1);
        final prevMonth = DateTime(now.year, now.month - 1, 1);
        prevStart = prevMonth;
        prevEnd = DateTime(now.year, now.month, 0, 23, 59, 59, 999);
        break;
    }
    return (start: start, end: end, prevStart: prevStart, prevEnd: prevEnd);
  }

  static List<Map<String, dynamic>> checkInsInRange(
    List<Map<String, dynamic>> checkIns,
    DateTime start,
    DateTime end,
  ) =>
      filterCheckInsInDateRange(checkIns, start, end);

  static String municipalityIdOf(Map<String, dynamic> row) {
    final mid = row['municipalityId']?.toString().trim() ?? '';
    if (mid.isNotEmpty && isMisamisOccidentalMunicipalityId(mid)) return mid;
    final fromName = getMunicipalityIdFromName(
      row['municipality']?.toString() ?? row['city']?.toString(),
    );
    return fromName;
  }

  static String municipalityNameOf(String id) {
    for (final m in getMisamisOccidentalMunicipalities()) {
      if (m.id == id) return m.name;
    }
    return id.isEmpty ? 'Unassigned' : id;
  }

  static List<ProvincialMunicipalityStats> municipalityPerformance({
    required List<Map<String, dynamic>> checkIns,
    required List<Map<String, dynamic>> spots,
    required String timeFilter,
  }) {
    final range = rangeForFilter(timeFilter);
    final current = checkInsInRange(checkIns, range.start, range.end);
    final previous =
        checkInsInRange(checkIns, range.prevStart, range.prevEnd);

    final arrivals = <String, int>{};
    final prevArrivals = <String, int>{};
    final unique = <String, Set<String>>{};
    final spotCounts = <String, int>{};
    final activeSpotCounts = <String, int>{};

    for (final m in getMisamisOccidentalMunicipalities()) {
      arrivals[m.id] = 0;
      prevArrivals[m.id] = 0;
      unique[m.id] = <String>{};
      spotCounts[m.id] = 0;
      activeSpotCounts[m.id] = 0;
    }

    for (final s in spots) {
      final id = municipalityIdOf(s);
      if (id.isEmpty || !spotCounts.containsKey(id)) continue;
      spotCounts[id] = (spotCounts[id] ?? 0) + 1;
      final status = (s['status']?.toString() ?? 'active').toLowerCase();
      final active = status != 'inactive' && status != 'closed';
      if (active) {
        activeSpotCounts[id] = (activeSpotCounts[id] ?? 0) + 1;
      }
    }

    void ingest(List<Map<String, dynamic>> rows, Map<String, int> bucket,
        {bool trackUnique = false}) {
      for (final c in rows) {
        final id = municipalityIdOf(c);
        if (id.isEmpty || !bucket.containsKey(id)) continue;
        bucket[id] = (bucket[id] ?? 0) + 1;
        if (trackUnique) {
          final uid = GovernorFirestoreService.checkInUserId(c);
          if (uid.isNotEmpty) unique[id]!.add(uid);
        }
      }
    }

    ingest(current, arrivals, trackUnique: true);
    ingest(previous, prevArrivals);

    final list = getMisamisOccidentalMunicipalities()
        .map(
          (m) => ProvincialMunicipalityStats(
            id: m.id,
            name: m.name,
            arrivals: arrivals[m.id] ?? 0,
            previousArrivals: prevArrivals[m.id] ?? 0,
            spotCount: spotCounts[m.id] ?? 0,
            activeSpotCount: activeSpotCounts[m.id] ?? 0,
            uniqueVisitors: unique[m.id]?.length ?? 0,
          ),
        )
        .toList()
      ..sort((a, b) => b.arrivals.compareTo(a.arrivals));
    return list;
  }

  static int pendingEventsCount(List<Map<String, dynamic>> announcements) {
    return announcements.where((a) {
      final status = (a['status']?.toString() ?? '').toLowerCase();
      return status == 'pending' || status == 'submitted' || status == 'review';
    }).length;
  }

  static List<ProvincialAlert> buildAlerts({
    required List<Map<String, dynamic>> checkIns,
    required List<Map<String, dynamic>> spots,
    required List<Map<String, dynamic>> announcements,
    required String timeFilter,
    required Set<String> acknowledgedIds,
  }) {
    final alerts = <ProvincialAlert>[];
    final perf = municipalityPerformance(
      checkIns: checkIns,
      spots: spots,
      timeFilter: timeFilter,
    );

    for (final m in perf) {
      if (m.hasZeroActivity) {
        alerts.add(
          ProvincialAlert(
            id: 'zero_${m.id}',
            title: 'No check-ins: ${m.name}',
            message:
                'This LGU has zero arrivals in the selected period.',
            severity: ProvincialAlertSeverity.warning,
            municipalityId: m.id,
          ),
        );
      } else if (m.growthPercent <= -40) {
        alerts.add(
          ProvincialAlert(
            id: 'drop_${m.id}',
            title: 'Arrival drop: ${m.name}',
            message:
                'Arrivals are down ${m.growthPercent.abs().toStringAsFixed(0)}% vs prior period.',
            severity: ProvincialAlertSeverity.critical,
            municipalityId: m.id,
          ),
        );
      }
    }

    for (final s in spots) {
      final id = s['id']?.toString() ?? '';
      final name = s['name']?.toString() ?? 'Spot';
      final qr = s['qrCode']?.toString() ??
          s['qrPayload']?.toString() ??
          s['qrData']?.toString() ??
          '';
      final hasQr = qr.trim().isNotEmpty ||
          (s['hasQr'] == true) ||
          (s['qrGenerated'] == true);
      if (!hasQr && id.isNotEmpty) {
        alerts.add(
          ProvincialAlert(
            id: 'qr_$id',
            title: 'Missing QR: $name',
            message: 'Spot may be missing a check-in QR code.',
            severity: ProvincialAlertSeverity.info,
            municipalityId: municipalityIdOf(s),
          ),
        );
        // Cap QR-missing noise so the badge stays actionable.
        if (alerts.where((a) => a.id.startsWith('qr_')).length >= 5) break;
      }
    }

    final now = DateTime.now();
    for (final a in announcements) {
      final status = (a['status']?.toString() ?? '').toLowerCase();
      if (status != 'pending' && status != 'submitted' && status != 'review') {
        continue;
      }
      final created = _asDate(a['createdAt']) ?? _asDate(a['submittedAt']);
      if (created == null) continue;
      final days = now.difference(created).inDays;
      if (days >= 3) {
        final id = a['id']?.toString() ?? created.millisecondsSinceEpoch.toString();
        alerts.add(
          ProvincialAlert(
            id: 'event_$id',
            title: 'Event pending ${days}d',
            message: a['title']?.toString() ?? 'LGU event awaiting review',
            severity: days >= 7
                ? ProvincialAlertSeverity.critical
                : ProvincialAlertSeverity.warning,
          ),
        );
      }
    }

    return alerts.where((a) => !acknowledgedIds.contains(a.id)).toList();
  }

  static Future<Set<String>> loadAcknowledgedAlertIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_ackPrefsKey) ?? const []).toSet();
  }

  static Future<void> acknowledgeAlert(String id) async {
    if (id.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_ackPrefsKey) ?? <String>[];
    if (current.contains(id)) return;
    current.add(id);
    await prefs.setStringList(_ackPrefsKey, current);
  }

  static Map<String, int> localForeignCounts(
    List<Map<String, dynamic>> tourists,
  ) {
    var local = 0;
    var foreign = 0;
    for (final t in tourists) {
      final type = (t['touristType'] ??
              t['visitorType'] ??
              t['nationalityType'] ??
              '')
          .toString()
          .toLowerCase();
      final nationality =
          (t['nationality'] ?? t['country'] ?? '').toString().toLowerCase();
      final isForeign = type.contains('foreign') ||
          type.contains('intl') ||
          (nationality.isNotEmpty &&
              nationality != 'ph' &&
              nationality != 'philippines' &&
              nationality != 'filipino');
      if (isForeign) {
        foreign++;
      } else {
        local++;
      }
    }
    return {'local': local, 'foreign': foreign};
  }

  static Map<String, int> genderCounts(List<Map<String, dynamic>> tourists) {
    var male = 0;
    var female = 0;
    var others = 0;
    for (final t in tourists) {
      final g = (t['gender'] ?? t['sex'] ?? '').toString().toLowerCase();
      if (g.startsWith('m')) {
        male++;
      } else if (g.startsWith('f')) {
        female++;
      } else {
        others++;
      }
    }
    return {'male': male, 'female': female, 'others': others};
  }

  static List<({String label, int count})> ageBands(
    List<Map<String, dynamic>> tourists,
  ) {
    final bands = <String, int>{
      '0-17': 0,
      '18-24': 0,
      '25-34': 0,
      '35-44': 0,
      '45-54': 0,
      '55+': 0,
      'Unknown': 0,
    };
    for (final t in tourists) {
      final ageRaw = t['age'];
      int? age;
      if (ageRaw is int) {
        age = ageRaw;
      } else if (ageRaw is num) {
        age = ageRaw.toInt();
      } else {
        age = int.tryParse(ageRaw?.toString() ?? '');
      }
      if (age == null) {
        bands['Unknown'] = (bands['Unknown'] ?? 0) + 1;
      } else if (age < 18) {
        bands['0-17'] = (bands['0-17'] ?? 0) + 1;
      } else if (age <= 24) {
        bands['18-24'] = (bands['18-24'] ?? 0) + 1;
      } else if (age <= 34) {
        bands['25-34'] = (bands['25-34'] ?? 0) + 1;
      } else if (age <= 44) {
        bands['35-44'] = (bands['35-44'] ?? 0) + 1;
      } else if (age <= 54) {
        bands['45-54'] = (bands['45-54'] ?? 0) + 1;
      } else {
        bands['55+'] = (bands['55+'] ?? 0) + 1;
      }
    }
    return bands.entries.map((e) => (label: e.key, count: e.value)).toList();
  }

  static List<({String name, int count})> topDestinations({
    required List<Map<String, dynamic>> checkIns,
    required List<Map<String, dynamic>> spots,
    int limit = 8,
  }) {
    final bySpot = <String, int>{};
    final names = <String, String>{
      for (final s in spots)
        (s['id']?.toString() ?? ''): (s['name']?.toString() ?? 'Spot'),
    };
    for (final c in checkIns) {
      final sid = c['spotId']?.toString() ??
          c['touristSpotId']?.toString() ??
          c['spot_id']?.toString() ??
          '';
      final name = names[sid] ??
          c['spotName']?.toString() ??
          c['touristSpotName']?.toString() ??
          'Unknown spot';
      final key = sid.isNotEmpty ? sid : name;
      bySpot[key] = (bySpot[key] ?? 0) + 1;
      names.putIfAbsent(key, () => name);
    }
    final sorted = bySpot.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .take(limit)
        .map((e) => (name: names[e.key] ?? e.key, count: e.value))
        .toList();
  }

  static List<double> arrivalsSparkline(
    List<Map<String, dynamic>> checkIns, {
    int days = 7,
  }) {
    final now = DateTime.now();
    final counts = List<double>.filled(days, 0);
    for (final c in checkIns) {
      final t = GovernorFirestoreService.parseCheckInTime(c);
      if (t == null) continue;
      final day = DateTime(t.year, t.month, t.day);
      final diff = DateTime(now.year, now.month, now.day).difference(day).inDays;
      if (diff < 0 || diff >= days) continue;
      counts[days - 1 - diff] += 1;
    }
    return counts;
  }

  static List<({DateTime day, int count})> arrivalsByDay(
    List<Map<String, dynamic>> checkIns, {
    int days = 14,
  }) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: days - 1));
    final map = <DateTime, int>{};
    for (var i = 0; i < days; i++) {
      map[start.add(Duration(days: i))] = 0;
    }
    for (final c in checkIns) {
      final t = GovernorFirestoreService.parseCheckInTime(c);
      if (t == null) continue;
      final day = DateTime(t.year, t.month, t.day);
      if (!map.containsKey(day)) continue;
      map[day] = (map[day] ?? 0) + 1;
    }
    return map.entries.map((e) => (day: e.key, count: e.value)).toList()
      ..sort((a, b) => a.day.compareTo(b.day));
  }

  static int peakHour(List<Map<String, dynamic>> checkIns) {
    final hours = List<int>.filled(24, 0);
    for (final c in checkIns) {
      final t = GovernorFirestoreService.parseCheckInTime(c);
      if (t == null) continue;
      hours[t.hour] += 1;
    }
    var peak = 0;
    for (var i = 1; i < 24; i++) {
      if (hours[i] > hours[peak]) peak = i;
    }
    return peak;
  }

  static ({int returning, int firstTimers}) returningVsNew(
    List<Map<String, dynamic>> checkIns,
  ) {
    final counts = <String, int>{};
    for (final c in checkIns) {
      final uid = GovernorFirestoreService.checkInUserId(c);
      if (uid.isEmpty) continue;
      counts[uid] = (counts[uid] ?? 0) + 1;
    }
    var returning = 0;
    var first = 0;
    for (final n in counts.values) {
      if (n > 1) {
        returning++;
      } else {
        first++;
      }
    }
    return (returning: returning, firstTimers: first);
  }
}
