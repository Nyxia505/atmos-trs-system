import 'package:flutter/material.dart';

import 'package:atmos_trs_system/config/ae_register_schema.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/models/mice_register.dart';
import 'package:atmos_trs_system/services/ae_register_service.dart';
import 'package:atmos_trs_system/services/establishment_approval_service.dart';
import 'package:atmos_trs_system/services/mice_register_service.dart';
import 'package:atmos_trs_system/utils/ae_register_calculator.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_register_viewer_screen.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_sheet_kit.dart';
import 'package:atmos_trs_system/widgets/atmos_table_kit.dart';

enum _RegStatus { submitted, draft, missing }

enum _StatusFilter { all, submitted, draft, missing, miceMissing }

class _ComplianceLine {
  const _ComplianceLine({
    required this.aeId,
    required this.name,
    required this.category,
    required this.municipalityId,
    required this.municipality,
    required this.rooms,
    required this.status,
    this.report,
    this.daeApplies = true,
    this.hostsMice = false,
    this.mice,
  });

  final String aeId;
  final String name;
  final String category;
  final String municipalityId;
  final String municipality;
  final int rooms;
  final _RegStatus status;
  final AeMonthlyReport? report;

  /// False for event-only venues (no rooms): DAE status does not apply.
  final bool daeApplies;
  final bool hostsMice;
  final MiceMonthlyReport? mice;

  bool get tracksMice => hostsMice || mice != null;

  /// CUS month counts once submitted (including "no events" nil reports).
  _RegStatus get miceStatus {
    final m = mice;
    if (m == null) return _RegStatus.missing;
    if (m.isSubmitted) return _RegStatus.submitted;
    return m.totals.events > 0 ? _RegStatus.draft : _RegStatus.missing;
  }
}

/// Monthly DOT register (DAE-1B) status for every active lodging establishment.
///
/// LGU passes its [municipalityId]; OPTACA / Governor pass null for province-wide.
class AeRegisterCompliancePanel extends StatefulWidget {
  const AeRegisterCompliancePanel({
    super.key,
    this.municipalityId,
    this.primaryColor = const Color(0xFFF97316),
    this.textDark = const Color(0xFF1F2937),
    this.textMuted = const Color(0xFF6B7280),
  });

  final String? municipalityId;
  final Color primaryColor;
  final Color textDark;
  final Color textMuted;

  @override
  State<AeRegisterCompliancePanel> createState() => _AeRegisterCompliancePanelState();
}

const _kBorder = Color(0xFFE2E8F0);
const _kSubmitted = Color(0xFF059669);
const _kDraft = Color(0xFFD97706);
const _kMissing = Color(0xFFE11D48);

class _AeRegisterCompliancePanelState extends State<AeRegisterCompliancePanel> {
  late DateTime _month = _defaultMonth();
  _StatusFilter _filter = _StatusFilter.all;
  String _munFilter = '';

  Stream<List<EstablishmentRegistryEntry>>? _registry;
  Stream<List<AeMonthlyReport>>? _reports;
  String _reportsKey = '';
  Stream<List<MiceMonthlyReport>>? _mice;
  String _miceKey = '';

  /// Reports are due after the month closes, so default to last month.
  static DateTime _defaultMonth() {
    final now = DateTime.now();
    return DateTime(now.year, now.month - 1);
  }

  /// Same window as the hotel DAE-1B date picker: five years back through
  /// the current month. Past years list January–December; the current year
  /// stops at this month (future periods are not opened for reporting).
  static List<DateTime> _calendarMonths() {
    final now = DateTime.now();
    final startYear = now.year - 5;
    return [
      for (var year = startYear; year <= now.year; year++)
        for (var month = 1;
            month <= (year == now.year ? now.month : 12);
            month++)
          DateTime(year, month),
    ];
  }

  String get _mid => normalizeMunicipalityId(widget.municipalityId ?? '');
  bool get _province => _mid.isEmpty;

  Stream<List<EstablishmentRegistryEntry>> get _registryStream => _registry ??= _province
      ? EstablishmentApprovalService.watchAll()
      : EstablishmentApprovalService.watchForMunicipality(_mid);

  Stream<List<AeMonthlyReport>> get _reportsStream {
    final key = '${AeMonthlyReport.periodKeyFor(_month.year, _month.month)}|$_mid';
    if (_reports == null || key != _reportsKey) {
      _reportsKey = key;
      _reports = AeRegisterService.watchForPeriod(
        periodKey: AeMonthlyReport.periodKeyFor(_month.year, _month.month),
        municipalityId: _province ? null : _mid,
      );
    }
    return _reports!;
  }

