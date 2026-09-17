import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Loads `qr_checkins` for LGU report windows (beyond the dashboard's recent-100 list).
class LguCheckInReportQuery {
  LguCheckInReportQuery._();

  /// Fetches check-ins for [municipalityQueryIds] between [start] and [end] (inclusive days).
  static Future<List<Map<String, dynamic>>> fetchRange({
    required List<String> municipalityQueryIds,
    required DateTime start,
    required DateTime end,
    int limitPerQuery = 1500,
  }) async {
    if (municipalityQueryIds.isEmpty) return const [];

    final firestore = FirebaseFirestore.instance;
    final startTs = Timestamp.fromDate(
      DateTime(start.year, start.month, start.day),
    );
    final endTs = Timestamp.fromDate(
      DateTime(end.year, end.month, end.day, 23, 59, 59, 999),
    );
    final byId = <String, Map<String, dynamic>>{};

    Future<void> mergeField(String field, String mid) async {
      try {
        final snap = await firestore
            .collection('qr_checkins')
            .where(field, isEqualTo: mid)
            .where('timestamp', isGreaterThanOrEqualTo: startTs)
            .where('timestamp', isLessThanOrEqualTo: endTs)
            .orderBy('timestamp', descending: true)
            .limit(limitPerQuery)
            .get()
            .timeout(const Duration(seconds: 25));
        for (final doc in snap.docs) {
          byId[doc.id] = <String, dynamic>{'id': doc.id, ...doc.data()};
        }
      } catch (e) {
        debugPrint(
          '[LguCheckInReportQuery] ranged $field=$mid failed, fallback: $e',
        );
        try {
          final snap = await firestore
              .collection('qr_checkins')
              .where(field, isEqualTo: mid)
              .orderBy('timestamp', descending: true)
              .limit(limitPerQuery)
              .get()
              .timeout(const Duration(seconds: 25));
          for (final doc in snap.docs) {
            final data = doc.data();
            final ts = data['timestamp'];
            DateTime? when;
            if (ts is Timestamp) {
              when = ts.toDate();
            } else if (ts is DateTime) {
              when = ts;
            }
            if (when == null) continue;
            if (when.isBefore(startTs.toDate()) || when.isAfter(endTs.toDate())) {
              continue;
            }
            byId[doc.id] = <String, dynamic>{'id': doc.id, ...data};
          }
        } catch (e2) {
          debugPrint('[LguCheckInReportQuery] fallback $field=$mid: $e2');
        }
      }
    }

    await Future.wait<void>([
      for (final mid in municipalityQueryIds) ...[
        mergeField('municipalityId', mid),
        mergeField('lguId', mid),
      ],
    ]);

    return byId.values.toList(growable: false);
  }
}
