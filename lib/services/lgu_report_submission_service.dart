import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'package:atmos_trs_system/services/governor_firestore_service.dart';
import 'package:atmos_trs_system/utils/checkin_report_summary_csv.dart';
import 'package:atmos_trs_system/utils/checkin_visitor_count.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/provincial_report_builder.dart';

/// Status values for [LguReportSubmission].
abstract final class LguReportSubmissionStatus {
  static const submitted = 'submitted';
  static const underReview = 'under_review';
  static const approved = 'approved';
  static const rejected = 'rejected';
  static const withdrawn = 'withdrawn';

  static String label(String status) {
    switch (status) {
      case submitted:
        return 'Submitted';
      case underReview:
        return 'Under review';
      case approved:
        return 'Approved';
      case rejected:
        return 'Rejected';
      case withdrawn:
        return 'Withdrawn';
      default:
        return status;
    }
  }
}

/// Common report types LGU can send to OPTACA / Provincial Tourism.
abstract final class LguReportSubmissionType {
  static const monthlySummary = 'monthly_summary';
  static const dae3FormA = 'dae3_form_a';
  static const visitorRecord = 'visitor_record';
  static const attractionReport = 'attraction_report';

  static const labels = <String, String>{
    monthlySummary: 'Monthly tourism summary',
    dae3FormA: 'DAE-3 Form A',
    visitorRecord: 'Visitor record (VAR-2)',
    attractionReport: 'Attraction visitor report',
  };

  static String label(String type) => labels[type] ?? type;
}

/// One LGU → OPTACA report package stored in Firestore.
class LguReportSubmission {
  const LguReportSubmission({
    required this.id,
    required this.municipalityId,
    required this.municipalityName,
    required this.reportType,
    required this.status,
    required this.periodStart,
    required this.periodEnd,
    required this.checkInCount,
    required this.visitorCount,
    required this.uniqueTourists,
    required this.activeSpots,
    required this.submittedByUid,
    required this.submittedByEmail,
    required this.submittedByName,
    required this.submittedAt,
    this.notes = '',
    this.reviewNotes = '',
    this.reviewedByUid,
    this.reviewedByEmail,
    this.reviewedAt,
    this.topSpotName,
  });

  final String id;
  final String municipalityId;
  final String municipalityName;
  final String reportType;
  final String status;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int checkInCount;
  final int visitorCount;
  final int uniqueTourists;
  final int activeSpots;
  final String submittedByUid;
  final String submittedByEmail;
  final String submittedByName;
  final DateTime submittedAt;
  final String notes;
  final String reviewNotes;
  final String? reviewedByUid;
  final String? reviewedByEmail;
  final DateTime? reviewedAt;
  final String? topSpotName;

  bool get isOpen =>
      status == LguReportSubmissionStatus.submitted ||
      status == LguReportSubmissionStatus.underReview;

  String get reportTypeLabel => LguReportSubmissionType.label(reportType);
  String get statusLabel => LguReportSubmissionStatus.label(status);

  factory LguReportSubmission.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    return LguReportSubmission(
      id: doc.id,
      municipalityId: d['municipalityId']?.toString() ?? '',
      municipalityName: d['municipalityName']?.toString() ?? '',
      reportType: d['reportType']?.toString() ??
          LguReportSubmissionType.monthlySummary,
      status: d['status']?.toString() ?? LguReportSubmissionStatus.submitted,
      periodStart: _asDate(d['periodStart']) ?? DateTime.now(),
      periodEnd: _asDate(d['periodEnd']) ?? DateTime.now(),
      checkInCount: _asInt(d['checkInCount']),
      visitorCount: _asInt(d['visitorCount']),
      uniqueTourists: _asInt(d['uniqueTourists']),
      activeSpots: _asInt(d['activeSpots']),
      submittedByUid: d['submittedByUid']?.toString() ?? '',
      submittedByEmail: d['submittedByEmail']?.toString() ?? '',
      submittedByName: d['submittedByName']?.toString() ?? '',
      submittedAt: _asDate(d['submittedAt']) ?? DateTime.now(),
      notes: d['notes']?.toString() ?? '',
      reviewNotes: d['reviewNotes']?.toString() ?? '',
      reviewedByUid: d['reviewedByUid']?.toString(),
      reviewedByEmail: d['reviewedByEmail']?.toString(),
      reviewedAt: _asDate(d['reviewedAt']),
      topSpotName: d['topSpotName']?.toString(),
    );
  }

  static DateTime? _asDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static int _asInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

/// Creates / reviews LGU report packages for OPTACA (Provincial Tourism).
class LguReportSubmissionService {
  LguReportSubmissionService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const collectionId = 'lgu_report_submissions';

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(collectionId);

