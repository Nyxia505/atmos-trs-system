import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:atmos_trs_system/config/mice_event_types.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/models/mice_register.dart';
import 'package:atmos_trs_system/models/sign_off.dart';
import 'package:atmos_trs_system/services/ae_register_service.dart';
import 'package:atmos_trs_system/services/sign_off_service.dart';
import 'package:atmos_trs_system/utils/mice_register_calculator.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Venue-entered CUS MICE survey: `mice_monthly_reports/{aeId}_{yyyy}_{mm}`
/// (+ `events`). Header totals are recomputed on every write so LGU / OPTACA /
/// Governor read one document per venue per month. Same sign-off model as the
/// DAE-1B register ([AeRegisterService]).
abstract final class MiceRegisterService {
  static const collection = 'mice_monthly_reports';
  static const eventsSubcollection = 'events';
  static const settingsCollection = 'mice_venue_settings';
  static const _timeout = Duration(seconds: 20);

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(collection);

  static DocumentReference<Map<String, dynamic>> headerRef(String aeId, int year, int month) =>
      _col.doc(MiceMonthlyReport.docIdFor(aeId, year, month));

  static CollectionReference<Map<String, dynamic>> eventsRef(String aeId, int year, int month) =>
      headerRef(aeId, year, month).collection(eventsSubcollection);

  // ------------------------------------------------------------- venue side

  static Stream<MiceMonthlyReport?> watchReport(String aeId, int year, int month) =>
      headerRef(aeId, year, month).snapshots().map((d) => d.exists ? MiceMonthlyReport.fromDoc(d) : null);

  static Stream<List<MiceEvent>> watchEvents(String aeId, int year, int month) =>
      eventsRef(aeId, year, month).snapshots().map(
            (s) => MiceRegisterCalculator.eventsInMonth(s.docs.map(MiceEvent.fromDoc), year, month),
          );

  static Future<List<MiceEvent>> fetchEvents(String aeId, int year, int month) async {
    final snap = await eventsRef(aeId, year, month).get().timeout(_timeout);
    return snap.docs.map(MiceEvent.fromDoc).toList();
  }

  /// Hash of the signed events of one month; compared with
  /// `lastSignOff.contentHash` to flag unsigned edits.
  static String contentHashFor(Iterable<MiceEvent> events) {
    final sorted = events.toList()..sort((a, b) => a.id.compareTo(b.id));
    return SignOffService.contentHash({
      'events': [
        for (final e in sorted) {'id': e.id, ...e.toMap()},
      ],
    });
  }

  static const _monthAbbr = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// Short human label (sign-off summaries / change log).
  static String eventLabel(MiceEvent e) {
    String d(DateTime x) => '${_monthAbbr[x.month - 1]} ${x.day}';
    return [
      e.isMultiDay ? '${d(e.dateStart)}–${d(e.lastDay)}' : d(e.dateStart),
      if (e.eventName.trim().isNotEmpty) e.eventName.trim(),
      if (e.eventType.trim().isNotEmpty) e.eventType.trim(),
      '${e.total} attendee(s)',
    ].join(' · ');
  }

