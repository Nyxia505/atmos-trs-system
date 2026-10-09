import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'package:atmos_trs_system/config/ae_register_schema.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/models/sign_off.dart';
import 'package:atmos_trs_system/services/sign_off_service.dart';
import 'package:atmos_trs_system/utils/ae_register_calculator.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Establishment identity copied onto every monthly header.
class AeRegisterProfile {
  const AeRegisterProfile({
    required this.aeId,
    required this.aeName,
    required this.municipalityId,
    required this.municipality,
    required this.totalRooms,
    required this.aeType,
    required this.classificationCode,
    required this.category,
  });

  /// Profile from registry fields; type / code default from [category].
  factory AeRegisterProfile.fromRegistry({
    required String aeId,
    required String aeName,
    required String category,
    String municipalityId = '',
    String municipality = '',
    int? totalRooms,
    String aeType = '',
    String classificationCode = '',
  }) {
    final type = aeType.isNotEmpty ? aeType : AeTypeCatalog.typeForCategory(category);
    return AeRegisterProfile(
      aeId: aeId,
      aeName: aeName,
      municipalityId: municipalityId,
      municipality: municipality,
      totalRooms: AeRegisterSchema.forCategory(category).tracksRooms ? (totalRooms ?? 0) : 0,
      aeType: type,
      classificationCode: classificationCode.isNotEmpty ? classificationCode : AeTypeCatalog.codeFor(type),
      category: category,
    );
  }

  final String aeId;
  final String aeName;
  final String municipalityId;
  final String municipality;
  final int totalRooms;
  final String aeType;
  final String classificationCode;
  final String category;
}

/// Hotel-entered DAE-1B register: `ae_monthly_reports/{aeId}_{yyyy}_{mm}`
/// (+ `rows` subcollection). Header totals are recomputed on every write so
/// LGU / OPTACA / Governor read one document per AE per month.
abstract final class AeRegisterService {
  static const collection = 'ae_monthly_reports';
  static const rowsSubcollection = 'rows';
  static const _writeTimeout = Duration(seconds: 20);

  static CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection(collection);

  static DocumentReference<Map<String, dynamic>> headerRef(
    String aeId,
    int year,
    int month,
  ) =>
      _col.doc(AeMonthlyReport.docIdFor(aeId, year, month));

  static CollectionReference<Map<String, dynamic>> rowsRef(
    String aeId,
    int year,
    int month,
  ) =>
      headerRef(aeId, year, month).collection(rowsSubcollection);

  // ---------------------------------------------------------------- hotel side

  static Stream<AeMonthlyReport?> watchReport(String aeId, int year, int month) =>
      headerRef(aeId, year, month).snapshots().map(
            (d) => d.exists ? AeMonthlyReport.fromDoc(d) : null,
          );

  static Stream<List<AeRegisterRow>> watchRows(String aeId, int year, int month) =>
      rowsRef(aeId, year, month).snapshots().map(
            (s) => AeRegisterCalculator.rowsInMonth(
              s.docs.map(AeRegisterRow.fromDoc),
              year,
              month,
            ),
          );

  static Future<List<AeRegisterRow>> fetchRows(String aeId, int year, int month) async {
    final snap = await rowsRef(aeId, year, month).get().timeout(_writeTimeout);
    return snap.docs.map(AeRegisterRow.fromDoc).toList();
  }

  /// Hash of the signed register content for one month (rows + "no guests"
  /// days). Compared with `lastSignOff.contentHash` to flag unsigned edits.
  static String contentHashFor(Iterable<AeRegisterRow> rows, List<int> zeroDays) {
    final sorted = rows.toList()..sort((a, b) => a.id.compareTo(b.id));
    return SignOffService.contentHash({
      'rows': [
        for (final r in sorted) {'id': r.id, ...r.toMap()},
      ],
      'zeroDays': [...zeroDays]..sort(),
    });
  }

  /// Short human label for a row (sign-off summaries / change log).
  static String rowLabel(AeRegisterRow r) {
    final d = '${_monthAbbr[r.date.month - 1]} ${r.date.day}';
    return [
      d,
      if (r.roomNo.isNotEmpty) 'Room ${r.roomNo}',
      '${r.guests} guest(s)',
      if (r.residence.isNotEmpty) r.residence,
    ].join(' · ');
  }