  /// Snapshot metrics for the LGU submit form preview.
  Map<String, dynamic> buildMetrics({
    required List<Map<String, dynamic>> checkIns,
    required DateTime periodStart,
    required DateTime periodEnd,
    DateTime? Function(Map<String, dynamic>)? parseTimestamp,
  }) {
    final startNorm =
        DateTime(periodStart.year, periodStart.month, periodStart.day);
    final endNorm = DateTime(
      periodEnd.year,
      periodEnd.month,
      periodEnd.day,
      23,
      59,
      59,
      999,
    );
    final filtered = <Map<String, dynamic>>[];
    for (final c in checkIns) {
      if (isExcludedFromOfficialReports(c)) continue;
      final t = parseTimestamp != null
          ? parseTimestamp(c)
          : GovernorFirestoreService.parseCheckInTime(c);
      if (t == null) continue;
      if (t.isBefore(startNorm) || t.isAfter(endNorm)) continue;
      filtered.add(c);
    }
    // Prefer official filter when no custom parser (also drops dummy rows).
    final rows = parseTimestamp == null
        ? filterCheckInsInDateRange(checkIns, periodStart, periodEnd)
        : filtered;
    final visitorCount = sumCheckInVisitors(rows);
    final unique = <String>{};
    final spotCounts = <String, int>{};
    for (final c in rows) {
      final uid = (c['userId'] ??
              c['user_id'] ??
              c['tourist_id'] ??
              c['touristId'] ??
              '')
          .toString()
          .trim();
      if (uid.isNotEmpty) unique.add(uid);
      final spot = (c['spotName'] ??
              c['spot_name'] ??
              c['location'] ??
              c['touristSpotName'] ??
              'Unknown')
          .toString()
          .trim();
      if (spot.isNotEmpty) {
        spotCounts[spot] = (spotCounts[spot] ?? 0) + checkInVisitorCount(c);
      }
    }
    String? topSpot;
    var topN = 0;
    spotCounts.forEach((name, n) {
      if (n > topN) {
        topN = n;
        topSpot = name;
      }
    });
    return {
      'checkInCount': rows.length,
      'visitorCount': visitorCount,
      'uniqueTourists': unique.length,
      'activeSpots': spotCounts.length,
      'topSpotName': topSpot,
    };
  }

