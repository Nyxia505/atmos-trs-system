import 'dart:async';

import 'package:flutter/material.dart';

import 'package:atmos_trs_system/config/ae_register_schema.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/models/sign_off.dart';
import 'package:atmos_trs_system/services/ae_register_service.dart';
import 'package:atmos_trs_system/utils/ae_register_calculator.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_country_matrix_table.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_dae2_summary_card.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_daily_register_table.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_monthly_record_table.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_register_row_dialog.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_sheet_kit.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';
import 'package:atmos_trs_system/widgets/sign_off/sign_off_dialog.dart';
import 'package:atmos_trs_system/widgets/sign_off/sign_off_history_panel.dart';

enum AeRegisterSheet { daily, monthly, dae2, country, signoffs }

/// Excel-style establishment register (DOT ET DAE-1B): Daily Register input +
/// auto MonthlyRecord / DAE-2 / by-Country sheets. Read-only for LGU / OPTACA.
class AeRegisterWorkspace extends StatefulWidget {
  const AeRegisterWorkspace({
    super.key,
    required this.profile,
    required this.schema,
    this.readOnly = false,
    this.banner,
    this.onOpenProfile,
    this.initialYear,
    this.initialMonth,
  });

  final AeRegisterProfile profile;
  final AeRegisterSchema schema;
  final bool readOnly;
  final Widget? banner;
  final VoidCallback? onOpenProfile;
  final int? initialYear;
  final int? initialMonth;

  @override
  State<AeRegisterWorkspace> createState() => _AeRegisterWorkspaceState();
}