  static const _monthAbbr = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// Upserts / deletes rows (any months) and rewrites each affected header.
  ///
  /// With [signOff], every touched row and header is stamped with the signer
  /// and the `signoffs` record commits in the same batch as the primary month
  /// (the month of the first change).
  static Future<void> applyChanges({
    required AeRegisterProfile profile,
    List<AeRegisterRow> upserts = const [],
    List<AeRegisterRow> deletes = const [],
    bool seedDemo = false,
    SignOffRequest? signOff,
  }) async {
    final months = <String, (int, int)>{};
    void track(DateTime d) => months['${d.year}-${d.month}'] = (d.year, d.month);
    for (final r in upserts) {
      track(r.date);
    }
    for (final r in deletes) {
      track(r.date);
    }
    if (months.isEmpty) return;

    final firstDate = (upserts.isNotEmpty ? upserts.first : deletes.first).date;
    final primary = (firstDate.year, firstDate.month);
    final ordered = [
      ...months.values.where((m) => m != primary),
      primary,
    ];
    final signRef = signOff == null ? null : SignOffService.newRef();
    final changes = <SignOffChange>[];

    for (final (year, month) in ordered) {
      final existing = await fetchRows(profile.aeId, year, month);
      final byId = {for (final r in existing) r.id: r};
      var batch = FirebaseFirestore.instance.batch();
      var ops = 0;
      Future<void> flushIfFull() async {
        if (++ops < 440) return;
        await batch.commit().timeout(_writeTimeout);
        batch = FirebaseFirestore.instance.batch();
        ops = 0;
      }

      final rowsCol = rowsRef(profile.aeId, year, month);

      for (final r in deletes.where((r) => r.date.year == year && r.date.month == month)) {
        if (r.id.isEmpty) continue;
        final before = byId.remove(r.id) ?? r;
        changes.add(SignOffChange(op: 'delete', label: rowLabel(before), before: before.toMap()));
        batch.delete(rowsCol.doc(r.id));
        await flushIfFull();
      }
      for (final r in upserts.where((r) => r.date.year == year && r.date.month == month)) {
        final ref = r.id.isEmpty ? rowsCol.doc() : rowsCol.doc(r.id);
        final before = r.id.isEmpty ? null : byId[r.id];
        final row = AeRegisterRow(
          id: ref.id,
          date: r.date,
          roomNo: r.roomNo,
          residence: r.residence,
          phRegion: r.phRegion,
          guests: r.guests,
          female: r.female,
          male: r.male,
          checkedInDay: r.checkedInDay,
          rate: r.rate,
          chargesA: r.chargesA,
          chargesB: r.chargesB,
          isDemo: seedDemo || r.isDemo,
        );
        byId[ref.id] = row;
        changes.add(SignOffChange(
          op: before == null ? 'add' : 'edit',
          label: rowLabel(row),
          before: before?.toMap(),
          after: row.toMap(),
        ));
        batch.set(ref, {
          ...row.toMap(),
          if (signOff != null && signRef != null) ..._rowAudit(signRef.id, signOff, before),
        });
        await flushIfFull();
      }

      final monthRows = AeRegisterCalculator.rowsInMonth(byId.values, year, month);
      final current = await headerRef(profile.aeId, year, month).get().timeout(_writeTimeout);
      final zd = current.exists ? AeMonthlyReport.fromDoc(current).zeroDays : const <int>[];
      final hash = contentHashFor(monthRows, zd);
      final report = await _writeHeader(
        batch: batch,
        profile: profile,
        year: year,
        month: month,
        rows: byId.values.toList(),
        seedDemo: seedDemo,
        extra: signOff == null || signRef == null ? null : {'lastSignOff': _stamp(signRef.id, signOff, hash)},
      );
      if (signOff != null && signRef != null && (year, month) == primary) {
        batch.set(signRef, _registerRecord(profile, report, signOff, hash, changes));
      }
      await batch.commit().timeout(_writeTimeout);
      await _syncNextMonthCarryOver(profile, year, month, byId.values);
    }
  }