  Stream<List<MiceMonthlyReport>> get _miceStream {
    final key = '${AeMonthlyReport.periodKeyFor(_month.year, _month.month)}|$_mid';
    if (_mice == null || key != _miceKey) {
      _miceKey = key;
      _mice = MiceRegisterService.watchForPeriod(
        periodKey: AeMonthlyReport.periodKeyFor(_month.year, _month.month),
        municipalityId: _province ? null : _mid,
      );
    }
    return _mice!;
  }

  List<_ComplianceLine> _lines(
    List<EstablishmentRegistryEntry> registry,
    List<AeMonthlyReport> reports,
    List<MiceMonthlyReport> mice,
  ) {
    final byAe = {for (final r in reports) r.aeId: r};
    final miceByAe = {for (final m in mice) m.aeId: m};
    final seen = <String>{};
    final out = <_ComplianceLine>[];

    _RegStatus statusOf(AeMonthlyReport? r) {
      if (r == null || (r.totals.rowCount == 0 && r.zeroDays.isEmpty)) return _RegStatus.missing;
      return r.isSubmitted ? _RegStatus.submitted : _RegStatus.draft;
    }

    for (final e in registry) {
      if (!e.isActive) continue;
      final r = byAe[e.id];
      final lodging = AeRegisterSchema.forCategory(e.category).tracksRooms;
      if (r == null && !lodging && !e.hostsMice && miceByAe[e.id] == null) continue;
      seen.add(e.id);
      out.add(
        _ComplianceLine(
          aeId: e.id,
          name: e.businessName,
          category: e.category,
          municipalityId: e.municipalityId,
          municipality: e.municipality,
          rooms: r != null && r.totalRooms > 0 ? r.totalRooms : (e.roomCount ?? 0),
          status: statusOf(r),
          report: r,
          daeApplies: lodging || r != null,
          hostsMice: e.hostsMice,
          mice: miceByAe[e.id],
        ),
      );
    }
    for (final r in reports) {
      if (seen.contains(r.aeId)) continue;
      seen.add(r.aeId);
      out.add(
        _ComplianceLine(
          aeId: r.aeId,
          name: r.aeName.isEmpty ? r.aeId : r.aeName,
          category: r.category,
          municipalityId: r.municipalityId,
          municipality: r.municipality,
          rooms: r.totalRooms,
          status: statusOf(r),
          report: r,
          mice: miceByAe[r.aeId],
        ),
      );
    }
    for (final m in mice) {
      if (seen.contains(m.aeId)) continue;
      out.add(
        _ComplianceLine(
          aeId: m.aeId,
          name: m.aeName.isEmpty ? m.aeId : m.aeName,
          category: m.category,
          municipalityId: m.municipalityId,
          municipality: m.municipality,
          rooms: 0,
          status: _RegStatus.missing,
          daeApplies: false,
          hostsMice: true,
          mice: m,
        ),
      );
    }
    out.sort((a, b) {
      final s = a.status.index.compareTo(b.status.index);
      return s != 0 ? s : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  void _open(_ComplianceLine l) {
    final r = l.report;
    AeRegisterViewerScreen.open(
      context,
      profile: AeRegisterViewerScreen.profileFor(
        aeId: l.aeId,
        aeName: l.name,
        category: l.category,
        municipalityId: l.municipalityId,
        municipality: l.municipality,
        totalRooms: l.rooms,
        aeType: r?.aeType ?? '',
        classificationCode: r?.classificationCode ?? '',
      ),
      year: _month.year,
      month: _month.month,
      showEvents: l.tracksMice,
      events: !l.daeApplies,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: StreamBuilder<List<EstablishmentRegistryEntry>>(
        stream: _registryStream,
        builder: (context, regSnap) => StreamBuilder<List<AeMonthlyReport>>(
          stream: _reportsStream,
          builder: (context, repSnap) => StreamBuilder<List<MiceMonthlyReport>>(
            stream: _miceStream,
            builder: (context, miceSnap) {
              final error = regSnap.error ?? repSnap.error;
              final loading = !regSnap.hasData || !repSnap.hasData;
              // MICE is additive: a failed / slow MICE query never blocks DAE status.
              final mice = miceSnap.data ?? const <MiceMonthlyReport>[];
              final all = loading ? const <_ComplianceLine>[] : _lines(regSnap.data!, repSnap.data!, mice);
              final municipalities = {
                for (final l in all)
                  if (l.municipality.trim().isNotEmpty) l.municipality.trim(),
              }.toList()..sort();
              final scoped = _munFilter.isEmpty ? all : all.where((l) => l.municipality.trim() == _munFilter).toList();
              final shown = scoped
                  .where(
                    (l) => switch (_filter) {
                      _StatusFilter.all => true,
                      _StatusFilter.submitted => l.daeApplies && l.status == _RegStatus.submitted,
                      _StatusFilter.draft => l.daeApplies && l.status == _RegStatus.draft,
                      _StatusFilter.missing => l.daeApplies && l.status == _RegStatus.missing,
                      _StatusFilter.miceMissing => l.tracksMice && l.miceStatus != _RegStatus.submitted,
                    },
                  )
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(municipalities),
                  const SizedBox(height: 14),
                  if (error != null)
                    _note(Icons.cloud_off_rounded, 'Could not load registers: $error', _kMissing)
                  else if (loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
                    )
                  else ...[
                    _kpis(scoped),
                    const SizedBox(height: 14),
                    _filters(scoped),
                    const SizedBox(height: 10),
                    if (shown.isEmpty)
                      _note(
                        Icons.inbox_outlined,
                        scoped.isEmpty
                            ? 'No active lodging establishments or event venues in scope yet.'
                            : 'No establishments with this status.',
                        widget.textMuted,
                      )
                    else
                      _table(shown),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _setPeriod({int? year, int? month}) {
    final allowed = _calendarMonths();
    final y = year ?? _month.year;
    final m = month ?? _month.month;
    final inYear = allowed.where((d) => d.year == y).toList();
    if (inYear.isEmpty) return;
    final next = inYear.firstWhere((d) => d.month == m, orElse: () => inYear.last);
    if (next.year == _month.year && next.month == _month.month) return;
    setState(() => _month = DateTime(next.year, next.month));
  }

  Widget _header(List<String> municipalities) {
    final allowed = _calendarMonths();
    final years = {for (final d in allowed) d.year}.toList()..sort();
    final year = years.contains(_month.year) ? _month.year : years.last;
    final monthsInYear = [
      for (final d in allowed)
        if (d.year == year) d.month,
    ]..sort();
    final month =
        monthsInYear.contains(_month.month) ? _month.month : monthsInYear.last;

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hotel DOT registers (DAE-1B)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: widget.textDark),
        ),
        const SizedBox(height: 2),
        Text(
          'Monthly guest register per establishment (DAE forms) and venue event logs (CUS MICE) — both feed Analytics.',
          style: TextStyle(fontSize: 12.5, color: widget.textMuted),
        ),
      ],
    );
    final yearPicker = _dropdown<int>(
      value: year,
      items: {for (final y in years) y: '$y'},
      icon: Icons.calendar_today_rounded,
      onChanged: (y) => _setPeriod(year: y),
    );
    final monthPicker = _dropdown<int>(
      value: month,
      items: {for (final m in monthsInYear) m: AeSheetKit.months[m - 1]},
      icon: Icons.calendar_month_rounded,
      onChanged: (m) => _setPeriod(month: m),
    );
    final munPicker = _province && municipalities.length > 1
        ? _dropdown<String>(
            value: municipalities.contains(_munFilter) ? _munFilter : '',
            items: {'': 'All municipalities', for (final m in municipalities) m: m},
            icon: Icons.location_city_rounded,
            onChanged: (m) => setState(() => _munFilter = m),
          )
        : null;
    return LayoutBuilder(
      builder: (context, c) {
        final pickers = Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            yearPicker,
            monthPicker,
            if (munPicker != null) munPicker,
          ],
        );
        if (c.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 10), pickers],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            pickers,
          ],
        );
      },
    );
  }

  Widget _dropdown<T>({
    required T value,
    required Map<T, String> items,
    required IconData icon,
    required ValueChanged<T> onChanged,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: widget.textMuted),
          const SizedBox(width: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isDense: true,
              borderRadius: BorderRadius.circular(10),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: widget.textDark),
              items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpis(List<_ComplianceLine> all) {
    final lines = all.where((l) => l.daeApplies).toList();
    final reports = [
      for (final l in lines)
        if (l.report != null && l.status != _RegStatus.missing) l.report!,
    ];
    final t = AeRegisterCalculator.combine(reports.map((r) => r.totals));
    final submitted = lines.where((l) => l.status == _RegStatus.submitted).length;
    final draft = lines.where((l) => l.status == _RegStatus.draft).length;
    final missing = lines.where((l) => l.status == _RegStatus.missing).length;
    final rooms = lines.fold<int>(0, (s, l) => s + l.rooms);
    final miceVenues = all.where((l) => l.tracksMice).toList();
    final miceSubmitted = miceVenues.where((l) => l.miceStatus == _RegStatus.submitted).length;
    final miceEvents = miceVenues.fold<int>(0, (s, l) => s + (l.mice?.totals.events ?? 0));
    final cards = <({
      String label,
      String value,
      IconData icon,
      Color color,
      VoidCallback? onTap,
    })>[
      (
        label: 'Submitted',
        value: '$submitted / ${lines.length}',
        icon: Icons.check_circle_rounded,
        color: const Color(0xFF34D399),
        onTap: () => setState(() => _filter = _StatusFilter.submitted),
      ),
      (
        label: 'Draft',
        value: '$draft',
        icon: Icons.description_rounded,
        color: const Color(0xFFFB923C),
        onTap: () => setState(() => _filter = _StatusFilter.draft),
      ),
      (
        label: 'Missing',
        value: '$missing',
        icon: Icons.error_rounded,
        color: const Color(0xFFFB7185),
        onTap: () => setState(() => _filter = _StatusFilter.missing),
      ),
      (
        label: 'Rooms',
        value: '$rooms',
        icon: Icons.king_bed_rounded,
        color: const Color(0xFFA78BFA),
        onTap: null,
      ),
      (
        label: 'Occupancy',
        value: AeRegisterCalculator.pct(
          AeRegisterCalculator.combinedOccupancy(reports),
          digits: 1,
        ),
        icon: Icons.star_rounded,
        color: const Color(0xFFFBBF24),
        onTap: null,
      ),
      (
        label: 'ALOS',
        value: AeRegisterCalculator.dec(t.alos),
        icon: Icons.person_rounded,
        color: const Color(0xFF38BDF8),
        onTap: null,
      ),
      (
        label: 'Guest-nights',
        value: '${t.guestNights}',
        icon: Icons.groups_rounded,
        color: const Color(0xFF2DD4BF),
        onTap: null,
      ),
      (
        label: 'Sales',
        value: _peso(t.grandTotalSales),
        icon: Icons.account_balance_wallet_rounded,
        color: const Color(0xFF4ADE80),
        onTap: null,
      ),
      if (miceVenues.isNotEmpty) ...[
        (
          label: 'MICE submitted',
          value: '$miceSubmitted / ${miceVenues.length}',
          icon: Icons.celebration_rounded,
          color: const Color(0xFFF472B6),
          onTap: () => setState(() => _filter = _StatusFilter.miceMissing),
        ),
        (
          label: 'MICE events',
          value: '$miceEvents',
          icon: Icons.event_rounded,
          color: const Color(0xFFC084FC),
          onTap: null,
        ),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.sync_rounded,
              size: 15,
              color: widget.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              'KEY PERFORMANCE METRICS',
              style: TextStyle(
                color: widget.textDark,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.85,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
            builder: (context, c) {
              const gap = 8.0;
              final scroll = c.maxWidth < 980;
              final tiles = [
                for (final k in cards)
                  _metricBox(
                    label: k.label,
                    value: k.value,
                    icon: k.icon,
                    color: k.color,
                    onTap: k.onTap,
                  ),
              ];
              if (scroll) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < tiles.length; i++) ...[
                        if (i > 0) const SizedBox(width: gap),
                        SizedBox(width: 152, child: tiles[i]),
                      ],
                    ],
                  ),
                );
              }
              return Row(
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    if (i > 0) const SizedBox(width: gap),
                    Expanded(child: tiles[i]),
                  ],
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _metricBox({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.95),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filters(List<_ComplianceLine> lines) {
    int count(_RegStatus s) => lines.where((l) => l.daeApplies && l.status == s).length;
    final miceVenues = lines.where((l) => l.tracksMice);
    final options = [
      (_StatusFilter.all, 'All', lines.length, widget.primaryColor),
      (_StatusFilter.submitted, 'Submitted', count(_RegStatus.submitted), _kSubmitted),
      (_StatusFilter.draft, 'Draft', count(_RegStatus.draft), _kDraft),
      (_StatusFilter.missing, 'Missing', count(_RegStatus.missing), _kMissing),
      if (miceVenues.isNotEmpty)
        (
          _StatusFilter.miceMissing,
          'MICE not submitted',
          miceVenues.where((l) => l.miceStatus != _RegStatus.submitted).length,
          const Color(0xFFDB2777),
        ),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          ChoiceChip(
            label: Text('${o.$2} · ${o.$3}'),
            selected: _filter == o.$1,
            showCheckmark: false,
            selectedColor: o.$4.withValues(alpha: 0.14),
            side: BorderSide(color: _filter == o.$1 ? o.$4 : _kBorder),
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: _filter == o.$1 ? o.$4 : widget.textDark,
            ),
            onSelected: (_) => setState(() => _filter = o.$1),
          ),
      ],
    );
  }

  Widget _table(List<_ComplianceLine> lines) {
    final cell = TextStyle(fontSize: 12.5, color: widget.textDark);
    Widget num(String value) => Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.right,
          style: cell,
        );
    return AtmosResponsiveTable(
      columns: const [
        AtmosTableColumn('Establishment', flex: 3, minWidth: 180),
        AtmosTableColumn('Status', minWidth: 108),
        AtmosTableColumn('Days filled', minWidth: 96, align: Alignment.centerRight),
        AtmosTableColumn('Rooms', minWidth: 72, align: Alignment.centerRight),
        AtmosTableColumn('Occupancy', minWidth: 96, align: Alignment.centerRight),
        AtmosTableColumn('ALOS', minWidth: 72, align: Alignment.centerRight),
        AtmosTableColumn('Guest-nights', minWidth: 112, align: Alignment.centerRight),
        AtmosTableColumn('Sales', minWidth: 96, align: Alignment.centerRight),
        AtmosTableColumn('MICE (CUS)', minWidth: 128),
        AtmosTableColumn('Open', minWidth: 108, flex: 1),
      ],
      rows: [
        for (final l in lines)
          [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: cell.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  [
                    if (l.category.isNotEmpty) l.category,
                    if (_province && l.municipality.isNotEmpty) l.municipality,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: widget.textMuted),
                ),
              ],
            ),
            _statusChip(l),
            num(l.report == null ? '—' : '${l.report!.totals.filledDays}/${l.report!.days}'),
            num(l.rooms > 0 ? '${l.rooms}' : '—'),
            num(
              l.status == _RegStatus.missing
                  ? '—'
                  : AeRegisterCalculator.pct(l.report!.totals.occupancyRate, digits: 1),
            ),
            num(l.status == _RegStatus.missing ? '—' : AeRegisterCalculator.dec(l.report!.totals.alos)),
            num(l.status == _RegStatus.missing ? '—' : '${l.report!.totals.guestNights}'),
            num(l.status == _RegStatus.missing ? '—' : _peso(l.report!.totals.grandTotalSales)),
            _miceCell(l, cell),
            TextButton.icon(
              onPressed: () => _open(l),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Open'),
              style: TextButton.styleFrom(
                foregroundColor: widget.primaryColor,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
      ],
    );
  }

