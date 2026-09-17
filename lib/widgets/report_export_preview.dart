import 'dart:math' as math;

import 'package:atmos_trs_system/utils/csv_file_download.dart';
import 'package:atmos_trs_system/utils/xlsx_file_download.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

const Color _kReportTextDark = Color(0xFF1A1A1A);
const Color _kReportAccent = Color(0xFFEA580C);

/// Renders ATMOS-TRS report plain text as a structured printable document.
class ReportDocumentView extends StatelessWidget {
  const ReportDocumentView({
    super.key,
    required this.content,
    this.accentColor = _kReportAccent,
  });

  final String content;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _ReportDocumentParser(
        accentColor: accentColor,
      ).parse(content.split('\n')),
    );
  }
}

class _ReportDocumentParser {
  const _ReportDocumentParser({required this.accentColor});

  final Color accentColor;

  List<Widget> parse(List<String> lines) {
    final out = <Widget>[];
    var i = 0;
    var inMetaBlock = false;
    var metaRows = <MapEntry<String, String>>[];

    while (i < lines.length) {
      final raw = lines[i];
      final trimmed = raw.trimRight().trim();

      if (trimmed.isEmpty) {
        if (inMetaBlock && metaRows.isNotEmpty) {
          out.add(_metaPanel(metaRows));
          metaRows = [];
          inMetaBlock = false;
        }
        out.add(const SizedBox(height: 10));
        i++;
        continue;
      }

      if (trimmed.startsWith('===') && trimmed.endsWith('===')) {
        if (metaRows.isNotEmpty) {
          out.add(_metaPanel(metaRows));
          metaRows.clear();
        }
        inMetaBlock = false;
        out.add(_title(trimmed.replaceAll('=', '').trim()));
        i++;
        continue;
      }

      if (trimmed.startsWith('---') && trimmed.endsWith('---')) {
        if (metaRows.isNotEmpty) {
          out.add(_metaPanel(metaRows));
          metaRows.clear();
          inMetaBlock = false;
        }
        final inner = trimmed.replaceAll('-', '').trim();
        out.add(const SizedBox(height: 6));
        out.add(_sectionHeader(inner));

        if (inner.toUpperCase().contains('CHECK-IN')) {
          i++;
          final metrics = <MapEntry<String, String>>[];
          while (i < lines.length) {
            final row = lines[i].trim();
            if (row.isEmpty) break;
            if (row.startsWith('---')) {
              i--;
              break;
            }
            final parsed = _parseKeyValue(row);
            if (parsed != null && _isCheckInMetricLabel(parsed.key)) {
              metrics.add(parsed);
              i++;
            } else {
              break;
            }
          }
          if (metrics.isNotEmpty) {
            out.add(const SizedBox(height: 12));
            out.add(_metricCards(metrics));
          }
          out.add(const SizedBox(height: 8));
          continue;
        }

        if (inner.toUpperCase().contains('SUMMARY BY SPOT') ||
            inner.toUpperCase().contains('SUMMARY BY MUNICIPALITY')) {
          i++;
          final table = _consumeSummaryTable(lines, i);
          i = table.nextIndex;
          final label = inner.toUpperCase().contains('MUNICIPALITY')
              ? 'Municipality / City'
              : 'Tourist spot';
          if (table.rows.isNotEmpty || table.grandTotal != null) {
            out.add(const SizedBox(height: 12));
            out.add(_summaryTable(table, rowLabel: label));
          } else {
            out.add(const SizedBox(height: 12));
            out.add(_emptySectionCard('No records in this period.'));
          }
          out.add(const SizedBox(height: 8));
          continue;
        }

        out.add(const SizedBox(height: 10));
        i++;
        continue;
      }

      if (trimmed == 'Detail (sorted newest first):') {
        out.add(const SizedBox(height: 8));
        out.add(
          Text(
            'Recent check-ins',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        );
        out.add(const SizedBox(height: 8));
        i++;
        var any = false;
        while (i < lines.length) {
          final row = lines[i];
          if (row.trim().isEmpty) break;
          if (row.trim().startsWith('---')) break;
          if (RegExp(r'^\s{2,}').hasMatch(row)) {
            out.add(_detailLogCard(row.trim()));
            any = true;
            i++;
          } else {
            break;
          }
        }
        if (!any) {
          out.add(_emptySectionCard('No check-in detail rows for this period.'));
        }
        continue;
      }

      if (trimmed.startsWith('Note:')) {
        if (metaRows.isNotEmpty) {
          out.add(_metaPanel(metaRows));
          metaRows.clear();
          inMetaBlock = false;
        }
        out.add(_noteCallout(trimmed.substring(5).trim()));
        i++;
        continue;
      }

      final kv = _parseKeyValue(trimmed);
      if (kv != null && _isMetaLabel(kv.key)) {
        metaRows.add(kv);
        inMetaBlock = true;
        i++;
        continue;
      }

      if (inMetaBlock && metaRows.isNotEmpty) {
        out.add(_metaPanel(metaRows));
        metaRows.clear();
        inMetaBlock = false;
      }

      if (trimmed.startsWith('GRAND TOTAL')) {
        out.add(_grandTotalBar(trimmed));
        i++;
        continue;
      }

      if (RegExp(r'^\s{2,}').hasMatch(raw) && trimmed.isNotEmpty) {
        out.add(_detailLogCard(trimmed));
        i++;
        continue;
      }

      if (kv != null) {
        out.add(_keyValueRow(kv.key, kv.value));
        i++;
        continue;
      }

      if (trimmed.contains(',') && !trimmed.startsWith('Attraction,')) {
        out.add(_csvLineCard(trimmed));
        i++;
        continue;
      }

      out.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: SelectableText(
            trimmed,
            style: const TextStyle(
              color: _kReportTextDark,
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ),
      );
      i++;
    }

    if (metaRows.isNotEmpty) {
      out.add(_metaPanel(metaRows));
    }
    return out;
  }

  bool _isMetaLabel(String key) {
    return key == 'Generated' ||
        key.startsWith('Period') ||
        key == 'Report type' ||
        key == 'Month/Year' ||
        key == 'Municipality' ||
        key == 'Scope' ||
        key == 'Check-ins in period';
  }

  MapEntry<String, String>? _parseKeyValue(String line) {
    final colonIdx = line.indexOf(':');
    if (colonIdx <= 0) return null;
    final key = line.substring(0, colonIdx).trim();
    final val = line.substring(colonIdx + 1).trim();
    if (val.isEmpty) return null;
    return MapEntry(key, val);
  }

  bool _isCheckInMetricLabel(String label) {
    final l = label.toLowerCase();
    return l.contains('count in period') ||
        l.contains('verified') ||
        l.contains('pending');
  }

  String _formatMetaValue(String label, String value) {
    if (label == 'Generated') {
      try {
        final dt = DateTime.parse(value);
        return '${_formatDate(dt)} · '
            '${dt.hour.toString().padLeft(2, '0')}:'
            '${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }
    return value;
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  Widget _title(String title) {
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _kReportTextDark,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 14),
        Divider(color: Colors.grey.shade200, thickness: 1),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _metaPanel(List<MapEntry<String, String>> rows) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var j = 0; j < rows.length; j++) ...[
            if (j > 0) const SizedBox(height: 10),
            _keyValueRow(rows[j].key, _formatMetaValue(rows[j].key, rows[j].value)),
          ],
        ],
      ),
    );
  }

  Widget _noteCallout(String message) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withOpacity(0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: accentColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.grey.shade800,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptySectionCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_outlined, color: Colors.grey.shade400, size: 22),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricCards(List<MapEntry<String, String>> metrics) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 520;
        if (narrow) {
          return Column(
            children: [
              for (var i = 0; i < metrics.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _metricCard(metrics[i].key, metrics[i].value),
              ],
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < metrics.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: _metricCard(metrics[i].key, metrics[i].value)),
            ],
          ],
        );
      },
    );
  }

  String _shortMetricLabel(String label) {
    if (label.toLowerCase().contains('count in period')) return 'Check-ins';
    if (label.toLowerCase().contains('verified')) return 'Verified';
    if (label.toLowerCase().contains('pending')) return 'Pending';
    return label;
  }

  Widget _metricCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _shortMetricLabel(label),
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: _kReportTextDark,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  ({List<(String name, String count)> rows, String? grandTotal, int nextIndex})
      _consumeSummaryTable(List<String> lines, int start) {
    final rows = <(String, String)>[];
    String? grandTotal;
    var i = start;
    while (i < lines.length) {
      final t = lines[i].trim();
      if (t.isEmpty) {
        i++;
        break;
      }
      if (t.startsWith('---') || t == 'Detail (sorted newest first):') break;
      if (RegExp(r'^-+$').hasMatch(t)) {
        i++;
        continue;
      }
      if (t.toUpperCase().startsWith('GRAND TOTAL')) {
        grandTotal = t.contains(':') ? t.split(':').last.trim() : t;
        i++;
        break;
      }
      if (t.contains('|')) {
        final parts = t.split('|').map((e) => e.trim()).toList();
        final head = parts[0].toLowerCase();
        if (parts.length >= 2 &&
            head != 'spot' &&
            !head.startsWith('municipality') &&
            !parts[0].contains('---')) {
          rows.add((parts[0], parts.sublist(1).join(' · ')));
        }
        i++;
        continue;
      }
      final colonMatch =
          RegExp(r'^(.+?):\s*(\d+)\s*total\s*$', caseSensitive: false).firstMatch(t);
      if (colonMatch != null) {
        rows.add((colonMatch.group(1)!.trim(), '${colonMatch.group(2)} total'));
        i++;
        continue;
      }
      break;
    }
    return (rows: rows, grandTotal: grandTotal, nextIndex: i);
  }

  Widget _summaryTable(
    ({List<(String name, String count)> rows, String? grandTotal, int nextIndex})
        table, {
    required String rowLabel,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: const Color(0xFFF1F5F9),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    rowLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _kReportTextDark,
                    ),
                  ),
                ),
                const Expanded(
                  child: Text(
                    'Counts',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _kReportTextDark,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final row in table.rows)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      row.$1,
                      style: const TextStyle(
                        color: _kReportTextDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      row.$2,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (table.grandTotal != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.1),
                border: Border(top: BorderSide(color: accentColor.withOpacity(0.25))),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Grand total',
                      style: TextStyle(
                        color: _kReportTextDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    table.grandTotal!,
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _grandTotalBar(String line) {
    final value = line.contains(':') ? line.split(':').last.trim() : line;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentColor.withOpacity(0.14),
            accentColor.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withOpacity(0.28)),
      ),
      child: Row(
        children: [
          Icon(Icons.summarize_rounded, color: accentColor, size: 22),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Grand total',
              style: TextStyle(
                color: _kReportTextDark,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: accentColor,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailLogCard(String line) {
    final parts = line.split('|').map((e) => e.trim()).toList();
    var when = parts.isNotEmpty ? parts[0] : line;
    var subtitle = '';
    var title = 'Check-in';
    var user = '';

    if (parts.length >= 4) {
      when = parts[0];
      subtitle = parts[1];
      title = parts[2];
      user = parts[3];
    } else if (parts.length == 3) {
      when = parts[0];
      title = parts[1];
      user = parts[2];
    } else if (parts.length == 2) {
      when = parts[0];
      title = parts[1];
    }

    if (user.startsWith('user=')) user = user.substring(5);

    DateTime? parsed;
    try {
      parsed = DateTime.parse(when);
    } catch (_) {}

    final whenLabel = parsed != null
        ? '${_formatDate(parsed)} · '
            '${parsed.hour.toString().padLeft(2, '0')}:'
            '${parsed.minute.toString().padLeft(2, '0')}'
        : when;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.qr_code_scanner_rounded, color: accentColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _kReportTextDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: accentColor.withOpacity(0.9),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    whenLabel,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                  if (user.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Visitor ID: ${user.length > 12 ? '${user.substring(0, 8)}…' : user}',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _csvLineCard(String line) {
    final cells = line.split(',').map((e) => e.trim()).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: SelectableText(
          cells.join('  ·  '),
          style: const TextStyle(color: _kReportTextDark, fontSize: 12, height: 1.4),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accentColor.withOpacity(0.16),
            accentColor.withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accentColor.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.label_important_rounded, color: accentColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _kReportTextDark,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _keyValueRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 420) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  value,
                  style: const TextStyle(color: _kReportTextDark, fontSize: 13),
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 168,
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(
                  value,
                  style: const TextStyle(color: _kReportTextDark, fontSize: 13),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Full-screen styled export preview dialog (LGU + Governor).
Future<void> showReportExportPreviewDialog(
  BuildContext context, {
  required String title,
  required String subtitle,
  required String content,
  String? csvData,
  String? csvFilename,
  String? detailCsvData,
  String? detailCsvFilename,
  String detailCsvLabel = 'Download detail CSV',
  List<int>? xlsxBytes,
  String? xlsxFilename,
  Color accentColor = _kReportAccent,
}) {
  final fullScreenWeb = kIsWeb;
  return showDialog<void>(
    context: context,
    barrierDismissible: !fullScreenWeb,
    builder: (dialogContext) {
      final mq = MediaQuery.of(context);
      final dialogW =
          fullScreenWeb ? mq.size.width : math.min(720.0, mq.size.width - 40);
      final dialogH = fullScreenWeb ? mq.size.height : mq.size.height * 0.82;
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: fullScreenWeb
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: SizedBox(
          width: dialogW,
          height: dialogH,
          child: Material(
            color: Colors.white,
            elevation: fullScreenWeb ? 0 : 8,
            shadowColor: Colors.black26,
            borderRadius: fullScreenWeb
                ? BorderRadius.zero
                : BorderRadius.circular(26),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                    20,
                    fullScreenWeb ? 14 : 18,
                    12,
                    fullScreenWeb ? 14 : 18,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accentColor, accentColor.withOpacity(0.88)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.description_outlined,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.92),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    color: const Color(0xFFE8E8E8),
                    padding: EdgeInsets.all(fullScreenWeb ? 20 : 16),
                    child: Scrollbar(
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            width: double.infinity,
                            constraints: fullScreenWeb
                                ? const BoxConstraints(maxWidth: 960)
                                : null,
                            padding: const EdgeInsets.fromLTRB(28, 32, 28, 36),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x12000000),
                                  blurRadius: 20,
                                  offset: Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ReportDocumentView(
                              content: content,
                              accentColor: accentColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  color: const Color(0xFFFFFBF7),
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (csvData != null &&
                          csvData.isNotEmpty &&
                          csvFilename != null &&
                          csvFilename.isNotEmpty)
                        TextButton.icon(
                          onPressed: () async {
                            await downloadCsvFile(csvFilename, csvData);
                            if (dialogContext.mounted) Navigator.pop(dialogContext);
                          },
                          icon: Icon(Icons.table_chart_rounded, color: accentColor),
                          label: Text(
                            'Download summary CSV',
                            style: TextStyle(color: accentColor, fontWeight: FontWeight.w600),
                          ),
                        ),
                      if (detailCsvData != null &&
                          detailCsvData.isNotEmpty &&
                          detailCsvFilename != null &&
                          detailCsvFilename.isNotEmpty)
                        TextButton.icon(
                          onPressed: () async {
                            await downloadCsvFile(detailCsvFilename, detailCsvData);
                            if (dialogContext.mounted) Navigator.pop(dialogContext);
                          },
                          icon: Icon(Icons.list_alt_rounded, color: accentColor),
                          label: Text(
                            detailCsvLabel,
                            style: TextStyle(color: accentColor, fontWeight: FontWeight.w600),
                          ),
                        ),
                      if (xlsxBytes != null &&
                          xlsxBytes.isNotEmpty &&
                          xlsxFilename != null &&
                          xlsxFilename.isNotEmpty)
                        TextButton.icon(
                          onPressed: () async {
                            await downloadXlsxFile(xlsxFilename, xlsxBytes);
                            if (dialogContext.mounted) Navigator.pop(dialogContext);
                          },
                          icon: Icon(Icons.grid_on_rounded, color: accentColor),
                          label: Text(
                            'Download VAR 2 Excel',
                            style: TextStyle(color: accentColor, fontWeight: FontWeight.w600),
                          ),
                        ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: Text('Close', style: TextStyle(color: accentColor)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
