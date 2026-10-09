import 'dart:async';

import 'package:flutter/material.dart';

import 'package:atmos_trs_system/config/mice_event_types.dart';
import 'package:atmos_trs_system/models/mice_register.dart';
import 'package:atmos_trs_system/models/sign_off.dart';
import 'package:atmos_trs_system/services/ae_register_service.dart';
import 'package:atmos_trs_system/services/mice_register_service.dart';
import 'package:atmos_trs_system/utils/mice_register_calculator.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_sheet_kit.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';
import 'package:atmos_trs_system/widgets/mice_register/mice_event_dialog.dart';
import 'package:atmos_trs_system/widgets/mice_register/mice_event_table.dart';
import 'package:atmos_trs_system/widgets/mice_register/mice_summary_card.dart';
import 'package:atmos_trs_system/widgets/sign_off/sign_off_dialog.dart';
import 'package:atmos_trs_system/widgets/sign_off/sign_off_history_panel.dart';

enum MicePeriodMode { month, quarter, year }

enum MiceSheet { events, summary, signoffs }

enum MiceSort { date, attendees, hours, name }

/// CUS MICE events log for one venue. Month view is editable (signed saves);
/// quarter / year are read-only roll-ups. Read-only for LGU / OPTACA / Governor.
class MiceRegisterWorkspace extends StatefulWidget {
  const MiceRegisterWorkspace({
    super.key,
    required this.profile,
    this.readOnly = false,
    this.banner,
    this.initialYear,
    this.initialMonth,
  });

  final AeRegisterProfile profile;
  final bool readOnly;
  final Widget? banner;
  final int? initialYear;
  final int? initialMonth;

  @override
  State<MiceRegisterWorkspace> createState() => _MiceRegisterWorkspaceState();
}

class _MiceRegisterWorkspaceState extends State<MiceRegisterWorkspace> {
  late int _year;
  late int _month;
  MicePeriodMode _mode = MicePeriodMode.month;
  MiceSheet _sheet = MiceSheet.events;
  bool _busy = false;

  final Set<MiceCategory> _cats = {};
  bool _exhibitsOnly = false;
  bool _foreignOnly = false;
  String _query = '';
  MiceSort _sort = MiceSort.date;
  final _search = TextEditingController();

  String _streamKey = '';
  Stream<MiceMonthlyReport?>? _reportStream;
  Stream<List<MiceEvent>>? _eventsStream;
  MiceMonthlyReport? _report;

  StreamSubscription<List<MiceMonthlyReport>>? _headersSub;
  StreamSubscription<List<MiceEventType>>? _typesSub;
  List<MiceMonthlyReport> _headers = const [];
  List<MiceEventType> _customTypes = const [];

  String _rollupKey = '';
  Future<Map<String, List<MiceEvent>>>? _rollupFuture;