  Widget _miceCell(_ComplianceLine l, TextStyle cell) {
    if (!l.tracksMice) return Text('—', style: TextStyle(fontSize: 12.5, color: widget.textMuted));
    final m = l.mice;
    final events = m?.totals.events ?? 0;
    final (label, color) = switch (l.miceStatus) {
      _RegStatus.submitted => (m!.isNilReport ? 'No events' : '$events event${events == 1 ? '' : 's'}', _kSubmitted),
      _RegStatus.draft => ('Draft · $events', _kDraft),
      _RegStatus.missing => ('Not logged', _kMissing),
    };
    return _pill(label, color);
  }

  Widget _statusChip(_ComplianceLine l) {
    if (!l.daeApplies) return _pill('No rooms', widget.textMuted);
    final (label, color) = switch (l.status) {
      _RegStatus.submitted => ('Submitted', _kSubmitted),
      _RegStatus.draft => ('Draft', _kDraft),
      _RegStatus.missing => ('Missing', _kMissing),
    };
    return _pill(label, color);
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }

  Widget _note(IconData icon, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(text, style: TextStyle(fontSize: 13, color: color)),
          ),
        ],
      ),
    );
  }

  static String _peso(double v) => v == 0 ? '—' : '₱${AeSheetKit.money(v)}';
}
