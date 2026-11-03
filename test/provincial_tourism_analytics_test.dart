import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/services/lgu_report_submission_service.dart';
import 'package:atmos_trs_system/services/provincial_tourism_service.dart';
import 'package:atmos_trs_system/utils/visit_analytics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 2, 4); // 12:00 Asia/Manila Nov 2

  Map<String, dynamic> checkIn({
    required DateTime timestamp,
    required String municipality,
    String municipalityId = '',
    String spotId = '',
    String spotName = '',
    int visitors = 1,
    String userId = 'u1',
  }) {
    return {
      'timestamp': timestamp,
      'municipality': municipality,
      'municipalityId': municipalityId,
      'spotId': spotId,
      'spot_name': spotName,
      'visitorCount': visitors,
      'userId': userId,
    };
  }

  test('OPTACA period visitors match Governor arrivals for the same window', () {
    final rows = [
      checkIn(
        timestamp: DateTime.utc(2026, 11, 1, 3),
        municipality: 'Oroquieta City',
        municipalityId: 'oroquieta',
        spotId: 'el_triunfo_beach',
        visitors: 4,
      ),
      checkIn(
        timestamp: DateTime.utc(2026, 10, 15, 8),
        municipality: 'Ozamiz City',
        municipalityId: 'ozamiz',
        spotId: 'cotta_fort_shrine',
        visitors: 9,
      ),
      checkIn(
        timestamp: DateTime.utc(2026, 11, 2, 2),
        municipality: 'Tangub City',
        municipalityId: 'tangub',
        spotName: 'City Plaza',
        visitors: 2,
      ),
    ];

    final optacaMonth = VisitAnalyticsSnapshot.build(
      now: now,
      range: 'This Month',
      checkIns: rows,
      spotNameById: const {'el_triunfo_beach': 'El Triunfo'},
    );
    final governorMonth = VisitAnalyticsSnapshot.build(
      now: now,
      range: 'This Month',
      checkIns: rows,
      spotNameById: const {'el_triunfo_beach': 'El Triunfo'},
    );

    expect(optacaMonth.periodVisitorCount, governorMonth.periodVisitorCount);
    expect(optacaMonth.periodVisitorCount, 6);
    expect(optacaMonth.spots.first.name, 'El Triunfo');
    expect(
      ProvincialTourismService.checkInsForFilter(rows, 'This Month', now: now)
          .length,
      2,
    );

    final year = VisitAnalyticsSnapshot.build(
      now: now,
      range: 'This Year',
      checkIns: rows,
    );
    expect(year.periodVisitorCount, 15);
  });

  test('municipality ranking uses party headcount and keeps all 17 LGUs', () {
    final rows = [
      checkIn(
        timestamp: DateTime.utc(2026, 11, 1, 3),
        municipality: 'Oroquieta City',
        municipalityId: 'oroquieta',
        visitors: 5,
      ),
      checkIn(
        timestamp: DateTime.utc(2026, 10, 20, 3),
        municipality: 'Oroquieta City',
        municipalityId: 'oroquieta',
        visitors: 40,
      ),
    ];
    final stats = ProvincialTourismService.municipalityPerformance(
      checkIns: rows,
      spots: const [
        {'id': 's1', 'municipalityId': 'oroquieta', 'status': 'Active'},
      ],
      timeFilter: 'This Month',
      now: now,
    );

    expect(stats.length, getMisamisOccidentalMunicipalities().length);
    final oro = stats.firstWhere((m) => m.id == 'oroquieta');
    expect(oro.arrivals, 5);
    expect(stats.fold<int>(0, (sum, m) => sum + m.arrivals), 5);
  });

  test('LGUs reporting counts submissions, not visits', () {
    final submissions = [
      LguReportSubmission(
        id: 'r1',
        municipalityId: 'oroquieta',
        municipalityName: 'Oroquieta City',
        reportType: LguReportSubmissionType.monthlySummary,
        status: LguReportSubmissionStatus.submitted,
        periodStart: DateTime(2026, 11, 1),
        periodEnd: DateTime(2026, 11, 30),
        checkInCount: 3,
        visitorCount: 10,
        uniqueTourists: 3,
        activeSpots: 2,
        submittedByUid: 'u',
        submittedByEmail: 'lgu@test',
        submittedByName: 'LGU',
        submittedAt: DateTime(2026, 11, 2),
      ),
      LguReportSubmission(
        id: 'r2',
        municipalityId: 'ozamiz',
        municipalityName: 'Ozamiz City',
        reportType: LguReportSubmissionType.monthlySummary,
        status: LguReportSubmissionStatus.rejected,
        periodStart: DateTime(2026, 11, 1),
        periodEnd: DateTime(2026, 11, 30),
        checkInCount: 1,
        visitorCount: 1,
        uniqueTourists: 1,
        activeSpots: 1,
        submittedByUid: 'u',
        submittedByEmail: 'lgu@test',
        submittedByName: 'LGU',
        submittedAt: DateTime(2026, 11, 2),
      ),
    ];

    expect(
      ProvincialTourismService.lgusReportingCount(
        submissions,
        'This Month',
        now: now,
      ),
      1,
    );
    expect(
      ProvincialTourismService.lgusReportingCount(
        submissions,
        'This Week',
        now: DateTime.utc(2026, 10, 20, 4),
      ),
      0,
    );
  });

  test('empty month stays empty instead of falling back to lifetime totals', () {
    final rows = [
      checkIn(
        timestamp: DateTime.utc(2026, 8, 2, 3),
        municipality: 'Oroquieta City',
        municipalityId: 'oroquieta',
        spotName: 'El Triunfo',
        visitors: 12,
      ),
    ];
    final stats = VisitAnalyticsSnapshot.build(
      now: now,
      range: 'This Month',
      checkIns: rows,
    );
    expect(stats.periodVisitorCount, 0);
    expect(stats.arrivals.any((v) => v > 0), isFalse);
    expect(stats.spots, isEmpty);
  });
}