  Future<String> submit({
    required String municipalityId,
    required String municipalityName,
    required String reportType,
    required DateTime periodStart,
    required DateTime periodEnd,
    required List<Map<String, dynamic>> checkIns,
    String notes = '',
    String submittedByName = '',
    DateTime? Function(Map<String, dynamic>)? parseTimestamp,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Sign in required to submit a report.');
    }
    final mid = normalizeMunicipalityId(municipalityId);
    if (mid.isEmpty) {
      throw StateError('Municipality is required.');
    }
    final metrics = buildMetrics(
      checkIns: checkIns,
      periodStart: periodStart,
      periodEnd: periodEnd,
      parseTimestamp: parseTimestamp,
    );
    final start = DateTime(
      periodStart.year,
      periodStart.month,
      periodStart.day,
    );
    final end = DateTime(
      periodEnd.year,
      periodEnd.month,
      periodEnd.day,
      23,
      59,
      59,
    );
    final ref = await _col.add({
      'municipalityId': mid,
      'municipalityName': municipalityName.trim().isEmpty
          ? mid
          : municipalityName.trim(),
      'reportType': reportType,
      'status': LguReportSubmissionStatus.submitted,
      'periodStart': Timestamp.fromDate(start),
      'periodEnd': Timestamp.fromDate(end),
      'checkInCount': metrics['checkInCount'],
      'visitorCount': metrics['visitorCount'],
      'uniqueTourists': metrics['uniqueTourists'],
      'activeSpots': metrics['activeSpots'],
      'topSpotName': metrics['topSpotName'],
      'notes': notes.trim(),
      'reviewNotes': '',
      'submittedByUid': user.uid,
      'submittedByEmail': (user.email ?? '').trim().toLowerCase(),
      'submittedByName': submittedByName.trim().isEmpty
          ? ((user.email ?? 'LGU Tourism').trim())
          : submittedByName.trim(),
      'submittedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _notifyProvincialNewSubmission(
      submissionId: ref.id,
      municipalityName: municipalityName,
      reportType: reportType,
    );
    return ref.id;
  }

  Future<List<LguReportSubmission>> listForMunicipality(
    String municipalityId, {
    int limit = 40,
  }) async {
    final mid = normalizeMunicipalityId(municipalityId);
    if (mid.isEmpty) return const [];
    try {
      final snap = await _col
          .where('municipalityId', isEqualTo: mid)
          .orderBy('submittedAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map(LguReportSubmission.fromDoc).toList();
    } on FirebaseException catch (e) {
      // Missing composite index → fall back without orderBy.
      debugPrint('[LGU_REPORT] listForMunicipality fallback: ${e.code}');
      final snap =
          await _col.where('municipalityId', isEqualTo: mid).limit(limit).get();
      final list = snap.docs.map(LguReportSubmission.fromDoc).toList()
        ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
      return list;
    }
  }

  Future<List<LguReportSubmission>> listForProvincial({
    String? statusFilter,
    int limit = 80,
  }) async {
    try {
      Query<Map<String, dynamic>> q = _col;
      if (statusFilter != null && statusFilter.isNotEmpty) {
        q = q.where('status', isEqualTo: statusFilter);
      }
      final snap =
          await q.orderBy('submittedAt', descending: true).limit(limit).get();
      return snap.docs.map(LguReportSubmission.fromDoc).toList();
    } on FirebaseException catch (e) {
      debugPrint('[LGU_REPORT] listForProvincial fallback: ${e.code}');
      final snap = await _col.limit(limit).get();
      var list = snap.docs.map(LguReportSubmission.fromDoc).toList();
      if (statusFilter != null && statusFilter.isNotEmpty) {
        list = list.where((s) => s.status == statusFilter).toList();
      }
      list.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
      return list;
    }
  }

  Future<void> markUnderReview(String id) async {
    await _updateStatus(
      id: id,
      status: LguReportSubmissionStatus.underReview,
    );
  }

  Future<void> approve({
    required String id,
    String reviewNotes = '',
  }) async {
    await _updateStatus(
      id: id,
      status: LguReportSubmissionStatus.approved,
      reviewNotes: reviewNotes,
      notifyLgu: true,
    );
  }

  Future<void> reject({
    required String id,
    required String reviewNotes,
  }) async {
    final notes = reviewNotes.trim();
    if (notes.isEmpty) {
      throw ArgumentError('Please add a reason when rejecting.');
    }
    await _updateStatus(
      id: id,
      status: LguReportSubmissionStatus.rejected,
      reviewNotes: notes,
      notifyLgu: true,
    );
  }

  Future<void> withdraw(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in required.');
    final doc = await _col.doc(id).get();
    if (!doc.exists) throw StateError('Report not found.');
    final data = doc.data() ?? {};
    final status = data['status']?.toString() ?? '';
    if (status != LguReportSubmissionStatus.submitted &&
        status != LguReportSubmissionStatus.underReview) {
      throw StateError('Only open submissions can be withdrawn.');
    }
    if (data['submittedByUid']?.toString() != user.uid &&
        data['municipalityId']?.toString() !=
            normalizeMunicipalityId(
              data['municipalityId']?.toString() ?? '',
            )) {
      // Still allow LGU staff of same municipality via rules; client soft-check.
    }
    await _col.doc(id).update({
      'status': LguReportSubmissionStatus.withdrawn,
      'updatedAt': FieldValue.serverTimestamp(),
      'withdrawnAt': FieldValue.serverTimestamp(),
      'withdrawnByUid': user.uid,
    });
  }

  Future<void> _updateStatus({
    required String id,
    required String status,
    String reviewNotes = '',
    bool notifyLgu = false,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Sign in required.');
    final patch = <String, dynamic>{
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      'reviewedAt': FieldValue.serverTimestamp(),
      'reviewedByUid': user.uid,
      'reviewedByEmail': (user.email ?? '').trim().toLowerCase(),
    };
    if (reviewNotes.trim().isNotEmpty) {
      patch['reviewNotes'] = reviewNotes.trim();
    }
    await _col.doc(id).update(patch);

    if (notifyLgu) {
      final doc = await _col.doc(id).get();
      final data = doc.data();
      if (data == null) return;
      await _notifyLguReviewResult(
        submissionId: id,
        municipalityId: data['municipalityId']?.toString() ?? '',
        status: status,
        reportType: data['reportType']?.toString() ?? '',
      );
    }
  }

  Future<void> _notifyProvincialNewSubmission({
    required String submissionId,
    required String municipalityName,
    required String reportType,
  }) async {
    try {
      await _db.collection('notifications').add({
        'type': 'lgu_report_submitted',
        'audience': 'provincial_tourism',
        'title': 'New LGU report for OPTACA',
        'body':
            '${municipalityName.trim().isEmpty ? 'An LGU' : municipalityName} '
            'submitted ${LguReportSubmissionType.label(reportType)}.',
        'submissionId': submissionId,
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
      });
    } catch (e) {
      debugPrint('[LGU_REPORT] provincial notify failed: $e');
    }
  }

  Future<void> _notifyLguReviewResult({
    required String submissionId,
    required String municipalityId,
    required String status,
    required String reportType,
  }) async {
    try {
      await _db.collection('notifications').add({
        'type': 'lgu_report_reviewed',
        'audience': 'lgu_tourism',
        'municipalityId': normalizeMunicipalityId(municipalityId),
        'title': status == LguReportSubmissionStatus.approved
            ? 'Report approved by OPTACA'
            : 'Report needs revision',
        'body':
            '${LguReportSubmissionType.label(reportType)} was marked '
            '${LguReportSubmissionStatus.label(status)}.',
        'submissionId': submissionId,
        'status': status,
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
      });
    } catch (e) {
      debugPrint('[LGU_REPORT] LGU notify failed: $e');
    }
  }
}
