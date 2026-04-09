import 'dart:collection';

import 'package:atmos_trs_system/data/mock_qr_spots.dart';
import 'package:atmos_trs_system/models/qr_tourist_spot.dart';
import 'package:atmos_trs_system/models/visit_record.dart';

/// Local, in-memory QR check-in service used for mock data and analytics.
class LocalQRSpotCheckInService {
  LocalQRSpotCheckInService._internal();

  static final LocalQRSpotCheckInService instance =
      LocalQRSpotCheckInService._internal();

  final List<VisitRecord> _visits = [];

  UnmodifiableListView<VisitRecord> get visits =>
      UnmodifiableListView(_visits);

  /// Parses deep link / QR payload and extracts spot id.
  /// Expected format: https://myapp.com/checkin?spot_id=SPOT001
  String? extractSpotIdFromPayload(String qrPayload) {
    final uri = Uri.tryParse(qrPayload);
    if (uri == null) return null;
    final spotId = uri.queryParameters['spot_id'];
    return spotId;
  }

  QrTouristSpot? getSpotById(String spotId) => findMockSpotById(spotId);

  /// Returns true if a new check-in was created, false if user already
  /// checked in at this spot today.
  bool checkIn({
    required String userId,
    required QrTouristSpot spot,
    DateTime? now,
  }) {
    final ts = now ?? DateTime.now();
    if (_hasCheckedInToday(userId: userId, spotId: spot.id, at: ts)) {
      return false;
    }

    _visits.add(
      VisitRecord(
        userId: userId,
        spotId: spot.id,
        spotName: spot.name,
        municipality: spot.municipality,
        timestamp: ts,
      ),
    );
    return true;
  }

  bool _hasCheckedInToday({
    required String userId,
    required String spotId,
    required DateTime at,
  }) {
    final startOfDay = DateTime(at.year, at.month, at.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return _visits.any((v) =>
        v.userId == userId &&
        v.spotId == spotId &&
        !v.timestamp.isBefore(startOfDay) &&
        v.timestamp.isBefore(endOfDay));
  }

  // Analytics

  Map<String, int> totalVisitsPerSpot() {
    final Map<String, int> counts = {};
    for (final v in _visits) {
      counts[v.spotId] = (counts[v.spotId] ?? 0) + 1;
    }
    return counts;
  }

  Map<String, int> totalVisitsPerMunicipality() {
    final Map<String, int> counts = {};
    for (final v in _visits) {
      counts[v.municipality] = (counts[v.municipality] ?? 0) + 1;
    }
    return counts;
  }

  int dailyVisitCount(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return _visits
        .where((v) => !v.timestamp.isBefore(start) && v.timestamp.isBefore(end))
        .length;
  }

  int monthlyVisitCount(int year, int month) {
    final start = DateTime(year, month, 1);
    final end =
        month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    return _visits
        .where((v) => !v.timestamp.isBefore(start) && v.timestamp.isBefore(end))
        .length;
  }
}

