import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:atmos_trs_system/models/ae_register.dart';
import 'package:atmos_trs_system/utils/ae_register_calculator.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_sheet_kit.dart';
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

  static const _primary = Color(0xFFF97316);
  static const _darkOrange = Color(0xFFEA580C);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _border = Color(0xFFE5E7EB);
  static const _darkText = Color(0xFF1F2937);
  static const _mutedText = Color(0xFF64748B);
  static const _rowAlt = Color(0xFFF8FAFC);
  static const _subtotalFill = Color(0xFFFFEDD5);
  static const _grandFill = Color(0xFFFED7AA);

  @override
  Widget build(BuildContext context) {
    final lines = AeRegisterCalculator.countryMatrix(widget.byCountry);
    final visible = lines.where((l) {
      if (!_hideEmpty) return true;
      if (l.kind != AeMatrixLineKind.country) return true;
      final t = l.totals;
      return t != null && (t.arrivals != 0 || t.nights != 0);
    }).toList();

    final screenH = MediaQuery.sizeOf(context).height;
    final tableBodyMaxH = (screenH * 0.48).clamp(280.0, 560.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _reportHeader(),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final cols = _fitColumns(_baseColumns(), constraints.maxWidth);
            final tableWidth = cols.fold<double>(0, (w, c) => w + c.$2);
            final available = constraints.maxWidth;

            return Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth < available ? available : tableWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _headerRow(cols),
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: tableBodyMaxH),
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              for (var i = 0; i < visible.length; i++)
                                _line(visible[i], cols, zebraIndex: i),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Text(
          '* Philippine passport holders permanently residing abroad; excludes overseas Filipino workers',
          style: GoogleFonts.inter(fontSize: 11, color: _mutedText, height: 1.35),
        ),
      ],
    );
  }

  Widget _reportHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, c) {
              final narrow = c.maxWidth < 720;
              final titleBlock = Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _lightOrange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.public_rounded, color: _primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DAE-1B (Sum)',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: _darkText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.title,
                          style: GoogleFonts.inter(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _darkText,
                            letterSpacing: -0.2,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
              final filter = Theme(
                data: Theme.of(context).copyWith(
                  checkboxTheme: CheckboxThemeData(
                    fillColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) return _primary;
                      return Colors.white;
                    }),
                    checkColor: const WidgetStatePropertyAll(Colors.white),
                    side: const BorderSide(color: Color(0xFFFDBA74), width: 1.4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _hideEmpty = !_hideEmpty),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: Checkbox(
                            value: _hideEmpty,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            onChanged: (v) => setState(() => _hideEmpty = v ?? false),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Hide countries with no guests',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: _darkText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleBlock,
                    const SizedBox(height: 10),
                    filter,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: titleBlock),
                  const SizedBox(width: 12),
                  filter,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _lightOrange,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _metaChip(Icons.calendar_month_outlined, widget.periodLabel),
                if (widget.aeName.isNotEmpty) _metaChip(Icons.hotel_rounded, 'AE: ${widget.aeName}'),
                if (widget.aeType.isNotEmpty) _metaChip(Icons.category_outlined, 'AE Type: ${widget.aeType}'),
                if (widget.municipality.isNotEmpty)
                  _metaChip(Icons.location_city_outlined, 'City/Municipality: ${widget.municipality}'),
                _metaChip(Icons.map_outlined, 'Province: ${widget.province}'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: _primary),
        const SizedBox(width: 5),
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _darkText,
          ),
        ),
      ],
    );
  }

  List<(String, double, IconData?, bool)> _baseColumns() => const [
        ('COUNTRY OF RESIDENCE', 280, Icons.public_outlined, true),
        ('TOTAL Guest Arrivals', 120, Icons.login_rounded, true),
        ('TOTAL Guest Nights', 120, Icons.bedtime_outlined, true),
        ('ALOS', 72, Icons.timelapse_rounded, false),
        ('Female Arrivals', 100, Icons.woman_rounded, false),
        ('Male Arrivals', 100, Icons.man_rounded, false),
        ('Validation', 96, Icons.verified_outlined, false),
      ];

  List<(String, double, IconData?)> _fitColumns(
    List<(String, double, IconData?, bool)> base,
    double available,
  ) {
    final minTotal = base.fold<double>(0, (w, c) => w + c.$2);
    if (!available.isFinite || available <= minTotal) {
      return [for (final c in base) (c.$1, c.$2, c.$3)];
    }
    final extra = available - minTotal;
    final flexTotal = base.where((c) => c.$4).fold<double>(0, (w, c) => w + c.$2);
    if (flexTotal <= 0) {
      final scale = available / minTotal;
      return [for (final c in base) (c.$1, c.$2 * scale, c.$3)];
    }
    return [
      for (final c in base)
        (
          c.$1,
          c.$4 ? c.$2 + extra * (c.$2 / flexTotal) : c.$2,
          c.$3,
        ),
    ];
  }

  Widget _headerRow(List<(String, double, IconData?)> cols) {
    final style = GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      color: _darkText,
    );
    return Row(
      children: [
        for (var i = 0; i < cols.length; i++)
          _cell(
            '',
            width: cols[i].$2,
            fill: _lightOrange,
            height: 42,
            boldBorder: true,
            child: Row(
              mainAxisAlignment: i == 0 ? MainAxisAlignment.start : MainAxisAlignment.end,
              children: [
                if (cols[i].$3 != null) ...[
                  Icon(cols[i].$3, size: 13, color: _primary),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    cols[i].$1,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: i == 0 ? TextAlign.left : TextAlign.right,
                    style: style,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _line(
    AeCountryMatrixLine l,
    List<(String, double, IconData?)> cols, {
    required int zebraIndex,
  }) {
    final (fill, color, weight, indent) = switch (l.kind) {
      AeMatrixLineKind.section => (_darkOrange, Colors.white, FontWeight.w800, 10.0),
      AeMatrixLineKind.region => (_lightOrange, _darkText, FontWeight.w800, 10.0),
      AeMatrixLineKind.subregion => (_subtotalFill, _darkText, FontWeight.w700, 16.0),
      AeMatrixLineKind.country => (
          zebraIndex.isEven ? Colors.white : _rowAlt,
          _darkText,
          FontWeight.w600,
          28.0,
        ),
      AeMatrixLineKind.subtotal => (_subtotalFill, _darkText, FontWeight.w800, 40.0),
      AeMatrixLineKind.total => (_subtotalFill, _darkText, FontWeight.w800, 10.0),
      AeMatrixLineKind.grand => (_grandFill, _darkText, FontWeight.w900, 10.0),
      AeMatrixLineKind.breakdown => (_lightOrange, _darkText, FontWeight.w700, 16.0),
    };

    final t = l.totals;
    final isHeaderOnly = t == null;
    final style = GoogleFonts.inter(
      fontSize: 12,
      fontWeight: weight,
      color: color,
      fontStyle: l.kind == AeMatrixLineKind.country ? FontStyle.italic : FontStyle.normal,
    );
    String n(int v) => v == 0 ? '—' : '$v';

    return AeHoverRow(
      child: Row(
        children: [
          _cell(
            '',
            width: cols[0].$2,
            fill: fill,
            height: 36,
            child: Padding(
              padding: EdgeInsets.only(left: indent),
              child: Text(
                l.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ),
          _cell(
            isHeaderOnly ? '' : n(t.arrivals),
            width: cols[1].$2,
            align: TextAlign.right,
            fill: fill,
            style: style,
            height: 36,
          ),
          _cell(
            isHeaderOnly ? '' : n(t.nights),
            width: cols[2].$2,
            align: TextAlign.right,
            fill: fill,
            style: style,
            height: 36,
          ),
          _cell(
            isHeaderOnly
                ? ''
                : (l.alos == null ? '—' : l.alos!.toStringAsFixed(2)),
            width: cols[3].$2,
            align: TextAlign.right,
            fill: fill,
            style: style,
            height: 36,
          ),
          _cell(
            isHeaderOnly ? '' : n(t.female),
            width: cols[4].$2,
            align: TextAlign.right,
            fill: fill,
            style: style,
            height: 36,
          ),
          _cell(
            isHeaderOnly ? '' : n(t.male),
            width: cols[5].$2,
            align: TextAlign.right,
            fill: fill,
            style: style,
            height: 36,
          ),
          _cell(
            '',
            width: cols[6].$2,
            fill: fill,
            height: 36,
            child: isHeaderOnly
                ? const SizedBox.shrink()
                : Center(child: _validationBadge(l.ok)),
          ),
        ],
      ),
    );
  }

  Widget _validationBadge(bool ok) {
    final bg = ok ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2);
    final fg = ok ? const Color(0xFF15803D) : const Color(0xFFB91C1C);
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
          Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            ok ? 'OK' : 'Check',
            style: GoogleFonts.inter(fontSize: 11, color: fg, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _cell(
    String text, {
    required double width,
    TextAlign align = TextAlign.left,
    Color? fill,
    TextStyle? style,
    double height = 36,
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
          right: BorderSide(color: _border.withValues(alpha: 0.9), width: boldBorder ? 1 : 0.7),
          bottom: BorderSide(color: _border.withValues(alpha: 0.9), width: boldBorder ? 1.2 : 0.7),
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
}