  List<MiceEvent>? _hashedEvents;
  String _liveHash = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = widget.initialYear ?? now.year;
    _month = widget.initialMonth ?? now.month;
    _headersSub = MiceRegisterService.watchForAe(widget.profile.aeId).listen(
      (h) {
        if (mounted) setState(() => _headers = h);
      },
      onError: (Object e) => debugPrint('[MICE] headers: $e'),
    );
    if (!widget.readOnly) {
      _typesSub = MiceRegisterService.watchCustomTypes(widget.profile.aeId).listen(
        (t) {
          if (mounted) setState(() => _customTypes = t);
        },
        onError: (Object e) => debugPrint('[MICE] custom types: $e'),
      );
    }
  }

  @override
  void dispose() {
    _headersSub?.cancel();
    _typesSub?.cancel();
    _search.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- period

  List<(int, int)> get _periodMonths {
    switch (_mode) {
      case MicePeriodMode.month:
        return [(_year, _month)];
      case MicePeriodMode.quarter:
        final q0 = ((_month - 1) ~/ 3) * 3 + 1;
        return [for (var m = q0; m < q0 + 3; m++) (_year, m)];
      case MicePeriodMode.year:
        return [for (var m = 1; m <= 12; m++) (_year, m)];
    }
  }

  String get _periodLabel => switch (_mode) {
        MicePeriodMode.month => '${AeSheetKit.monthName(_month)} $_year',
        MicePeriodMode.quarter => 'Q${(_month - 1) ~/ 3 + 1} $_year '
            '(${AeSheetKit.monthName(_periodMonths.first.$2).substring(0, 3)}–'
            '${AeSheetKit.monthName(_periodMonths.last.$2).substring(0, 3)})',
        MicePeriodMode.year => 'Year $_year',
      };

  void _shift(int delta) {
    final step = switch (_mode) {
      MicePeriodMode.month => 1,
      MicePeriodMode.quarter => 3,
      MicePeriodMode.year => 12,
    };
    final d = DateTime(_year, _month + delta * step);
    final now = DateTime.now();
    if (d.isAfter(DateTime(now.year + 1, 12))) return;
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
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDatePickerMode: DatePickerMode.year,
      helpText: 'Pick any day in the month to open',
    );
    if (picked == null) return;
    setState(() {
      _year = picked.year;
      _month = picked.month;
    });
  }

  void _openMonth(int year, int month) => setState(() {
        _mode = MicePeriodMode.month;
        _year = year;
        _month = month;
        _sheet = MiceSheet.events;
      });

  void _ensureMonthStreams() {
    final key = '${widget.profile.aeId}|$_year|$_month';
    if (key == _streamKey) return;
    _streamKey = key;
    _reportStream = MiceRegisterService.watchReport(widget.profile.aeId, _year, _month);
    _eventsStream = MiceRegisterService.watchEvents(widget.profile.aeId, _year, _month);
  }

  List<MiceMonthlyReport> get _periodHeaders {
    final keys = {for (final (y, m) in _periodMonths) y * 100 + m};
    return [for (final h in _headers) if (keys.contains(h.year * 100 + h.month)) h];
  }

  Future<Map<String, List<MiceEvent>>> _ensureRollup(List<MiceMonthlyReport> headers) {
    final key = [
      for (final h in headers) '${h.id}:${h.totals.events}:${h.updatedAt?.millisecondsSinceEpoch ?? 0}',
    ].join('|');
    if (key != _rollupKey || _rollupFuture == null) {
      _rollupKey = key;
      _rollupFuture = MiceRegisterService.fetchEventsForReports(headers);
    }
    return _rollupFuture!;
  }

  // ------------------------------------------------------------- filters

  bool get _filtered => _cats.isNotEmpty || _exhibitsOnly || _foreignOnly || _query.trim().isNotEmpty;

  List<MiceEvent> _apply(List<MiceEvent> events) {
    final q = _query.trim().toLowerCase();
    final out = events.where((e) {
      if (_cats.isNotEmpty && !_cats.contains(e.category)) return false;
      if (_exhibitsOnly && !e.hasExhibit) return false;
      if (_foreignOnly && e.foreign <= 0) return false;
      if (q.isNotEmpty) {
        final hay = '${e.eventName} ${e.eventType} ${e.organizerName} ${e.contactPerson} ${e.remarks}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
    switch (_sort) {
      case MiceSort.date:
        return MiceRegisterCalculator.sorted(out);
      case MiceSort.attendees:
        return out..sort((a, b) => b.total.compareTo(a.total));
      case MiceSort.hours:
        return out..sort((a, b) => b.hours.compareTo(a.hours));
      case MiceSort.name:
        return out..sort((a, b) => a.eventName.toLowerCase().compareTo(b.eventName.toLowerCase()));
    }
  }

  void _clearFilters() => setState(() {
        _cats.clear();
        _exhibitsOnly = false;
        _foreignOnly = false;
        _query = '';
        _search.clear();
      });

  // ------------------------------------------------------------- actions

  List<MiceEventType> get _types => MiceEventTypes.merged(_customTypes);

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

  /// Fresh signature for a save; null when cancelled (nothing is written).
  Future<SignOffRequest?> _sign(SignOffAction action, String summary, {List<String> details = const []}) async {
    final submitted = (_report?.isSubmitted ?? false) && action != MiceSignOffActions.submitMonth;
    final capture = await SignOffDialog.show(
      context,
      ownerId: widget.profile.aeId,
      action: action,
      summary: summary,
      details: details,
      requireReason: submitted,
      reasonHint: submitted || action.requiresReason ? 'e.g. organizer sent corrected head count' : null,
      notice: submitted && action != MiceSignOffActions.reopenMonth
          ? 'This month is already submitted — your LGU will see this change and your reason.'
          : null,
    );
    if (capture == null) return null;
    return SignOffRequest(action: action, capture: capture, summary: summary, details: details);
  }

  Future<void> _rememberType(MiceEventType? t) async {
    if (t == null) return;
    try {
      await MiceRegisterService.saveCustomType(widget.profile.aeId, t);
    } catch (e) {
      debugPrint('[MICE] custom type not saved: $e');
    }
  }

  String _monthNote(MiceEvent e) => e.dateStart.year != _year || e.dateStart.month != _month
      ? ' Saved under ${AeSheetKit.monthName(e.dateStart.month)} ${e.dateStart.year}.'
      : '';

  Future<void> _add({MiceEvent? from}) async {
    final res = await MiceEventDialog.show(
      context,
      year: _year,
      month: _month,
      types: _types,
      initial: from,
      duplicate: from != null,
    );
    if (res == null) return;
    final e = res.event;
    final signOff = await _sign(
      from == null ? MiceSignOffActions.addEvent : MiceSignOffActions.duplicateEvent,
      MiceRegisterService.eventLabel(e),
    );
    if (signOff == null) return;
    await _run(() async {
      await MiceRegisterService.applyChanges(profile: widget.profile, upserts: [e], signOff: signOff);
      await _rememberType(res.newType);
    }, success: 'Event ${from == null ? 'added' : 'duplicated'} and signed.${_monthNote(e)}');
  }

  Future<void> _edit(MiceEvent before) async {
    final res = await MiceEventDialog.show(context, year: _year, month: _month, types: _types, initial: before);
    if (res == null) return;
    final after = res.event;
    final diffs = signOffDiffLines(before.toMap(), after.toMap());
    if (diffs.isEmpty) return _snack('No changes to save.');
    final moved = before.dateStart.year != after.dateStart.year || before.dateStart.month != after.dateStart.month;
    final signOff = await _sign(MiceSignOffActions.editEvent, MiceRegisterService.eventLabel(after), details: diffs);
    if (signOff == null) return;
    await _run(() async {
      await MiceRegisterService.applyChanges(
        profile: widget.profile,
        upserts: [after],
        deletes: moved ? [before] : const [],
        signOff: signOff,
      );
      await _rememberType(res.newType);
    }, success: 'Event updated and signed.${_monthNote(after)}');
  }

  Future<void> _delete(MiceEvent e) async {
    final signOff = await _sign(MiceSignOffActions.deleteEvent, MiceRegisterService.eventLabel(e));
    if (signOff == null) return;
    await _run(
      () => MiceRegisterService.applyChanges(profile: widget.profile, deletes: [e], signOff: signOff),
      success: 'Event deleted and signed.',
    );
  }

  Future<void> _setSubmitted(bool submitted, MiceMonthTotals t) async {
    final signOff = await _sign(
      submitted ? MiceSignOffActions.submitMonth : MiceSignOffActions.reopenMonth,
      submitted
          ? (t.events == 0
              ? '$_periodLabel · no events this month (nil report)'
              : '$_periodLabel · ${t.events} event(s) · ${t.attendees} attendee(s) · ${MiceRegisterCalculator.hoursLabel(t.hours)} h')
          : '$_periodLabel goes back to draft so it can be corrected.',
      details: submitted && t.events > 0
          ? ['${t.local} local · ${t.foreign} foreign', '${t.male} male · ${t.female} female']
          : const [],
    );
    if (signOff == null) return;
    await _run(
      () => MiceRegisterService.setSubmitted(
        profile: widget.profile,
        year: _year,
        month: _month,
        submitted: submitted,
        signOff: signOff,
      ),
      success: submitted ? 'Submitted to your LGU tourism office.' : 'Moved back to draft.',
    );
  }

  String _liveHashFor(List<MiceEvent> events) {
    if (!identical(events, _hashedEvents)) {
      _hashedEvents = events;
      _liveHash = MiceRegisterService.contentHashFor(events);
    }
    return _liveHash;
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    if (_mode != MicePeriodMode.month) return _rollupBuild();
    _ensureMonthStreams();
    return StreamBuilder<MiceMonthlyReport?>(
      stream: _reportStream,
      builder: (context, reportSnap) => StreamBuilder<List<MiceEvent>>(
        stream: _eventsStream,
        builder: (context, eventsSnap) {
          final events = eventsSnap.data ?? const <MiceEvent>[];
          _report = reportSnap.data;
          final report = _report ??
              MiceMonthlyReport(
                id: MiceMonthlyReport.docIdFor(widget.profile.aeId, _year, _month),
                aeId: widget.profile.aeId,
                year: _year,
                month: _month,
                aeName: widget.profile.aeName,
                municipality: widget.profile.municipality,
              );
          final liveHash = eventsSnap.hasData ? _liveHashFor(events) : null;
          final totals = MiceRegisterCalculator.totals(events);
          final issueCount = events.where((e) => MiceRegisterCalculator.validate(e).isNotEmpty).length;
          return _scaffold(
            totals: totals,
            report: report,
            issueCount: issueCount,
            liveHash: liveHash,
            hasEvents: events.isNotEmpty,
            error: eventsSnap.error,
            loading: !eventsSnap.hasData && !eventsSnap.hasError,
            body: () => _sheetBody(
              events: events,
              totals: totals,
              report: report,
              issueCount: issueCount,
              liveHash: liveHash,
            ),
          );
        },
      ),
    );
  }

  Widget _rollupBuild() {
    final headers = _periodHeaders;
    return FutureBuilder<Map<String, List<MiceEvent>>>(
      future: _ensureRollup(headers),
      builder: (context, snap) {
        final byReport = snap.data ?? const <String, List<MiceEvent>>{};
        final events = MiceRegisterCalculator.sorted(byReport.values.expand((e) => e));
        final totals = MiceRegisterCalculator.totals(events);
        return _scaffold(
          totals: totals,
          report: null,
          issueCount: events.where((e) => MiceRegisterCalculator.validate(e).isNotEmpty).length,
          liveHash: null,
          hasEvents: events.isNotEmpty,
          error: snap.error,
          loading: snap.connectionState != ConnectionState.done && !snap.hasData,
          body: () => _sheetBody(
            events: events,
            totals: totals,
            report: null,
            issueCount: 0,
            liveHash: null,
            submittedMonths: headers.where((h) => h.isSubmitted).length,
          ),
        );
      },
    );
  }

  Widget _scaffold({
    required MiceMonthTotals totals,
    required MiceMonthlyReport? report,
    required int issueCount,
    required String? liveHash,
    required bool hasEvents,
    required Object? error,
    required bool loading,
    required Widget Function() body,
  }) {
    return Column(children: [
      _header(totals, report, issueCount, liveHash, hasEvents),
      Expanded(
        child: LayoutBuilder(builder: (context, c) {
          final pad = c.maxWidth < 600 ? 12.0 : 20.0;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(pad, 14, pad, 24),
            children: [
              if (widget.banner != null) ...[widget.banner!, const SizedBox(height: 12)],
              if (error != null)
                Text('Could not load events: $error', style: AeDashTokens.body(color: AeDashTokens.danger))
              else if (loading)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else
                body(),
            ],
          );
        }),
      ),
      _sheetTabs(),
    ]);
  }

  Widget _header(MiceMonthTotals t, MiceMonthlyReport? report, int issueCount, String? liveHash, bool hasEvents) {
    final signed = report?.lastSignOff;
    final tampered = signed != null && liveHash != null && signed.contentHash.isNotEmpty && signed.contentHash != liveHash;
    final kpis = <(String, String, IconData, Color)>[
      ('Events', '${t.events}', Icons.event_rounded, AeDashTokens.accent),
      ('Attendees', '${t.attendees}', Icons.groups_rounded, AeDashTokens.success),
      ('Foreign', '${t.foreign}', Icons.public_rounded, AeDashTokens.info),
      ('Hours', MiceRegisterCalculator.hoursLabel(t.hours), Icons.schedule_rounded, AeDashTokens.chartSecondary),
      ('Exhibits', '${t.exhibitions}', Icons.storefront_rounded, AeDashTokens.warning),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: AeDashTokens.surface,
        border: Border(bottom: BorderSide(color: AeDashTokens.border)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SegmentedButton<MicePeriodMode>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(value: MicePeriodMode.month, label: Text('Month')),
              ButtonSegment(value: MicePeriodMode.quarter, label: Text('Quarter')),
              ButtonSegment(value: MicePeriodMode.year, label: Text('Year')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() {
              _mode = s.first;
              if (_mode != MicePeriodMode.month && _sheet == MiceSheet.signoffs) _sheet = MiceSheet.events;
            }),
          ),
          Container(
            decoration: BoxDecoration(border: Border.all(color: AeDashTokens.border), borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left_rounded), tooltip: 'Previous'),
              InkWell(
                onTap: _pickMonth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(_periodLabel, style: AeDashTokens.section(size: 15)),
                ),
              ),
              IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right_rounded), tooltip: 'Next'),
            ]),
          ),
          if (report != null)
            _pill(
              report.isSubmitted ? (report.isNilReport ? 'Submitted · no events' : 'Submitted') : 'Draft',
              report.isSubmitted ? AeDashTokens.success : AeDashTokens.warning,
              report.isSubmitted ? Icons.verified_rounded : Icons.edit_note_rounded,
            )
          else
            _pill(
              '${_periodHeaders.where((h) => h.isSubmitted).length}/${_periodMonths.length} months submitted',
              AeDashTokens.info,
              Icons.fact_check_rounded,
            ),
          if (issueCount > 0) _pill('$issueCount with errors', AeDashTokens.danger, Icons.error_outline_rounded),
          if (report != null)
            if (tampered)
              _pillButton('Changed after signing', AeDashTokens.danger, Icons.report_rounded)
            else if (signed != null)
              _pillButton('Signed: ${signed.name} · ${formatSignOffTime(signed.at)}', AeDashTokens.chartSecondary, Icons.draw_rounded)
            else if (hasEvents)
              _pillButton('No signature yet', AeDashTokens.muted, Icons.draw_outlined),
          if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
        ]),
        const SizedBox(height: 10),
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
      ]),
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
        onTap: () => setState(() => _sheet = MiceSheet.signoffs),
        child: _pill(label, color, icon),
      );

  Widget _sheetBody({
    required List<MiceEvent> events,
    required MiceMonthTotals totals,
    required MiceMonthlyReport? report,
    required int issueCount,
    required String? liveHash,
    int submittedMonths = 0,
  }) {
    final venue = report?.aeName.isNotEmpty == true ? report!.aeName : widget.profile.aeName;
    final municipality = report?.municipality.isNotEmpty == true ? report!.municipality : widget.profile.municipality;
    switch (_sheet) {
      case MiceSheet.events:
        final visible = _apply(events);
        final cn = <String, int>{};
        final byMonth = <int, List<MiceEvent>>{};
        for (final e in events) {
          byMonth.putIfAbsent(e.dateStart.year * 100 + e.dateStart.month, () => []).add(e);
        }
        for (final list in byMonth.values) {
          cn.addAll(MiceRegisterCalculator.controlNumbers(list));
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _toolbar(events),
          const SizedBox(height: 10),
          MiceEventTable(
            events: visible,
            controlNumbers: cn,
            readOnly: widget.readOnly,
            totalCount: _filtered ? events.length : null,
            showMonth: _mode != MicePeriodMode.month,
            onEdit: _edit,
            onDuplicate: (e) => _add(from: e),
            onDelete: _delete,
            onOpenMonth: (e) => _openMonth(e.dateStart.year, e.dateStart.month),
          ),
          if (_filtered)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('TOTAL row reflects the filtered events only.', style: AeDashTokens.body(size: 11.5)),
            ),
        ]);
      case MiceSheet.summary:
        return MiceSummaryCard(
          totals: totals,
          periodLabel: _periodLabel,
          venueName: venue,
          municipality: municipality,
          readOnly: widget.readOnly,
          report: report,
          issueCount: issueCount,
          busy: _busy,
          monthsInPeriod: _periodMonths.length,
          submittedMonths: submittedMonths,
          onSubmit: () => _setSubmitted(true, totals),
          onWithdraw: () => _setSubmitted(false, totals),
        );
      case MiceSheet.signoffs:
        if (report == null) {
          return Text('Open a single month to see its sign-offs.', style: AeDashTokens.body(size: 12.5));
        }
        return SignOffHistoryPanel(
          ownerId: widget.profile.aeId,
          subjectType: SignOffSubjects.miceRegister,
          subjectId: report.id,
          latest: report.lastSignOff,
          liveContentHash: liveHash,
          title: 'Sign-offs · $_periodLabel',
          emptyText: 'No signed saves for this month yet.',
        );
    }
  }

  Widget _toolbar(List<MiceEvent> events) {
    final present = {for (final e in events) e.category};
    final canAdd = !widget.readOnly && _mode == MicePeriodMode.month;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: AeDashTokens.panelDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (canAdd)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AeDashTokens.accent),
              onPressed: _busy ? null : () => _add(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add event'),
            ),
          SizedBox(
            width: 240,
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search event, type, organizer…',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          FilterChip(
            selected: _exhibitsOnly,
            onSelected: (v) => setState(() => _exhibitsOnly = v),
            avatar: const Icon(Icons.storefront_rounded, size: 16),
            label: const Text('Exhibits only'),
          ),
          FilterChip(
            selected: _foreignOnly,
            onSelected: (v) => setState(() => _foreignOnly = v),
            avatar: const Icon(Icons.public_rounded, size: 16),
            label: const Text('With foreign guests'),
          ),
          DropdownButton<MiceSort>(
            value: _sort,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: MiceSort.date, child: Text('Sort: date (CN)')),
              DropdownMenuItem(value: MiceSort.attendees, child: Text('Sort: most attendees')),
              DropdownMenuItem(value: MiceSort.hours, child: Text('Sort: longest')),
              DropdownMenuItem(value: MiceSort.name, child: Text('Sort: event name')),
            ],
            onChanged: (v) => setState(() => _sort = v ?? MiceSort.date),
          ),
          if (_filtered) TextButton.icon(onPressed: _clearFilters, icon: const Icon(Icons.clear_rounded, size: 16), label: const Text('Clear filters')),
        ]),
        if (present.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in MiceCategory.values)
              if (present.contains(c) || _cats.contains(c))
                FilterChip(
                  selected: _cats.contains(c),
                  avatar: Icon(c.icon, size: 15),
                  label: Text('${c.label} (${events.where((e) => e.category == c).length})'),
                  selectedColor: AeDashTokens.softAccent,
                  onSelected: (v) => setState(() => v ? _cats.add(c) : _cats.remove(c)),
                ),
          ]),
        ],
        if (canAdd)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'One row per event (multi-day = one row). CN, totals and the CUS MICE report update automatically.',
              style: AeDashTokens.body(size: 12),
            ),
          ),
      ]),
    );
  }

  Widget _sheetTabs() {
    final labels = <MiceSheet, (String, IconData)>{
      MiceSheet.events: ('Events (CUS by establishment)', Icons.event_note_rounded),
      MiceSheet.summary: ('Summary', Icons.summarize_rounded),
      if (_mode == MicePeriodMode.month) MiceSheet.signoffs: ('Sign-offs', Icons.draw_rounded),
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
                    bottom: BorderSide(color: _sheet == e.key ? AeDashTokens.success : Colors.transparent, width: 3),
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