class _AeRegisterWorkspaceState extends State<AeRegisterWorkspace> {
  late int _year;
  late int _month;
  AeRegisterSheet _sheet = AeRegisterSheet.daily;
  bool _showCharges = false;
  bool _busy = false;
  String _streamKey = '';
  Stream<List<AeRegisterRow>>? _rowsStream;
  Stream<AeMonthlyReport?>? _reportStream;
  String _touchedKey = '';
  AeMonthlyReport? _report;
  List<AeRegisterRow>? _hashedRows;
  List<int>? _hashedZeroDays;
  String _liveHash = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = widget.initialYear ?? now.year;
    _month = widget.initialMonth ?? now.month;
  }

  void _ensureStreams() {
    final key = '${widget.profile.aeId}|$_year|$_month';
    if (key == _streamKey) return;
    _streamKey = key;
    _rowsStream = AeRegisterService.watchRows(widget.profile.aeId, _year, _month);
    _reportStream = AeRegisterService.watchReport(widget.profile.aeId, _year, _month);
  }

  void _shiftMonth(int delta) {
    final d = DateTime(_year, _month + delta);
    final now = DateTime.now();
    if (d.isAfter(DateTime(now.year, now.month + 1))) return;
    setState(() {
      _year = d.year;
      _month = d.month;
    });
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(_year, _month, 1),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year, now.month + 1, 0),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Pick any day in the month to open',
    );
    if (picked == null) return;
    setState(() {
      _year = picked.year;
      _month = picked.month;
    });
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (success != null && mounted) _snack(success);
    } on TimeoutException {
      _snack('Saving timed out. Check your connection and try again.', error: true);
    } catch (e) {
      _snack('Could not save: ${e.toString().replaceFirst('Bad state: ', '')}', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Colors.red.shade700 : null,
      ));
  }

  String? _roomConflict(List<AeRegisterRow> incoming, List<AeRegisterRow> current) {
    if (!widget.schema.tracksRooms) return null;
    for (final n in incoming) {
      for (final c in current) {
        if (c.id == n.id && n.id.isNotEmpty) continue;
        if (c.roomNo == n.roomNo && AeRegisterRow.dateKey(c.date) == AeRegisterRow.dateKey(n.date)) {
          return 'Room ${n.roomNo} already has a record on ${AeSheetKit.shortDate(n.date)}.';
        }
      }
    }
    return null;
  }

  Future<void> _add(AeRowDialogMode mode, List<AeRegisterRow> current) async {
    final lastRate = current.isEmpty ? 0.0 : current.last.rate;
    final rows = await AeRegisterRowDialog.show(
      context,
      mode: mode,
      schema: widget.schema,
      year: _year,
      month: _month,
      totalRooms: widget.profile.totalRooms,
      showCharges: _showCharges,
      lastRate: lastRate,
    );
    if (rows == null || rows.isEmpty) return;
    final conflict = _roomConflict(rows, current);
    if (conflict != null) return _snack(conflict, error: true);
    final crosses = rows.any((r) => r.date.month != _month || r.date.year != _year);
    final first = rows.first;
    final last = rows.last;
    final signOff = await _sign(
      mode == AeRowDialogMode.stay ? AeSignOffActions.addStay : AeSignOffActions.addNight,
      rows.length == 1
          ? AeRegisterService.rowLabel(first)
          : '${rows.length} nights · ${AeSheetKit.shortDate(first.date)} – ${AeSheetKit.shortDate(last.date)}'
              '${first.roomNo.isNotEmpty ? ' · Room ${first.roomNo}' : ''} · ${first.guests} guest(s) · ${first.residence}',
      details: rows.length > 1 ? rows.map(AeRegisterService.rowLabel).toList() : const [],
    );
    if (signOff == null) return;
    await _run(
      () => AeRegisterService.applyChanges(profile: widget.profile, upserts: rows, signOff: signOff),
      success: rows.length == 1
          ? 'Record added and signed.'
          : '${rows.length} nightly rows added${crosses ? ' (some in another month)' : ''} and signed.',
    );
  }

  /// Fresh signature for a save; null when cancelled (nothing is written).
  Future<SignOffRequest?> _sign(
    SignOffAction action,
    String summary, {
    List<String> details = const [],
  }) async {
    final submitted = (_report?.isSubmitted ?? false) && action != AeSignOffActions.submitMonth;
    final capture = await SignOffDialog.show(
      context,
      ownerId: widget.profile.aeId,
      action: action,
      summary: summary,
      details: details,
      requireReason: submitted,
      reasonHint: submitted || action.requiresReason ? 'e.g. guest extended stay, wrong room typed' : null,
      notice: submitted && action != AeSignOffActions.reopenMonth
          ? 'This month is already submitted — your LGU will see this change and your reason.'
          : null,
    );
    if (capture == null) return null;
    return SignOffRequest(action: action, capture: capture, summary: summary, details: details);
  }

  Future<void> _edit(AeRegisterRow row, List<AeRegisterRow> current) async {
    final rows = await AeRegisterRowDialog.show(
      context,
      mode: AeRowDialogMode.edit,
      schema: widget.schema,
      year: _year,
      month: _month,
      totalRooms: widget.profile.totalRooms,
      showCharges: _showCharges,
      initial: row,
    );
    if (rows == null || rows.isEmpty) return;
    final conflict = _roomConflict(rows, current);
    if (conflict != null) return _snack(conflict, error: true);
    final diffs = signOffDiffLines(row.toMap(), rows.first.toMap());
    if (rows.length == 1 && diffs.isEmpty) return _snack('No changes to save.');
    final signOff = await _sign(
      AeSignOffActions.editRow,
      AeRegisterService.rowLabel(rows.first),
      details: diffs,
    );
    if (signOff == null) return;
    await _run(
      () => AeRegisterService.applyChanges(profile: widget.profile, upserts: rows, signOff: signOff),
      success: 'Record updated and signed.',
    );
  }

  Future<void> _delete(AeRegisterRow row) async {
    final signOff = await _sign(AeSignOffActions.deleteRow, AeRegisterService.rowLabel(row));
    if (signOff == null) return;
    await _run(
      () => AeRegisterService.applyChanges(profile: widget.profile, deletes: [row], signOff: signOff),
      success: 'Record deleted and signed.',
    );
  }

  Future<void> _duplicateNext(AeRegisterRow row, List<AeRegisterRow> current) async {
    final next = AeRegisterRow(
      id: '',
      date: DateTime(row.date.year, row.date.month, row.date.day + 1),
      roomNo: row.roomNo,
      residence: row.residence,
      phRegion: row.phRegion,
      guests: row.guests,
      female: row.female,
      male: row.male,
      rate: row.rate,
    );
    final conflict = _roomConflict([next], current);
    if (conflict != null) return _snack(conflict, error: true);
    final signOff = await _sign(AeSignOffActions.stayAnotherNight, AeRegisterService.rowLabel(next));
    if (signOff == null) return;
    await _run(
      () => AeRegisterService.applyChanges(profile: widget.profile, upserts: [next], signOff: signOff),
      success: 'Guest stays another night: ${AeSheetKit.shortDate(next.date)}.',
    );
  }

  Future<void> _toggleZeroDay(int day, bool zero) async {
    final label = '${AeSheetKit.monthName(_month)} $day, $_year';
    final signOff = await _sign(
      zero ? AeSignOffActions.markNoGuests : AeSignOffActions.unmarkNoGuests,
      zero ? '$label — no guests that day' : '$label — "no guests" cleared',
    );
    if (signOff == null) return;
    await _run(() => AeRegisterService.setZeroDay(
          profile: widget.profile,
          year: _year,
          month: _month,
          day: day,
          zero: zero,
          signOff: signOff,
        ));
  }

  Future<void> _setSubmitted(bool submitted, AeMonthlyReport report, AeMonthTotals t) async {
    final period = '${AeSheetKit.monthName(_month)} $_year';
    final signOff = await _sign(
      submitted ? AeSignOffActions.submitMonth : AeSignOffActions.reopenMonth,
      submitted
          ? '$period · ${t.rowCount} record(s) · ${t.filledDays}/${report.days} days filled'
              '${widget.schema.tracksRooms ? ' · occupancy ${AeRegisterCalculator.pct(t.occupancyRate)}' : ''}'
          : '$period goes back to draft so it can be corrected.',
      details: submitted
          ? [
              '${t.checkIns} check-in(s) · ${t.guestNights} guest-night(s)',
              '${t.domesticArrivals} domestic · ${t.foreignArrivals} foreign · ${t.overseasFilipinoArrivals} overseas Filipino',
            ]
          : const [],
    );
    if (signOff == null) return;
    await _run(
      () => AeRegisterService.setSubmitted(
        profile: widget.profile,
        year: _year,
        month: _month,
        submitted: submitted,
        signOff: signOff,
      ),
      success: submitted ? 'Submitted to your LGU tourism office.' : 'Moved back to draft.',
    );
  }

  String _liveHashFor(List<AeRegisterRow> rows, AeMonthlyReport report) {
    if (!identical(rows, _hashedRows) || !identical(report.zeroDays, _hashedZeroDays)) {
      _hashedRows = rows;
      _hashedZeroDays = report.zeroDays;
      _liveHash = AeRegisterService.contentHashFor(rows, report.zeroDays);
    }
    return _liveHash;
  }

  AeMonthlyReport _virtualReport(AeMonthlyReport? r) =>
      (r ??
              AeMonthlyReport(
                id: AeMonthlyReport.docIdFor(widget.profile.aeId, _year, _month),
                aeId: widget.profile.aeId,
                year: _year,
                month: _month,
              ))
          .copyWith(
        aeName: widget.readOnly && r != null ? r.aeName : widget.profile.aeName,
        municipality: widget.readOnly && r != null ? r.municipality : widget.profile.municipality,
        municipalityId: widget.readOnly && r != null ? r.municipalityId : widget.profile.municipalityId,
        totalRooms: widget.readOnly && r != null ? r.totalRooms : widget.profile.totalRooms,
        aeType: widget.readOnly && r != null ? r.aeType : widget.profile.aeType,
        classificationCode: widget.readOnly && r != null ? r.classificationCode : widget.profile.classificationCode,
      );

  void _maybeRefreshHeader(AeMonthlyReport? r, List<AeRegisterRow> rows) {
    if (widget.readOnly || r == null) return;
    final p = widget.profile;
    final stale = r.totalRooms != p.totalRooms ||
        r.aeType != p.aeType ||
        r.classificationCode != p.classificationCode ||
        r.aeName != p.aeName;
    final key = '$_streamKey|${p.totalRooms}|${p.aeType}|${p.classificationCode}|${p.aeName}';
    if (!stale || _touchedKey == key) return;
    _touchedKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AeRegisterService.touchHeader(p, _year, _month).catchError((Object e) {
        debugPrint('[AeRegister] header refresh skipped: $e');
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    _ensureStreams();
    return StreamBuilder<AeMonthlyReport?>(
      stream: _reportStream,
      builder: (context, reportSnap) {
        return StreamBuilder<List<AeRegisterRow>>(
          stream: _rowsStream,
          builder: (context, rowsSnap) {
            final rows = rowsSnap.data ?? const <AeRegisterRow>[];
            final rawReport = reportSnap.data;
            _report = rawReport;
            _maybeRefreshHeader(rawReport, rows);
            final report = _virtualReport(rawReport);
            final liveHash = rowsSnap.hasData ? _liveHashFor(rows, report) : null;
            final totals = AeRegisterCalculator.totals(
              rows: rows,
              year: _year,
              month: _month,
              totalRooms: report.totalRooms,
              prevMonthLastDayGuests: report.prevMonthLastDayGuests,
              zeroDays: report.zeroDays,
            );
            final issues = AeRegisterCalculator.validate(
              rows: rows,
              year: _year,
              month: _month,
              totalRooms: report.totalRooms,
              tracksRooms: widget.schema.tracksRooms,
            );
            final loading = !rowsSnap.hasData && !rowsSnap.hasError;
            return Column(
              children: [
                _header(report, totals, issues.length, rows, liveHash),
                Expanded(
                  child: LayoutBuilder(builder: (context, c) {
                    final pad = c.maxWidth < 600 ? 12.0 : 20.0;
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(pad, 14, pad, 24),
                      children: [
                        if (widget.banner != null) ...[widget.banner!, const SizedBox(height: 12)],
                        if (rowsSnap.hasError)
                          Text('Could not load register: ${rowsSnap.error}', style: AeDashTokens.body(color: AeDashTokens.danger))
                        else if (loading)
                          const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                        else
                          _sheetBody(report, rows, totals, issues, liveHash),
                      ],
                    );
                  }),
                ),
                _sheetTabs(),
              ],
            );
          },
        );
      },
    );
  }

  Widget _header(
    AeMonthlyReport report,
    AeMonthTotals t,
    int issueCount,
    List<AeRegisterRow> rows,
    String? liveHash,
  ) {
    final s = widget.schema;
    final submitted = report.isSubmitted;
    final signed = report.lastSignOff;
    final tampered = signed != null &&
        liveHash != null &&
        signed.contentHash.isNotEmpty &&
        signed.contentHash != liveHash;
    final kpis = <(String, String, IconData, Color)>[
      if (s.tracksRooms) ('Occupancy', AeRegisterCalculator.pct(t.occupancyRate), Icons.hotel_rounded, AeDashTokens.accent),
      if (s.tracksNights) ('ALOS', '${AeRegisterCalculator.dec(t.alos)} n', Icons.nights_stay_rounded, AeDashTokens.chartSecondary),
      if (s.tracksNights) ('Guest-nights', '${t.guestNights}', Icons.bedtime_rounded, AeDashTokens.info),
      (s.tracksNights ? 'Check-ins' : 'Guests', '${t.checkIns}', Icons.login_rounded, AeDashTokens.success),
      if (s.tracksRooms) ('Persons / room', AeRegisterCalculator.dec(t.avgPersonsPerRoom), Icons.groups_rounded, AeDashTokens.chartTertiary),
      ('Sales', '₱${AeSheetKit.money(t.grandTotalSales)}', Icons.payments_rounded, AeDashTokens.warning),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: AeDashTokens.surface,
        border: Border(bottom: BorderSide(color: AeDashTokens.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AeDashTokens.border),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(onPressed: () => _shiftMonth(-1), icon: const Icon(Icons.chevron_left_rounded), tooltip: 'Previous month'),
                  InkWell(
                    onTap: _pickMonth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text('${AeSheetKit.monthName(_month)} $_year', style: AeDashTokens.section(size: 15)),
                    ),
                  ),
                  IconButton(onPressed: () => _shiftMonth(1), icon: const Icon(Icons.chevron_right_rounded), tooltip: 'Next month'),
                ]),
              ),
              _pill(
                submitted ? 'Submitted' : 'Draft',
                submitted ? AeDashTokens.success : AeDashTokens.warning,
                submitted ? Icons.verified_rounded : Icons.edit_note_rounded,
              ),
              if (issueCount > 0) _pill('$issueCount issue(s)', AeDashTokens.danger, Icons.error_outline_rounded),
              _pill('${t.filledDays}/${report.days} days filled', AeDashTokens.info, Icons.event_available_rounded),
              if (tampered)
                _pillButton('Changed after signing', AeDashTokens.danger, Icons.report_rounded)
              else if (signed != null)
                _pillButton(
                  'Signed: ${signed.name} · ${formatSignOffTime(signed.at)}',
                  AeDashTokens.chartSecondary,
                  Icons.draw_rounded,
                )
              else if (rows.isNotEmpty)
                _pillButton('No signature yet', AeDashTokens.muted, Icons.draw_outlined),
              if (_busy)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 10),
          if (s.tracksRooms && report.totalRooms <= 0 && !widget.readOnly)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(10),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.warning_amber_rounded, color: AeDashTokens.accent),
                  title: const Text('Set your total available rooms to compute occupancy.'),
                  trailing: widget.onOpenProfile == null
                      ? null
                      : TextButton(onPressed: widget.onOpenProfile, child: const Text('Open profile')),
                ),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final k in kpis)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: k.$4.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: k.$4.withValues(alpha: 0.25)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(k.$3, size: 16, color: k.$4),
                    const SizedBox(width: 8),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(k.$1, style: AeDashTokens.body(size: 10.5)),
                      Text(k.$2, style: AeDashTokens.number(size: 15)),
                    ]),
                  ]),
                ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _pill(String label, Color color, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(label, style: AeDashTokens.body(size: 12, color: color, weight: FontWeight.w800)),
        ]),
      );

  Widget _pillButton(String label, Color color, IconData icon) => InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => setState(() => _sheet = AeRegisterSheet.signoffs),
        child: _pill(label, color, icon),
      );

  Widget _sheetBody(
    AeMonthlyReport report,
    List<AeRegisterRow> rows,
    AeMonthTotals totals,
    List<AeRegisterIssue> issues,
    String? liveHash,
  ) {
    switch (_sheet) {
      case AeRegisterSheet.daily:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.readOnly) _dailyToolbar(rows),
            const SizedBox(height: 10),
            AeDailyRegisterTable(
              rows: rows,
              schema: widget.schema,
              issues: issues,
              showCharges: _showCharges,
              readOnly: widget.readOnly,
              onEdit: (r) => _edit(r, rows),
              onDelete: _delete,
              onDuplicateNext: (r) => _duplicateNext(r, rows),
            ),
          ],
        );
      case AeRegisterSheet.monthly:
        return AeMonthlyRecordTable(
          report: report,
          daily: AeRegisterCalculator.dailyTable(
            rows: rows,
            year: _year,
            month: _month,
            totalRooms: report.totalRooms,
            prevMonthLastDayGuests: report.prevMonthLastDayGuests,
            zeroDays: report.zeroDays,
          ),
          totals: totals,
          schema: widget.schema,
          readOnly: widget.readOnly,
          onToggleZeroDay: _toggleZeroDay,
        );
      case AeRegisterSheet.dae2:
        return AeDae2SummaryCard(
          report: report,
          totals: totals,
          readOnly: widget.readOnly,
          issueCount: issues.length,
          busy: _busy,
          onSubmit: () => _setSubmitted(true, report, totals),
          onWithdraw: () => _setSubmitted(false, report, totals),
        );
      case AeRegisterSheet.signoffs:
        return SignOffHistoryPanel(
          ownerId: widget.profile.aeId,
          subjectType: SignOffSubjects.aeRegister,
          subjectId: report.id,
          latest: report.lastSignOff,
          liveContentHash: liveHash,
          title: 'Sign-offs · ${AeSheetKit.monthName(_month)} $_year',
          emptyText: 'No signed saves for this month yet.',
        );
      case AeRegisterSheet.country:
        return AeCountryMatrixTable(
          byCountry: totals.byCountry,
          title: 'REPORT ON THE REGIONAL DISTRIBUTION OF TRAVELERS',
          periodLabel: '${AeSheetKit.monthName(_month)} $_year',
          aeName: report.aeName,
          aeType: report.aeType,
          municipality: report.municipality,
          province: report.province,
        );
    }
  }

  Widget _dailyToolbar(List<AeRegisterRow> rows) {
    final s = widget.schema;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AeDashTokens.panelDecoration(),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AeDashTokens.accent),
            onPressed: _busy ? null : () => _add(AeRowDialogMode.stay, rows),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(s.tracksNights ? 'Add stay (guests × nights)' : 'Add record'),
          ),
          if (s.tracksNights)
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _add(AeRowDialogMode.single, rows),
              icon: const Icon(Icons.post_add_rounded, size: 18),
              label: const Text('Add single night'),
            ),
          if (s.has(AeRegisterColumn.chargesA))
            FilterChip(
              selected: _showCharges,
              onSelected: (v) => setState(() => _showCharges = v),
              label: const Text('Show Charges (A)/(B)'),
            ),
          Text(
            'Each row = ${s.rowNoun}. Totals, occupancy and DAE sheets update automatically.',
            style: AeDashTokens.body(size: 12),
          ),
        ],
      ),
    );
  }

  Widget _sheetTabs() {
    const labels = {
      AeRegisterSheet.daily: ('Daily Register', Icons.edit_calendar_rounded),
      AeRegisterSheet.monthly: ('Monthly Record', Icons.calendar_view_month_rounded),
      AeRegisterSheet.dae2: ('Monthly Report (DAE-2)', Icons.summarize_rounded),
      AeRegisterSheet.country: ('By Country', Icons.public_rounded),
      AeRegisterSheet.signoffs: ('Sign-offs', Icons.draw_rounded),
    };
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
        border: Border(top: BorderSide(color: AeDashTokens.border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          for (final e in labels.entries)
            InkWell(
              onTap: () => setState(() => _sheet = e.key),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _sheet == e.key ? Colors.white : Colors.transparent,
                  border: Border(
                    bottom: BorderSide(
                      color: _sheet == e.key ? AeDashTokens.success : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Row(children: [
                  Icon(e.value.$2, size: 16, color: _sheet == e.key ? AeDashTokens.success : AeDashTokens.muted),
                  const SizedBox(width: 6),
                  Text(
                    e.value.$1,
                    style: AeDashTokens.body(
                      size: 12.5,
                      color: _sheet == e.key ? AeDashTokens.text : AeDashTokens.muted,
                      weight: _sheet == e.key ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