  static Map<String, dynamic> _rowAudit(String signOffId, SignOffRequest s, AeRegisterRow? before) {
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

  static Map<String, dynamic> _registerRecord(
    AeRegisterProfile profile,
    AeMonthlyReport report,
    SignOffRequest signOff,
    String hash,
    List<SignOffChange> changes,
  ) =>
      SignOffService.recordMap(
        subjectType: SignOffSubjects.aeRegister,
        subjectId: report.id,
        ownerId: profile.aeId,
        ownerName: profile.aeName,
        municipalityId: normalizeMunicipalityId(profile.municipalityId),
        periodKey: report.periodKey,
        request: signOff,
        contentHash: hash,
        snapshot: _snapshot(report),
        changes: changes,
      );

  static Map<String, dynamic> _snapshot(AeMonthlyReport r) {
    final t = r.totals;
    return {
      'status': r.status.name,
      'totalRooms': r.totalRooms,
      'rowCount': t.rowCount,
      'filledDays': t.filledDays,
      'zeroDays': r.zeroDays,
      'checkIns': t.checkIns,
      'guestNights': t.guestNights,
      'roomsOccupied': t.roomsOccupied,
      'occupancyRate': t.occupancyRate,
      'alos': t.alos,
      'domesticArrivals': t.domesticArrivals,
      'foreignArrivals': t.foreignArrivals,
      'overseasFilipinoArrivals': t.overseasFilipinoArrivals,
      'grandTotalSales': t.grandTotalSales,
    };
  }

  static Future<AeMonthlyReport> _writeHeader({
    required WriteBatch batch,
    required AeRegisterProfile profile,
    required int year,
    required int month,
    required List<AeRegisterRow> rows,
    List<int>? zeroDays,
    bool seedDemo = false,
    Map<String, dynamic>? extra,
  }) async {
    final ref = headerRef(profile.aeId, year, month);
    final current = await ref.get().timeout(_writeTimeout);
    final existing = current.exists ? AeMonthlyReport.fromDoc(current) : null;
    final prev = await _prevMonthLastDayGuests(profile.aeId, year, month);
    final zd = zeroDays ?? existing?.zeroDays ?? const <int>[];
    final totals = AeRegisterCalculator.totals(
      rows: rows,
      year: year,
      month: month,
      totalRooms: profile.totalRooms,
      prevMonthLastDayGuests: prev,
      zeroDays: zd,
    );
    final report = AeMonthlyReport(
      id: ref.id,
      aeId: profile.aeId,
      year: year,
      month: month,
      aeName: profile.aeName,
      municipalityId: normalizeMunicipalityId(profile.municipalityId),
      municipality: profile.municipality,
      totalRooms: profile.totalRooms,
      aeType: profile.aeType,
      classificationCode: profile.classificationCode,
      category: profile.category,
      prevMonthLastDayGuests: prev,
      zeroDays: zd,
      status: existing?.status ?? AeReportStatus.draft,
      submittedAt: existing?.submittedAt,
      totals: totals,
      isDemo: seedDemo || (existing?.isDemo ?? false),
    );
    batch.set(
      ref,
      {
        ...report.toHeaderMap(),
        'lastDayGuests': AeRegisterCalculator.lastDayGuests(rows, year, month),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
        ...?extra,
      },
      SetOptions(merge: true),
    );
    return report;
  }

  static Future<int> _prevMonthLastDayGuests(String aeId, int year, int month) async {
    final prev = DateTime(year, month - 1);
    try {
      final d = await headerRef(aeId, prev.year, prev.month).get().timeout(_writeTimeout);
      final v = d.data()?['lastDayGuests'];
      return v is num ? v.toInt() : 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> _syncNextMonthCarryOver(
    AeRegisterProfile profile,
    int year,
    int month,
    Iterable<AeRegisterRow> rows,
  ) async {
    final next = DateTime(year, month + 1);
    final ref = headerRef(profile.aeId, next.year, next.month);
    try {
      final d = await ref.get().timeout(_writeTimeout);
      if (!d.exists) return;
      await ref.update({
        'prevMonthLastDayGuests': AeRegisterCalculator.lastDayGuests(rows, year, month),
      }).timeout(_writeTimeout);
    } catch (e) {
      debugPrint('[AeRegister] carry-over sync skipped: $e');
    }
  }

  /// Ensures the header exists (profile fields refreshed) without rows changes.
  static Future<void> touchHeader(AeRegisterProfile profile, int year, int month) async {
    final rows = await fetchRows(profile.aeId, year, month);
    final batch = FirebaseFirestore.instance.batch();
    await _writeHeader(batch: batch, profile: profile, year: year, month: month, rows: rows);
    await batch.commit().timeout(_writeTimeout);
  }

  /// Marks / unmarks a day as "no guests" (completeness without rows).
  static Future<void> setZeroDay({
    required AeRegisterProfile profile,
    required int year,
    required int month,
    required int day,
    required bool zero,
    SignOffRequest? signOff,
  }) async {
    final ref = headerRef(profile.aeId, year, month);
    final d = await ref.get().timeout(_writeTimeout);
    final existing = d.exists ? AeMonthlyReport.fromDoc(d).zeroDays.toSet() : <int>{};
    final wasZero = existing.contains(day);
    if (zero) {
      existing.add(day);
    } else {
      existing.remove(day);
    }
    final zd = existing.toList()..sort();
    final rows = await fetchRows(profile.aeId, year, month);
    final hash = contentHashFor(AeRegisterCalculator.rowsInMonth(rows, year, month), zd);
    final signRef = signOff == null ? null : SignOffService.newRef();
    final batch = FirebaseFirestore.instance.batch();
    final report = await _writeHeader(
      batch: batch,
      profile: profile,
      year: year,
      month: month,
      rows: rows,
      zeroDays: zd,
      extra: signOff == null || signRef == null ? null : {'lastSignOff': _stamp(signRef.id, signOff, hash)},
    );
    if (signOff != null && signRef != null) {
      batch.set(
        signRef,
        _registerRecord(profile, report, signOff, hash, [
          SignOffChange(
            op: 'set',
            label: '${_monthAbbr[month - 1]} $day · no guests',
            before: {'noGuests': wasZero},
            after: {'noGuests': zero},
          ),
        ]),
      );
    }
    await batch.commit().timeout(_writeTimeout);
  }

  static Future<void> setSubmitted({
    required AeRegisterProfile profile,
    required int year,
    required int month,
    required bool submitted,
    SignOffRequest? signOff,
  }) async {
    final rows = await fetchRows(profile.aeId, year, month);
    final current = await headerRef(profile.aeId, year, month).get().timeout(_writeTimeout);
    final prior = current.exists ? AeMonthlyReport.fromDoc(current) : null;
    final hash = contentHashFor(
      AeRegisterCalculator.rowsInMonth(rows, year, month),
      prior?.zeroDays ?? const [],
    );
    final signRef = signOff == null ? null : SignOffService.newRef();
    final status = submitted ? AeReportStatus.submitted : AeReportStatus.draft;
    final batch = FirebaseFirestore.instance.batch();
    final report = await _writeHeader(
      batch: batch,
      profile: profile,
      year: year,
      month: month,
      rows: rows,
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
        _registerRecord(profile, report.copyWith(status: status), signOff, hash, [
          SignOffChange(
            op: 'set',
            label: 'Month status',
            before: {'status': (prior?.status ?? AeReportStatus.draft).name},
            after: {'status': status.name},
          ),
        ]),
      );
    }
    await batch.commit().timeout(_writeTimeout);
  }

  /// Refreshes profile fields on all existing headers (rooms / type changes).
  static Future<void> refreshProfileOnHeaders(AeRegisterProfile profile) async {
    final snap = await _col.where('aeId', isEqualTo: profile.aeId).get().timeout(_writeTimeout);
    for (final d in snap.docs) {
      final r = AeMonthlyReport.fromDoc(d);
      await touchHeader(profile, r.year, r.month);
    }
  }

  // --------------------------------------------------------------- reader side

  static Future<List<AeMonthlyReport>> listForAe(String aeId) async {
    final snap = await _col.where('aeId', isEqualTo: aeId.trim()).get().timeout(_writeTimeout);
    return _sorted(snap.docs.map(AeMonthlyReport.fromDoc));
  }

  static Stream<List<AeMonthlyReport>> watchForAe(String aeId) =>
      _col.where('aeId', isEqualTo: aeId.trim()).snapshots().map(
            (s) => _sorted(s.docs.map(AeMonthlyReport.fromDoc)),
          );

  static Future<List<AeMonthlyReport>> listForMunicipality(String municipalityId) async {
    final snap = await _col
        .where('municipalityId', isEqualTo: normalizeMunicipalityId(municipalityId))
        .get()
        .timeout(_writeTimeout);
    return _sorted(snap.docs.map(AeMonthlyReport.fromDoc));
  }

  static Stream<List<AeMonthlyReport>> watchForPeriod({
    required String periodKey,
    String? municipalityId,
  }) {
    Query<Map<String, dynamic>> q = _col.where('periodKey', isEqualTo: periodKey);
    final mid = normalizeMunicipalityId(municipalityId ?? '');
    if (mid.isNotEmpty) q = q.where('municipalityId', isEqualTo: mid);
    return q.snapshots().map((s) => _sorted(s.docs.map(AeMonthlyReport.fromDoc)));
  }

  /// Province-wide (OPTACA / Governor) or municipality-scoped list in a range.
  static Future<List<AeMonthlyReport>> listInRange({
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
    final snap = await q.get().timeout(_writeTimeout);
    final startKey = start.year * 100 + start.month;
    final endKey = end.year * 100 + end.month;
    return _sorted(
      snap.docs.map(AeMonthlyReport.fromDoc).where((r) {
        final k = r.year * 100 + r.month;
        return k >= startKey && k <= endKey;
      }),
    );
  }

  /// Rows for several months (DAE-1A register, Insights history).
  static Future<List<AeRegisterRow>> fetchRowsForReports(Iterable<AeMonthlyReport> reports) async {
    final out = <AeRegisterRow>[];
    for (final r in reports) {
      final snap = await _col.doc(r.id).collection(rowsSubcollection).get().timeout(_writeTimeout);
      out.addAll(snap.docs.map(AeRegisterRow.fromDoc));
    }
    return out;
  }

  static List<AeMonthlyReport> _sorted(Iterable<AeMonthlyReport> list) =>
      list.toList()
        ..sort((a, b) {
          final c = (a.year * 100 + a.month).compareTo(b.year * 100 + b.month);
          if (c != 0) return c;
          return a.aeName.toLowerCase().compareTo(b.aeName.toLowerCase());
        });

  // ------------------------------------------------------------ demo / purge

  /// Removes demo-seeded rows (optionally for one AE / municipality). Months
  /// that still hold real rows keep their header (totals recomputed).
  /// Returns the number of months touched.
  static Future<int> deleteDemo({String? aeId, String? municipalityId}) async {
    Query<Map<String, dynamic>> q = _col.where('seed', isEqualTo: 'demo');
    if ((aeId ?? '').isNotEmpty) {
      q = q.where('aeId', isEqualTo: aeId!.trim());
    } else if ((municipalityId ?? '').isNotEmpty) {
      q = q.where('municipalityId', isEqualTo: normalizeMunicipalityId(municipalityId));
    }
    final snap = await q.get().timeout(_writeTimeout);
    var n = 0;
    for (final d in snap.docs) {
      final r = AeMonthlyReport.fromDoc(d);
      if ((aeId ?? '').isNotEmpty && r.aeId != aeId) continue;
      if ((municipalityId ?? '').isNotEmpty &&
          normalizeMunicipalityId(r.municipalityId) != normalizeMunicipalityId(municipalityId)) {
        continue;
      }
      final rows = await fetchRows(r.aeId, r.year, r.month);
      final real = rows.where((x) => !x.isDemo).toList();
      if (real.isEmpty) {
        await deleteReport(r.id);
      } else {
        final profile = AeRegisterProfile(
          aeId: r.aeId,
          aeName: r.aeName,
          municipalityId: r.municipalityId,
          municipality: r.municipality,
          totalRooms: r.totalRooms,
          aeType: r.aeType,
          classificationCode: r.classificationCode,
          category: r.category,
        );
        await applyChanges(profile: profile, deletes: rows.where((x) => x.isDemo).toList());
        await headerRef(r.aeId, r.year, r.month)
            .update({'seed': FieldValue.delete()}).timeout(_writeTimeout);
      }
      n++;
    }
    return n;
  }

  static Future<void> deleteReport(String reportId) async {
    final rows = await _col.doc(reportId).collection(rowsSubcollection).get().timeout(_writeTimeout);
    var batch = FirebaseFirestore.instance.batch();
    var ops = 0;
    for (final d in rows.docs) {
      batch.delete(d.reference);
      if (++ops >= 400) {
        await batch.commit().timeout(_writeTimeout);
        batch = FirebaseFirestore.instance.batch();
        ops = 0;
      }
    }
    batch.delete(_col.doc(reportId));
    await batch.commit().timeout(_writeTimeout);
  }
}
