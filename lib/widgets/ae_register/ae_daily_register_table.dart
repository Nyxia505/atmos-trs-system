import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:atmos_trs_system/config/ae_register_schema.dart';
import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/utils/ae_register_calculator.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_sheet_kit.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';

/// DailyRecord sheet: one line per register row with sales + sex validation.
class AeDailyRegisterTable extends StatefulWidget {
  const AeDailyRegisterTable({
    super.key,
    required this.rows,
    required this.schema,
    required this.issues,
    required this.showCharges,
    required this.readOnly,
    this.onEdit,
    this.onDelete,
    this.onDuplicateNext,
  });

  final List<AeRegisterRow> rows;
  final AeRegisterSchema schema;
  final List<AeRegisterIssue> issues;
  final bool showCharges;
  final bool readOnly;
  final ValueChanged<AeRegisterRow>? onEdit;
  final ValueChanged<AeRegisterRow>? onDelete;
  final ValueChanged<AeRegisterRow>? onDuplicateNext;

  @override
  State<AeDailyRegisterTable> createState() => _AeDailyRegisterTableState();
}

class _AeDailyRegisterTableState extends State<AeDailyRegisterTable> {
  int? _dayFilter;
  AeDailyRegisterSort _sort = AeDailyRegisterSort.newestDate;
  final _hScroll = ScrollController();
  final _vScroll = ScrollController();

  static const _headerFill = Color(0xFFFFF7ED);
  static const _rowAlt = Color(0xFFF8FAFC);
  static const _totalFill = Color(0xFFFFF7ED);
  static const _border = Color(0xFFE5E7EB);
  static const _darkText = Color(0xFF1F2937);
  static const _mutedText = Color(0xFF64748B);