  /// Upserts / deletes events (any months) and rewrites each touched header.
  ///
  /// An event whose start moved to another month is passed in both [deletes]
  /// (old month) and [upserts] (same id, new month) and logged as one edit.
  /// With [signOff], the `signoffs` record commits in the batch of the primary
  /// month (month of the first change).
  static Future<void> applyChanges({
    required AeRegisterProfile profile,
    List<MiceEvent> upserts = const [],
    List<MiceEvent> deletes = const [],
    bool seedDemo = false,
    SignOffRequest? signOff,
  }) async {
    final months = <String, (int, int)>{};
    void track(DateTime d) => months['${d.year}-${d.month}'] = (d.year, d.month);
    for (final e in upserts) {
      track(e.dateStart);
    }
    for (final e in deletes) {
      track(e.dateStart);
    }
    if (months.isEmpty) return;

    final movedIds = {
      for (final u in upserts)
        if (u.id.isNotEmpty && deletes.any((d) => d.id == u.id)) u.id,
    };
    final movedFrom = {for (final d in deletes) if (movedIds.contains(d.id)) d.id: d};

    final first = (upserts.isNotEmpty ? upserts.first : deletes.first).dateStart;
    final primary = (first.year, first.month);
    final ordered = [...months.values.where((m) => m != primary), primary];
    final signRef = signOff == null ? null : SignOffService.newRef();
    final changes = <SignOffChange>[];

    for (final (year, month) in ordered) {
      final existing = await fetchEvents(profile.aeId, year, month);
      final byId = {for (final e in existing) e.id: e};
      final batch = FirebaseFirestore.instance.batch();
      final col = eventsRef(profile.aeId, year, month);

      for (final e in deletes.where((e) => e.dateStart.year == year && e.dateStart.month == month)) {
        if (e.id.isEmpty) continue;
        final before = byId.remove(e.id) ?? e;
        if (!movedIds.contains(e.id)) {
          changes.add(SignOffChange(op: 'delete', label: eventLabel(before), before: before.toMap()));
        }
        batch.delete(col.doc(e.id));
      }
      for (final e in upserts.where((e) => e.dateStart.year == year && e.dateStart.month == month)) {
        final ref = e.id.isEmpty ? col.doc() : col.doc(e.id);
        final before = e.id.isEmpty ? null : (byId[e.id] ?? movedFrom[e.id]);
        final saved = e.copyWith(id: ref.id, isDemo: seedDemo || e.isDemo);
        byId[ref.id] = saved;
        changes.add(SignOffChange(
          op: before == null ? 'add' : 'edit',
          label: eventLabel(saved),
          before: before?.toMap(),
          after: saved.toMap(),
        ));
        batch.set(ref, {
          ...saved.toMap(),
          if (signOff != null && signRef != null) ..._audit(signRef.id, signOff, before),
        });
      }

      final monthEvents = MiceRegisterCalculator.eventsInMonth(byId.values, year, month);
      final hash = contentHashFor(monthEvents);
      final report = await _writeHeader(
        batch: batch,
        profile: profile,
        year: year,
        month: month,
        events: monthEvents,
        seedDemo: seedDemo,
        extra: signOff == null || signRef == null ? null : {'lastSignOff': _stamp(signRef.id, signOff, hash)},
      );
      if (signOff != null && signRef != null && (year, month) == primary) {
        batch.set(signRef, _record(profile, report, signOff, hash, changes));
      }
      await batch.commit().timeout(_timeout);
    }
  }

  /// Draft ↔ submitted. Submitting a month with no events is an explicit
  /// "no events this month" report for LGU completeness.
  static Future<void> setSubmitted({
    required AeRegisterProfile profile,
    required int year,
    required int month,
    required bool submitted,
    SignOffRequest? signOff,
  }) async {
    final events = MiceRegisterCalculator.eventsInMonth(await fetchEvents(profile.aeId, year, month), year, month);
    final current = await headerRef(profile.aeId, year, month).get().timeout(_timeout);
    final prior = current.exists ? MiceMonthlyReport.fromDoc(current) : null;
    final hash = contentHashFor(events);
    final signRef = signOff == null ? null : SignOffService.newRef();
    final status = submitted ? AeReportStatus.submitted : AeReportStatus.draft;
    final batch = FirebaseFirestore.instance.batch();
    final report = await _writeHeader(
      batch: batch,
      profile: profile,
      year: year,
      month: month,
      events: events,
      existing: prior,
      extra: {
        'status': status.name,
        'submittedAt': submitted ? FieldValue.serverTimestamp() : null,
        'submittedBy': submitted ? (FirebaseAuth.instance.currentUser?.uid ?? '') : '',
        'submittedByName': submitted && signOff != null ? signOff.capture.name.trim() : '',
        if (signOff != null && signRef != null) 'lastSignOff': _stamp(signRef.id, signOff, hash),
      },
    );
    if (signOff != null && signRef != null) {
      batch.set(
        signRef,
        _record(profile, report.copyWith(status: status), signOff, hash, [
          SignOffChange(
            op: 'set',
            label: 'MICE month status',
            before: {'status': (prior?.status ?? AeReportStatus.draft).name},
            after: {'status': status.name},
          ),
        ]),
      );
    }
    await batch.commit().timeout(_timeout);
  }

