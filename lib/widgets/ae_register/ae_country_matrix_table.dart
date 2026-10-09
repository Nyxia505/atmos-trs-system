import 'package:flutter/material.dart';

import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/utils/ae_register_calculator.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_sheet_kit.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';

/// "AE DAE-1B by Country (Sum)" — Report on the Regional Distribution of Travelers.
class AeCountryMatrixTable extends StatefulWidget {
  const AeCountryMatrixTable({
    super.key,
    required this.byCountry,
    required this.title,
    required this.periodLabel,
    this.aeName = '',
    this.aeType = '',
    this.municipality = '',
    this.province = 'Misamis Occidental',
  });

  final Map<String, AeCountryTotals> byCountry;
  final String title;
  final String periodLabel;
  final String aeName;
  final String aeType;
  final String municipality;
  final String province;

  @override
  State<AeCountryMatrixTable> createState() => _AeCountryMatrixTableState();
}

class _AeCountryMatrixTableState extends State<AeCountryMatrixTable> {
  bool _hideEmpty = false;

  @override
  Widget build(BuildContext context) {
    final lines = AeRegisterCalculator.countryMatrix(widget.byCountry);
    final head = AeSheetKit.cell(size: 11.5, weight: FontWeight.w800);
    const cols = <(String, double)>[
      ('COUNTRY OF RESIDENCE', 300),
      ('TOTAL Guest Arrivals', 110),
      ('TOTAL Guest Nights', 110),
      ('ALOS', 80),
      ('Female Arrivals', 96),
      ('Male Arrivals', 96),
      ('Validation', 84),
    ];
    final width = cols.fold<double>(0, (w, c) => w + c.$2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('DAE-1B (Sum)', style: AeDashTokens.body(size: 12, weight: FontWeight.w800, color: AeDashTokens.text)),
        const SizedBox(height: 4),
        Text(widget.title, style: AeDashTokens.heading(size: 16)),
        const SizedBox(height: 6),
        Wrap(spacing: 24, runSpacing: 2, children: [
          Text(widget.periodLabel, style: AeDashTokens.body(size: 12.5, color: AeDashTokens.text, weight: FontWeight.w700)),
          if (widget.aeName.isNotEmpty) Text('AE: ${widget.aeName}', style: AeDashTokens.body(size: 12.5)),
          if (widget.aeType.isNotEmpty) Text('AE Type: ${widget.aeType}', style: AeDashTokens.body(size: 12.5)),
          if (widget.municipality.isNotEmpty) Text('City/Municipality: ${widget.municipality}', style: AeDashTokens.body(size: 12.5)),
          Text('Province: ${widget.province}', style: AeDashTokens.body(size: 12.5)),
        ]),
        Row(children: [
          Checkbox(value: _hideEmpty, onChanged: (v) => setState(() => _hideEmpty = v ?? false)),
          Text('Hide countries with no guests', style: AeDashTokens.body(size: 12)),
        ]),
        AeSheetFrame(
          minWidth: width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                for (final c in cols)
                  AeCell(c.$1, width: c.$2, align: c == cols.first ? TextAlign.left : TextAlign.center, fill: const Color(0xFFFFFF66), style: head, height: 38),
              ]),
              for (final l in lines)
                if (!(_hideEmpty && l.kind == AeMatrixLineKind.country && (l.totals?.arrivals ?? 0) == 0 && (l.totals?.nights ?? 0) == 0))
                  _line(l, cols),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text('* Philippine passport holders permanently residing abroad; excludes overseas Filipino workers',
            style: AeDashTokens.body(size: 11)),
      ],
    );
  }

  Widget _line(AeCountryMatrixLine l, List<(String, double)> cols) {
    final (fill, color, weight, indent) = switch (l.kind) {
      AeMatrixLineKind.section => (AeSheetKit.sectionFill, Colors.white, FontWeight.w800, 0.0),
      AeMatrixLineKind.region => (AeSheetKit.sectionFill, Colors.white, FontWeight.w800, 0.0),
      AeMatrixLineKind.subregion => (AeSheetKit.sectionFill.withValues(alpha: 0.85), Colors.white, FontWeight.w700, 12.0),
      AeMatrixLineKind.country => (Colors.white, AeDashTokens.text, FontWeight.w600, 28.0),
      AeMatrixLineKind.subtotal => (AeSheetKit.subtotalFill, Colors.white, FontWeight.w800, 80.0),
      AeMatrixLineKind.total => (AeSheetKit.totalFill, AeDashTokens.text, FontWeight.w800, 0.0),
      AeMatrixLineKind.grand => (const Color(0xFFFFFF00), AeDashTokens.text, FontWeight.w900, 0.0),
      AeMatrixLineKind.breakdown => (AeSheetKit.totalFill.withValues(alpha: 0.6), AeDashTokens.text, FontWeight.w700, 12.0),
    };
    final t = l.totals;
    final style = AeSheetKit.cell(color: color, weight: weight, italic: l.kind == AeMatrixLineKind.country);
    String n(int v) => v == 0 ? '-' : '$v';
    return Row(children: [
      AeCell('', width: cols[0].$2, fill: fill, child: Padding(
        padding: EdgeInsets.only(left: indent),
        child: Text(l.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
      )),
      AeCell(t == null ? '' : n(t.arrivals), width: cols[1].$2, align: TextAlign.right, fill: fill, style: style),
      AeCell(t == null ? '' : n(t.nights), width: cols[2].$2, align: TextAlign.right, fill: fill, style: style),
      AeCell(t == null ? '' : (l.alos == null ? '-' : l.alos!.toStringAsFixed(2)), width: cols[3].$2, align: TextAlign.right, fill: fill, style: style),
      AeCell(t == null ? '' : n(t.female), width: cols[4].$2, align: TextAlign.right, fill: fill, style: style),
      AeCell(t == null ? '' : n(t.male), width: cols[5].$2, align: TextAlign.right, fill: fill, style: style),
      AeCell(
        t == null ? '' : (l.ok ? 'ok' : '!!!'),
        width: cols[6].$2,
        align: TextAlign.center,
        fill: const Color(0xFFF1F5F9),
        style: AeSheetKit.cell(weight: FontWeight.w800, color: l.ok ? AeDashTokens.success : AeDashTokens.danger),
      ),
    ]);
  }
}