  @override
  void dispose() {
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  String _peso(double v) {
    final m = AeSheetKit.money(v);
    if (m == '-') return '₱0.00';
    return '₱$m';
  }

  /// Base (unscaled) column widths. Flex columns grow when the viewport is wider.
  List<(String, double, TextAlign, bool)> _baseColumns(AeRegisterSchema s) {
    return [
      ('#', 48, TextAlign.center, false),
      ('Date', 104, TextAlign.center, false),
      if (s.tracksRooms) ('Room', 70, TextAlign.center, false),
      ('Residence / Nationality', 240, TextAlign.left, true),
      if (s.has(AeRegisterColumn.phRegion)) ('PH origin', 200, TextAlign.left, true),
      (s.guestsLabel, 92, TextAlign.center, false),
      if (s.tracksNights) ('Checked-in day', 108, TextAlign.center, false),
      (s.rateLabel, 112, TextAlign.center, false),
      if (widget.showCharges && s.has(AeRegisterColumn.chargesA))
        ('Charges (A)', 100, TextAlign.center, false),
      if (widget.showCharges && s.has(AeRegisterColumn.chargesB))
        ('Charges (B)', 100, TextAlign.center, false),
      if (widget.showCharges) ('Subtotal', 108, TextAlign.center, false),
      ('Female', 64, TextAlign.center, false),
      ('Male', 64, TextAlign.center, false),
      ('Validation', 108, TextAlign.center, false),
      ('Encoded by', 150, TextAlign.left, true),
      if (!widget.readOnly) ('Actions', 118, TextAlign.center, false),
    ];
  }

  /// Stretch flex columns first; if still short of [available], scale everything.
  List<(String, double, TextAlign)> _fitColumns(
    List<(String, double, TextAlign, bool)> base,
    double available,
  ) {
    final minTotal = base.fold<double>(0, (w, c) => w + c.$2);
    if (!available.isFinite || available <= 0) {
      return [for (final c in base) (c.$1, c.$2, c.$3)];
    }
    if (available <= minTotal) {
      return [for (final c in base) (c.$1, c.$2, c.$3)];
    }

    final extra = available - minTotal;
    final flexTotal = base.where((c) => c.$4).fold<double>(0, (w, c) => w + c.$2);
    if (flexTotal <= 0) {
      final scale = available / minTotal;
      return [for (final c in base) (c.$1, c.$2 * scale, c.$3)];
    }

    final flexed = <(String, double, TextAlign)>[
      for (final c in base)
        (
          c.$1,
          c.$4 ? c.$2 + extra * (c.$2 / flexTotal) : c.$2,
          c.$3,
        ),
    ];
    final flexedTotal = flexed.fold<double>(0, (w, c) => w + c.$2);
    if (flexedTotal + 0.5 >= available) return flexed;
    final scale = available / flexedTotal;
    return [for (final c in flexed) (c.$1, c.$2 * scale, c.$3)];
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.schema;
    final issuesByRow = <String, List<String>>{};
    for (final i in widget.issues) {
      if (i.rowId.isEmpty) continue;
      issuesByRow.putIfAbsent(i.rowId, () => []).add(i.message);
    }
    final days = {for (final r in widget.rows) r.day}.toList()
      ..sort((a, b) => b.compareTo(a));
    final filtered = _dayFilter == null
        ? widget.rows
        : widget.rows.where((r) => r.day == _dayFilter).toList();
    final visible = AeRegisterCalculator.sortDailyRegisterRows(
      filtered,
      sort: _sort,
    );

    final screenH = MediaQuery.sizeOf(context).height;
    final tableBodyMaxH = (screenH * 0.48).clamp(280.0, 560.0);
    final headStyle = GoogleFonts.inter(
      fontSize: 11.5,
      fontWeight: FontWeight.w800,
      color: _darkText,
      letterSpacing: -0.1,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(
          visibleCount: visible.length,
          totalCount: widget.rows.length,
          days: days,
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth;
            final cols = _fitColumns(_baseColumns(s), available);
            final tableWidth = cols.fold<double>(0, (w, c) => w + c.$2);

            return DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Scrollbar(
                  controller: _hScroll,
                  thumbVisibility: tableWidth > available + 1,
                  notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _hScroll,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: tableWidth < available ? available : tableWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              for (final c in cols)
                                _cell(
                                  c.$1,
                                  width: c.$2,
                                  align: TextAlign.center,
                                  fill: _headerFill,
                                  style: headStyle,
                                  height: 42,
                                  boldBorder: true,
                                ),
                            ],
                          ),
                          ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: tableBodyMaxH),
                            child: Scrollbar(
                              controller: _vScroll,
                              thumbVisibility: visible.length > 8,
                              child: SingleChildScrollView(
                                controller: _vScroll,
                                child: Column(
                                  children: [
                                    if (visible.isEmpty)
                                      SizedBox(
                                        height: 96,
                                        child: Center(
                                          child: Text(
                                            widget.readOnly
                                                ? 'No register rows for this month.'
                                                : 'No rows yet — use "Add Stay" to record guests (${s.rowNoun} per row).',
                                            style: AeDashTokens.body(size: 12.5),
                                          ),
                                        ),
                                      ),
                                    for (var i = 0; i < visible.length; i++)
                                      _row(i, visible[i], issuesByRow[visible[i].id], cols),
                                    if (visible.isNotEmpty)
                                      _totalsRow(cols, visible, s, headStyle),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _toolbar({
    required int visibleCount,
    required int totalCount,
    required List<int> days,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '$visibleCount of $totalCount rows',
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: _darkText,
            ),
          ),
          _filterChip(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                value: _dayFilter,
                isDense: true,
                borderRadius: BorderRadius.circular(10),
                style: GoogleFonts.inter(fontSize: 12.5, color: _darkText, fontWeight: FontWeight.w600),
                hint: Text('All days', style: GoogleFonts.inter(fontSize: 12.5, color: _mutedText)),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('All days')),
                  for (final d in days)
                    DropdownMenuItem<int?>(value: d, child: Text('Day $d')),
                ],
                onChanged: (v) => setState(() => _dayFilter = v),
              ),
            ),
          ),
          _filterChip(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<AeDailyRegisterSort>(
                value: _sort,
                isDense: true,
                borderRadius: BorderRadius.circular(10),
                style: GoogleFonts.inter(fontSize: 12.5, color: _darkText, fontWeight: FontWeight.w600),
                items: const [
                  DropdownMenuItem(
                    value: AeDailyRegisterSort.newestDate,
                    child: Text('Newest date first'),
                  ),
                  DropdownMenuItem(
                    value: AeDailyRegisterSort.oldestDate,
                    child: Text('Oldest date first'),
                  ),
                  DropdownMenuItem(
                    value: AeDailyRegisterSort.recentlyAdded,
                    child: Text('Recently added'),
                  ),
                  DropdownMenuItem(
                    value: AeDailyRegisterSort.recentlyUpdated,
                    child: Text('Recently updated'),
                  ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _sort = v);
                },
              ),
            ),
          ),
          if (widget.issues.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline_rounded, size: 15, color: AeDashTokens.danger),
                  const SizedBox(width: 5),
                  Text(
                    '${widget.issues.length} validation issue(s)',
                    style: AeDashTokens.body(
                      size: 12,
                      color: AeDashTokens.danger,
                      weight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _totalsRow(
    List<(String, double, TextAlign)> cols,
    List<AeRegisterRow> visible,
    AeRegisterSchema s,
    TextStyle headStyle,
  ) {
    double sum(double Function(AeRegisterRow r) f) =>
        visible.fold<double>(0, (t, r) => t + f(r));

    return Row(
      children: [
        for (final c in cols)
          switch (c.$1) {
            '#' => _cell('', width: c.$2, fill: _totalFill, height: 38),
            'Date' => _cell(
                'TOTAL',
                width: c.$2,
                align: TextAlign.center,
                fill: _totalFill,
                style: headStyle,
                height: 38,
              ),
            final l when l == s.guestsLabel => _cell(
                '${sum((r) => r.guests.toDouble()).round()}',
                width: c.$2,
                align: TextAlign.center,
                fill: _totalFill,
                style: headStyle,
                height: 38,
              ),
            final l when l == s.rateLabel => _cell(
                _peso(sum((r) => r.rate)),
                width: c.$2,
                align: TextAlign.center,
                fill: _totalFill,
                style: headStyle,
                height: 38,
              ),
            'Charges (A)' => _cell(
                _peso(sum((r) => r.chargesA)),
                width: c.$2,
                align: TextAlign.center,
                fill: _totalFill,
                style: headStyle,
                height: 38,
              ),
            'Charges (B)' => _cell(
                _peso(sum((r) => r.chargesB)),
                width: c.$2,
                align: TextAlign.center,
                fill: _totalFill,
                style: headStyle,
                height: 38,
              ),
            'Subtotal' => _cell(
                _peso(sum((r) => r.subtotal)),
                width: c.$2,
                align: TextAlign.center,
                fill: _totalFill,
                style: headStyle,
                height: 38,
              ),
            'Female' => _cell(
                '${sum((r) => r.female.toDouble()).round()}',
                width: c.$2,
                align: TextAlign.center,
                fill: _totalFill,
                style: headStyle,
                height: 38,
              ),
            'Male' => _cell(
                '${sum((r) => r.male.toDouble()).round()}',
                width: c.$2,
                align: TextAlign.center,
                fill: _totalFill,
                style: headStyle,
                height: 38,
              ),
            _ => _cell('', width: c.$2, fill: _totalFill, height: 38),
          },
      ],
    );
  }

  Widget _filterChip({required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: child,
    );
  }

  Widget _cell(
    String text, {
    required double width,
    TextAlign align = TextAlign.left,
    Color? fill,
    TextStyle? style,
    double height = 40,
    Widget? child,
    bool boldBorder = false,
  }) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: switch (align) {
        TextAlign.right || TextAlign.end => Alignment.centerRight,
        TextAlign.center => Alignment.center,
        _ => Alignment.centerLeft,
      },
      decoration: BoxDecoration(
        color: fill,
        border: Border(
          right: BorderSide(color: _border, width: boldBorder ? 1 : 0.8),
          bottom: BorderSide(color: _border, width: boldBorder ? 1.2 : 0.8),
        ),
      ),
      child: child ??
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: style ??
                GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _darkText,
                ),
          ),
    );
  }

  Widget _row(
    int index,
    AeRegisterRow r,
    List<String>? issues,
    List<(String, double, TextAlign)> cols,
  ) {
    final s = widget.schema;
    final ok = r.female + r.male == r.guests;
    final hasIssue = issues != null && issues.isNotEmpty;
    final fill = hasIssue
        ? const Color(0xFFFEF2F2)
        : (index.isEven ? Colors.white : _rowAlt);
    final body = GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: _darkText);
    final muted = GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: _mutedText);
    final cells = <Widget>[];

    for (final c in cols) {
      final w = c.$2;
      final a = c.$3;
      switch (c.$1) {
        case '#':
          cells.add(_cell('${index + 1}', width: w, align: a, fill: fill, height: 40, style: muted));
        case 'Date':
          cells.add(_cell(
            AeSheetKit.shortDate(r.date),
            width: w,
            align: TextAlign.center,
            fill: fill,
            height: 40,
            style: body,
          ));
        case 'Room':
          cells.add(_cell(r.roomNo, width: w, align: a, fill: fill, height: 40, style: body));
        case 'Residence / Nationality':
          cells.add(_cell(r.residence, width: w, fill: fill, height: 40, style: body));
        case 'PH origin':
          cells.add(_cell(
            r.phRegion.trim().isEmpty ? '—' : r.phRegion,
            width: w,
            fill: fill,
            height: 40,
            style: muted,
          ));
        case 'Checked-in day':
          cells.add(_cell(
            r.checkedInDay ? 'Yes' : 'No',
            width: w,
            align: a,
            fill: fill,
            height: 40,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: r.checkedInDay ? FontWeight.w800 : FontWeight.w500,
              color: r.checkedInDay ? AeDashTokens.success : _darkText,
            ),
          ));
        case 'Charges (A)':
          cells.add(_cell(_peso(r.chargesA), width: w, align: a, fill: fill, height: 40, style: body));
        case 'Charges (B)':
          cells.add(_cell(_peso(r.chargesB), width: w, align: a, fill: fill, height: 40, style: body));
        case 'Subtotal':
          cells.add(_cell(_peso(r.subtotal), width: w, align: a, fill: fill, height: 40, style: body));
        case 'Female':
          cells.add(_cell('${r.female}', width: w, align: a, fill: fill, height: 40, style: body));
        case 'Male':
          cells.add(_cell('${r.male}', width: w, align: a, fill: fill, height: 40, style: body));
        case 'Validation':
          cells.add(_cell(
            '',
            width: w,
            align: a,
            fill: fill,
            height: 40,
            child: Tooltip(
              message: hasIssue ? issues.join('\n') : 'OK',
              child: _validationBadge(hasIssue: hasIssue, ok: ok),
            ),
          ));
        case 'Encoded by':
          final au = r.audit;
          cells.add(_cell(
            '',
            width: w,
            fill: fill,
            height: 40,
            child: Tooltip(
              message: au.isEmpty
                  ? 'Saved before sign-offs were required'
                  : [
                      '${au.encodedBy} · ${au.encodedPosition}',
                      if (au.createdBy.isNotEmpty && au.createdBy != au.encodedBy)
                        'First entered by ${au.createdBy}',
                    ].join('\n'),
              child: Text(
                au.isEmpty ? '—' : au.encodedBy,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: au.isEmpty ? muted : body,
              ),
            ),
          ));
        case 'Actions':
          cells.add(_cell(
            '',
            width: w,
            align: a,
            fill: fill,
            height: 40,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _icon(Icons.edit_rounded, 'Edit', () => widget.onEdit?.call(r), color: AeDashTokens.accent),
                if (s.tracksNights)
                  _icon(Icons.redo_rounded, 'Copy to next night', () => widget.onDuplicateNext?.call(r)),
                _icon(
                  Icons.delete_outline_rounded,
                  'Delete',
                  () => widget.onDelete?.call(r),
                  color: AeDashTokens.danger,
                ),
              ],
            ),
          ));
        default:
          if (c.$1 == s.guestsLabel) {
            cells.add(_cell(
              '${r.guests}',
              width: w,
              align: a,
              fill: fill,
              height: 40,
              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: _darkText),
            ));
          } else if (c.$1 == s.rateLabel) {
            cells.add(_cell(_peso(r.rate), width: w, align: a, fill: fill, height: 40, style: body));
          } else {
            cells.add(_cell('', width: w, fill: fill, height: 40));
          }
      }
    }
    return AeHoverRow(
      child: InkWell(
        onTap: widget.readOnly ? null : () => widget.onEdit?.call(r),
        child: Row(children: cells),
      ),
    );
  }

  Widget _validationBadge({required bool hasIssue, required bool ok}) {
    final bad = hasIssue;
    final bg = bad ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7);
    final fg = bad ? const Color(0xFFB91C1C) : const Color(0xFF15803D);
    final label = bad ? (ok ? 'Check' : 'Error') : 'OK';
    final icon = bad ? Icons.error_rounded : Icons.check_circle_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.inter(fontSize: 11, color: fg, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _icon(
    IconData icon,
    String tip,
    VoidCallback onTap, {
    Color color = AeDashTokens.muted,
  }) =>
      IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        iconSize: 17,
        color: color,
        onPressed: onTap,
        icon: Icon(icon),
      );
}