  static Map<String, dynamic> _audit(String signOffId, SignOffRequest s, MiceEvent? before) {
    final name = s.capture.name.trim();
    final createdAt = before?.audit.createdAt;
    return {
      'signOffId': signOffId,
      'encodedBy': name,
      'encodedPosition': s.capture.position.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (before == null) ...{
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': name,
      } else ...{
        if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt),
        if (before.audit.createdBy.isNotEmpty) 'createdBy': before.audit.createdBy,
      },
    };
  }

  static Map<String, dynamic> _stamp(String id, SignOffRequest s, String hash) => SignOffStamp(
        id: id,
        action: s.action.code,
        name: s.capture.name.trim(),
        position: s.capture.position.trim(),
        contentHash: hash,
      ).toWriteMap();

  static Map<String, dynamic> _record(
    AeRegisterProfile profile,
    MiceMonthlyReport report,
    SignOffRequest signOff,
    String hash,
    List<SignOffChange> changes,
  ) {
    final t = report.totals;
    return SignOffService.recordMap(
      subjectType: SignOffSubjects.miceRegister,
      subjectId: report.id,
      ownerId: profile.aeId,
      ownerName: profile.aeName,
      municipalityId: normalizeMunicipalityId(profile.municipalityId),
      periodKey: report.periodKey,
      request: signOff,
      contentHash: hash,
      snapshot: {
        'status': report.status.name,
        'events': t.events,
        'hours': t.hours,
        'foreign': t.foreign,
        'local': t.local,
        'male': t.male,
        'female': t.female,
        'exhibitors': t.exhibitors,
        'exhibitVisitors': t.exhibitVisitors,
      },
      changes: changes,
    );
  }

  static Future<MiceMonthlyReport> _writeHeader({
    required WriteBatch batch,
    required AeRegisterProfile profile,
    required int year,
    required int month,
    required List<MiceEvent> events,
    MiceMonthlyReport? existing,
    bool seedDemo = false,
    Map<String, dynamic>? extra,
  }) async {
    final ref = headerRef(profile.aeId, year, month);
    var prior = existing;
    if (prior == null) {
      final current = await ref.get().timeout(_timeout);
      prior = current.exists ? MiceMonthlyReport.fromDoc(current) : null;
    }
    final report = MiceMonthlyReport(
      id: ref.id,
      aeId: profile.aeId,
      year: year,
      month: month,
      aeName: profile.aeName,
      municipalityId: normalizeMunicipalityId(profile.municipalityId),
      municipality: profile.municipality,
      category: profile.category,
      status: prior?.status ?? AeReportStatus.draft,
      submittedAt: prior?.submittedAt,
      totals: MiceRegisterCalculator.totals(events),
      isDemo: seedDemo || (prior?.isDemo ?? false),
    );
    batch.set(
      ref,
      {
        ...report.toHeaderMap(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
        ...?extra,
      },
      SetOptions(merge: true),
    );
    return report;
  }

  /// Refreshes venue identity on existing headers (name / municipality edits).
  static Future<void> refreshProfileOnHeaders(AeRegisterProfile profile) async {
    for (final r in await listForAe(profile.aeId)) {
      final events = MiceRegisterCalculator.eventsInMonth(await fetchEvents(r.aeId, r.year, r.month), r.year, r.month);
      final batch = FirebaseFirestore.instance.batch();
      await _writeHeader(batch: batch, profile: profile, year: r.year, month: r.month, events: events, existing: r);
      await batch.commit().timeout(_timeout);
    }
  }

  // ----------------------------------------------------------- custom types

  static DocumentReference<Map<String, dynamic>> _settings(String aeId) =>
      FirebaseFirestore.instance.collection(settingsCollection).doc(aeId);

  /// Venue's own event types (added from the event dialog).
  static Stream<List<MiceEventType>> watchCustomTypes(String aeId) {
    if (aeId.trim().isEmpty) return Stream.value(const []);
    return _settings(aeId).snapshots().map((d) {
      final raw = d.data()?['customTypes'];
      if (raw is! List) return const <MiceEventType>[];
      return [
        for (final m in raw)
          if (MiceEventType.fromMap(m) case final t?) t,
      ];
    });
  }

  static Future<void> saveCustomType(String aeId, MiceEventType type) async {
    final ref = _settings(aeId);
    final snap = await ref.get().timeout(_timeout);
    final raw = snap.data()?['customTypes'];
    final list = <Map<String, dynamic>>[
      if (raw is List)
        for (final m in raw)
          if (MiceEventType.fromMap(m) case final t? when t.key != type.key) t.toMap(),
      type.toMap(),
    ];
    await ref.set({
      'aeId': aeId,
      'customTypes': list,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)).timeout(_timeout);
  }

  static Future<void> removeCustomType(String aeId, MiceEventType type) async {
    final ref = _settings(aeId);
    final snap = await ref.get().timeout(_timeout);
    final raw = snap.data()?['customTypes'];
    if (raw is! List) return;
    await ref.update({
      'customTypes': [
        for (final m in raw)
          if (MiceEventType.fromMap(m) case final t? when t.key != type.key) t.toMap(),
      ],
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(_timeout);
  }

  // ------------------------------------------------------------ reader side

  static Future<List<MiceMonthlyReport>> listForAe(String aeId) async {
    final snap = await _col.where('aeId', isEqualTo: aeId.trim()).get().timeout(_timeout);
    return _sorted(snap.docs.map(MiceMonthlyReport.fromDoc));
  }

  static Stream<List<MiceMonthlyReport>> watchForAe(String aeId) =>
      _col.where('aeId', isEqualTo: aeId.trim()).snapshots().map((s) => _sorted(s.docs.map(MiceMonthlyReport.fromDoc)));

  static Stream<List<MiceMonthlyReport>> watchForPeriod({required String periodKey, String? municipalityId}) {
    Query<Map<String, dynamic>> q = _col.where('periodKey', isEqualTo: periodKey);
    final mid = normalizeMunicipalityId(municipalityId ?? '');
    if (mid.isNotEmpty) q = q.where('municipalityId', isEqualTo: mid);
    return q.snapshots().map((s) => _sorted(s.docs.map(MiceMonthlyReport.fromDoc)));
  }

  /// Venue › municipality › province-wide headers whose month is in range.
  static Future<List<MiceMonthlyReport>> listInRange({
    required DateTime start,
    required DateTime end,
    String? municipalityId,
    String? aeId,
  }) async {
    final aid = aeId?.trim() ?? '';
    final mid = normalizeMunicipalityId(municipalityId ?? '');
    Query<Map<String, dynamic>> q = _col;
    if (aid.isNotEmpty) {
      q = q.where('aeId', isEqualTo: aid);
    } else if (mid.isNotEmpty) {
      q = q.where('municipalityId', isEqualTo: mid);
    }
    final snap = await q.get().timeout(_timeout);
    final startKey = start.year * 100 + start.month;
    final endKey = end.year * 100 + end.month;
    return _sorted(snap.docs.map(MiceMonthlyReport.fromDoc).where((r) {
      final k = r.year * 100 + r.month;
      return k >= startKey && k <= endKey;
    }));
  }

  /// Events of several months (quarter / year views, CUS export).
  static Future<Map<String, List<MiceEvent>>> fetchEventsForReports(Iterable<MiceMonthlyReport> reports) async {
    final out = <String, List<MiceEvent>>{};
    await Future.wait([
      for (final r in reports)
        _col.doc(r.id).collection(eventsSubcollection).get().timeout(_timeout).then((s) {
          out[r.id] = MiceRegisterCalculator.eventsInMonth(s.docs.map(MiceEvent.fromDoc), r.year, r.month);
        }),
    ]);
    return out;
  }

  static List<MiceMonthlyReport> _sorted(Iterable<MiceMonthlyReport> list) => list.toList()
    ..sort((a, b) {
      final c = (a.year * 100 + a.month).compareTo(b.year * 100 + b.month);
      if (c != 0) return c;
      return a.aeName.toLowerCase().compareTo(b.aeName.toLowerCase());
    });

  // ----------------------------------------------------------- demo / purge

  /// Removes demo-seeded events (one venue / municipality). Months that still
  /// hold real events keep their header (totals recomputed).
  static Future<int> deleteDemo({String? aeId, String? municipalityId}) async {
    Query<Map<String, dynamic>> q = _col.where('seed', isEqualTo: 'demo');
    if ((aeId ?? '').isNotEmpty) {
      q = q.where('aeId', isEqualTo: aeId!.trim());
    } else if ((municipalityId ?? '').isNotEmpty) {
      q = q.where('municipalityId', isEqualTo: normalizeMunicipalityId(municipalityId));
    }
    final snap = await q.get().timeout(_timeout);
    var n = 0;
    for (final d in snap.docs) {
      final r = MiceMonthlyReport.fromDoc(d);
      final events = await fetchEvents(r.aeId, r.year, r.month);
      final real = events.where((e) => !e.isDemo).toList();
      if (real.isEmpty) {
        await deleteReport(r.id);
      } else {
        await applyChanges(
          profile: AeRegisterProfile(
            aeId: r.aeId,
            aeName: r.aeName,
            municipalityId: r.municipalityId,
            municipality: r.municipality,
            totalRooms: 0,
            aeType: '',
            classificationCode: '',
            category: r.category,
          ),
          deletes: events.where((e) => e.isDemo).toList(),
        );
        await headerRef(r.aeId, r.year, r.month).update({'seed': FieldValue.delete()}).timeout(_timeout);
      }
      n++;
    }
    return n;
  }

  static Future<void> deleteReport(String reportId) async {
    final events = await _col.doc(reportId).collection(eventsSubcollection).get().timeout(_timeout);
    final batch = FirebaseFirestore.instance.batch();
    for (final d in events.docs) {
      batch.delete(d.reference);
    }
    batch.delete(_col.doc(reportId));
    await batch.commit().timeout(_timeout);
  }
}
