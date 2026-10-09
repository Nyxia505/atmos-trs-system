import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';

/// Spreadsheet-like building blocks shared by the register sheets.
abstract final class AeSheetKit {
  static const Color grid = Color(0xFFD7DEE7);
  static const Color headerFill = Color(0xFFFFF3C4);
  static const Color inputFill = Color(0xFFFFFF8A);
  static const Color kpiFill = Color(0xFF9BD771);
  static const Color nightsFill = Color(0xFF3AA8E8);
  static const Color sectionFill = Color(0xFF1F6FB8);
  static const Color subtotalFill = Color(0xFF29B6E8);
  static const Color totalFill = Color(0xFF92D050);
  static const Color bandFill = Color(0xFFDDE8C9);
  static const Color labelFill = Color(0xFFDCE6F1);

  static TextStyle cell({
    double size = 12,
    FontWeight weight = FontWeight.w500,
    Color color = AeDashTokens.text,
    bool italic = false,
  }) =>
      GoogleFonts.inter(
        fontSize: size,
        fontWeight: weight,
        color: color,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        height: 1.2,
      );

  static String int0(num v) => v == 0 ? '-' : v.round().toString();

  static String money(double v) {
    if (v == 0) return '-';
    final s = v.toStringAsFixed(2);
    final parts = s.split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '$whole.${parts[1]}';
  }

  static const months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];
  static const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  static String monthName(int m) => months[(m - 1).clamp(0, 11)];
  static String shortDate(DateTime d) => '${d.month}/${d.day}/${d.year}';
}

/// One bordered sheet cell.
class AeCell extends StatelessWidget {
  const AeCell(
    this.text, {
    super.key,
    this.width = 90,
    this.align = TextAlign.left,
    this.fill,
    this.style,
    this.height = 32,
    this.child,
  });

  final String text;
  final double width;
  final double height;
  final TextAlign align;
  final Color? fill;
  final TextStyle? style;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: switch (align) {
        TextAlign.right || TextAlign.end => Alignment.centerRight,
        TextAlign.center => Alignment.center,
        _ => Alignment.centerLeft,
      },
      decoration: BoxDecoration(
        color: fill,
        border: const Border(
          right: BorderSide(color: AeSheetKit.grid),
          bottom: BorderSide(color: AeSheetKit.grid),
        ),
      ),
      child: child ??
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: style ?? AeSheetKit.cell(),
          ),
    );
  }
}

/// Bordered sheet frame with horizontal scroll for wide tables.
class AeSheetFrame extends StatelessWidget {
  const AeSheetFrame({super.key, required this.child, this.minWidth = 0});

  final Widget child;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AeSheetKit.grid),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: minWidth),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: AeSheetKit.grid)),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Labeled key/value line used on sheet headers (Province, Municipality, ...).
class AeSheetField extends StatelessWidget {
  const AeSheetField({
    super.key,
    required this.label,
    required this.value,
    this.fill = AeSheetKit.labelFill,
    this.valueWidth = 220,
    this.labelWidth = 200,
    this.valueAlign = TextAlign.left,
    this.bold = false,
  });

  final String label;
  final String value;
  final Color fill;
  final double valueWidth;
  final double labelWidth;
  final TextAlign valueAlign;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(label, style: AeSheetKit.cell(size: 12.5)),
          ),
          Container(
            width: valueWidth,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: fill,
              border: Border.all(color: const Color(0xFF8EA9C1)),
            ),
            child: Text(
              value.isEmpty ? '—' : value,
              textAlign: valueAlign,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AeSheetKit.cell(
                size: 12.5,
                weight: bold ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
