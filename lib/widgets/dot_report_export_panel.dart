import 'dart:async';

import 'package:flutter/material.dart';

import 'package:atmos_trs_system/config/supabase_report_templates_config.dart';
import 'package:atmos_trs_system/services/dae3_auto_report_service.dart';
import 'package:atmos_trs_system/services/lgu_checkin_report_query.dart';
import 'package:atmos_trs_system/utils/dot_report_export_service.dart';
import 'package:atmos_trs_system/utils/dot_var2_visitor_record_report.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/utils/xlsx_file_download.dart';

/// Shared DOT / DAE export panel for LGU (municipal) and Governor (provincial).
class DotReportExportPanel extends StatefulWidget {
  const DotReportExportPanel({
    super.key,
    required this.primaryColor,
    required this.textDark,
    required this.textMuted,
    required this.borderColor,
    required this.scopeLabel,
    required this.scopeSlug,
    required this.isProvincial,
    required this.isMobile,
    required this.checkIns,
    required this.tourists,
    required this.catalogSpots,
    this.municipalityId,
    this.parseTimestamp,
    this.wrapPanel,
  });

  final Color primaryColor;
  final Color textDark;
  final Color textMuted;
  final Color borderColor;
  final String scopeLabel;
  final String scopeSlug;
  final bool isProvincial;
  final bool isMobile;
  final List<Map<String, dynamic>> checkIns;
  final List<Map<String, dynamic>> tourists;
  final List<DotVar2SpotCatalogEntry> catalogSpots;
  /// LGU municipality id — enables auto DAE-3 draft + month Firestore fetch.
  final String? municipalityId;
  final DateTime? Function(Map<String, dynamic> checkIn)? parseTimestamp;
  final Widget Function(Widget child)? wrapPanel;

  @override
  State<DotReportExportPanel> createState() => _DotReportExportPanelState();
}

class _DotReportExportPanelState extends State<DotReportExportPanel> {
  final _service = DotReportExportService();
  DotReportType _selected = DotReportType.var2VisitorRecord;
  DateTime? _start;
  DateTime? _end;
  bool _busy = false;
  bool _busyCurrentMonth = false;
  String? _lastGapsPreview;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, 1);
    _end = DateTime(now.year, now.month, now.day);
    if (!widget.isProvincial) {
      _selected = DotReportType.dae3FormA;
      unawaited(_bootstrapDae3Draft());
    }
  }

  Future<void> _bootstrapDae3Draft() async {
    final mid = widget.municipalityId;
    if (mid == null || mid.isEmpty) return;
    await Dae3AutoReportService.instance.ensureLoaded(mid);
    Dae3AutoReportService.instance.scheduleRefresh(
      municipalityId: mid,
      scopeLabel: widget.scopeLabel,
      scopeSlug: widget.scopeSlug,
      localCheckIns: widget.checkIns,
      tourists: widget.tourists,
      parseTimestamp: widget.parseTimestamp,
    );
  }

  @override
  void didUpdateWidget(covariant DotReportExportPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isProvincial) return;
    if (oldWidget.checkIns.length != widget.checkIns.length ||
        (widget.checkIns.isNotEmpty &&
            oldWidget.checkIns.isNotEmpty &&
            widget.checkIns.first['id'] != oldWidget.checkIns.first['id'])) {
      Dae3AutoReportService.instance.scheduleRefresh(
        municipalityId: widget.municipalityId,
        scopeLabel: widget.scopeLabel,
        scopeSlug: widget.scopeSlug,
        localCheckIns: widget.checkIns,
        tourists: widget.tourists,
        newestCheckInId: widget.checkIns.isNotEmpty
            ? widget.checkIns.first['id']?.toString()
            : null,
        parseTimestamp: widget.parseTimestamp,
      );
    }
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = widget.isProvincial
        ? _buildProvincialBody()
        : _buildLguBody();

    final wrapped = widget.wrapPanel?.call(body) ??
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(widget.isMobile ? 14 : 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: widget.borderColor),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: body,
        );

    return wrapped;
  }

  /// Cleaner LGU layout: DAE-3 first, then other forms + custom range.
  Widget _buildLguBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDae3AutoCard(),
        const SizedBox(height: 18),
        Text(
          'Other official forms',
          style: TextStyle(
            color: widget.textDark,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Pick a form, choose dates, then generate a filled Excel from your check-ins.',
          style: TextStyle(
            color: widget.textMuted,
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final type in DotReportType.values)
              _buildReportTypeChip(type),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          _selected.title,
          style: TextStyle(
            color: widget.textDark,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          _selected.subtitle,
          style: TextStyle(
            color: widget.textMuted,
            fontSize: 11.5,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Custom date range',
          style: TextStyle(
            color: widget.textDark,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        widget.isMobile ? _buildControlsStacked() : _buildControlsRow(),
        if (_lastGapsPreview != null) ...[
          const SizedBox(height: 12),
          _buildGapsPreview(),
        ],
        const SizedBox(height: 8),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 4),
            title: Text(
              'Blank templates (download only)',
              style: TextStyle(
                color: widget.textDark,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              'Official empty files from Supabase — no ATMOS fill',
              style: TextStyle(color: widget.textMuted, fontSize: 11.5),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in kDotBlankTemplates)
                      OutlinedButton.icon(
                        onPressed: _busy || _busyCurrentMonth
                            ? null
                            : () => _downloadBlank(t),
                        icon: Icon(
                          Icons.download_outlined,
                          size: 16,
                          color: widget.primaryColor,
                        ),
                        label: Text(
                          t.title,
                          style: TextStyle(
                            color: widget.textDark,
                            fontSize: 12,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: widget.borderColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProvincialBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'DOT templates (province-wide)',
          style: TextStyle(
            color: widget.textDark,
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Fetches official forms from Supabase and fills them from province-wide check-ins.',
          style: TextStyle(
            color: widget.textMuted,
            fontSize: 12,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        ...DotReportType.values.map(_buildPriorityTile),
        const SizedBox(height: 16),
        Text(
          'Period & generate',
          style: TextStyle(
            color: widget.textDark,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        widget.isMobile ? _buildControlsStacked() : _buildControlsRow(),
        if (_lastGapsPreview != null) ...[
          const SizedBox(height: 12),
          _buildGapsPreview(),
        ],
        const SizedBox(height: 18),
        Text(
          'Blank templates (download only)',
          style: TextStyle(
            color: widget.textDark,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Official files from Supabase — no ATMOS fill yet.',
          style: TextStyle(color: widget.textMuted, fontSize: 11.5),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in kDotBlankTemplates)
              OutlinedButton.icon(
                onPressed: _busy || _busyCurrentMonth
                    ? null
                    : () => _downloadBlank(t),
                icon: Icon(
                  Icons.download_outlined,
                  size: 16,
                  color: widget.primaryColor,
                ),
                label: Text(
                  t.title,
                  style: TextStyle(color: widget.textDark, fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: widget.borderColor),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildGapsPreview() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: widget.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.primaryColor.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        _lastGapsPreview!,
        style: TextStyle(
          color: widget.textDark,
          fontSize: 11.5,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildReportTypeChip(DotReportType type) {
    final selected = _selected == type;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _busy || _busyCurrentMonth
            ? null
            : () => setState(() => _selected = type),
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? widget.primaryColor.withValues(alpha: 0.12)
                : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? widget.primaryColor : widget.borderColor,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Text(
            type.title,
            style: TextStyle(
              color: selected ? widget.primaryColor : widget.textDark,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDae3AutoCard() {
    return ValueListenableBuilder<Dae3DraftMeta?>(
      valueListenable: Dae3AutoReportService.instance.draftMeta,
      builder: (context, meta, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: Dae3AutoReportService.instance.reportJustUpdated,
          builder: (context, justUpdated, _) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    widget.primaryColor.withValues(alpha: 0.10),
                    const Color(0xFFFFF7ED),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: widget.primaryColor.withValues(alpha: 0.28),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.auto_awesome_motion_rounded,
                          color: widget.primaryColor,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DAE-3 (recommended)',
                              style: TextStyle(
                                color: widget.textDark,
                                fontWeight: FontWeight.w800,
                                fontSize: 14.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Monthly guest record — auto-counts new QR check-ins',
                              style: TextStyle(
                                color: widget.textMuted,
                                fontSize: 12,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (justUpdated)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: widget.primaryColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Updated',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    meta == null
                        ? 'Preparing this month’s draft from live check-ins. '
                            'File base: ${DotReportType.dae3FormA.objectFilename}'
                        : '${meta.monthLabel}: ${meta.checkInsInMonth} check-ins → '
                            '${meta.aeRows} AE rows (${meta.totalGuests} guests). '
                            'Updated ${_formatRelative(meta.updatedAt)}.',
                    style: TextStyle(
                      color: widget.textMuted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: _busy || _busyCurrentMonth
                        ? null
                        : _downloadCurrentMonthDae3,
                    icon: _busyCurrentMonth
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.file_download_outlined, size: 18),
                    label: Text(
                      _busyCurrentMonth
                          ? 'Preparing DAE-3...'
                          : 'Download this month’s DAE-3',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatRelative(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${when.month}/${when.day} ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildPriorityTile(DotReportType type) {
    final selected = _selected == type;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _busy || _busyCurrentMonth
              ? null
              : () => setState(() => _selected = type),
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected
                  ? widget.primaryColor.withValues(alpha: 0.08)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? widget.primaryColor : widget.borderColor,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? widget.primaryColor : widget.textMuted,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        type.title,
                        style: TextStyle(
                          color: widget.textDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        type.subtitle,
                        style: TextStyle(
                          color: widget.textMuted,
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlsRow() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.end,
      children: [
        SizedBox(
          width: 180,
          child: _dateField('Start', _start, (d) => setState(() => _start = d)),
        ),
        SizedBox(
          width: 180,
          child: _dateField('End', _end, (d) => setState(() => _end = d)),
        ),
        ElevatedButton.icon(
          onPressed: _busy || _busyCurrentMonth ? null : _generate,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.file_download_outlined, size: 18),
          label: Text(_busy ? 'Generating...' : 'Generate filled Excel'),
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildControlsStacked() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _dateField('Start', _start, (d) => setState(() => _start = d)),
        const SizedBox(height: 10),
        _dateField('End', _end, (d) => setState(() => _end = d)),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          onPressed: _busy || _busyCurrentMonth ? null : _generate,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.file_download_outlined, size: 18),
          label: Text(_busy ? 'Generating...' : 'Generate filled Excel'),
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.primaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dateField(
    String label,
    DateTime? value,
    ValueChanged<DateTime> onSelect,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: widget.textMuted, fontSize: 11)),
        const SizedBox(height: 4),
        InkWell(
          onTap: _busy || _busyCurrentMonth
              ? null
              : () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: value ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) onSelect(picked);
                },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: widget.borderColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value == null
                        ? 'Select date'
                        : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: value == null ? widget.textMuted : widget.textDark,
                      fontSize: 13,
                      fontWeight:
                          value == null ? FontWeight.normal : FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  Icons.calendar_today_rounded,
                  color: widget.primaryColor,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _resolveCheckInsForExport({
    required DateTime start,
    required DateTime end,
  }) async {
    if (widget.isProvincial) return widget.checkIns;
    final mid = normalizeMunicipalityId(widget.municipalityId);
    if (mid.isEmpty) return widget.checkIns;

    try {
      final fetched = await LguCheckInReportQuery.fetchRange(
        municipalityQueryIds: municipalityIdsForQuery(mid),
        start: start,
        end: end,
      );
      if (fetched.isEmpty) return widget.checkIns;
      final byId = <String, Map<String, dynamic>>{
        for (final c in fetched)
          if ((c['id']?.toString() ?? '').isNotEmpty) c['id'].toString(): c,
        for (final c in widget.checkIns)
          if ((c['id']?.toString() ?? '').isNotEmpty) c['id'].toString(): c,
      };
      return byId.values.toList();
    } catch (e) {
      debugPrint('[DotReportExportPanel] range fetch: $e');
      return widget.checkIns;
    }
  }

  Future<void> _downloadCurrentMonthDae3() async {
    final mid = widget.municipalityId;
    if (mid == null || mid.trim().isEmpty) {
      _snack('Municipality not set — cannot build DAE-3.', Colors.orange);
      return;
    }

    setState(() {
      _busyCurrentMonth = true;
      _lastGapsPreview = null;
    });

    try {
      final result =
          await Dae3AutoReportService.instance.generateCurrentMonthExcel(
        municipalityId: mid,
        scopeLabel: widget.scopeLabel,
        scopeSlug: widget.scopeSlug,
        localCheckIns: widget.checkIns,
        tourists: widget.tourists,
        catalogSpots: widget.catalogSpots,
        parseTimestamp: widget.parseTimestamp,
        exportService: _service,
      );
      await downloadXlsxFile(result.filename, result.bytes);
      if (!mounted) return;
      Dae3AutoReportService.instance.clearJustUpdatedFlag();
      setState(() {
        _lastGapsPreview =
            '${result.summary}\nBase: ${DotReportType.dae3FormA.objectFilename}\n'
            'Gaps noted in ATMOS_GAPS sheet (${result.gaps.length}):\n'
            '• ${result.gaps.take(3).join('\n• ')}'
            '${result.gaps.length > 3 ? '\n• …' : ''}';
      });
      _snack(
        xlsxDownloadUsesShareSheet
            ? 'Current-month DAE-3 ready — use the share sheet to save'
            : 'Download started: ${result.filename}',
        widget.primaryColor,
      );
    } on DotReportTemplateFetchException catch (e) {
      if (!mounted) return;
      _snack(e.message, Colors.red.shade700);
    } catch (e) {
      if (!mounted) return;
      _snack('DAE-3 export failed: $e', Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _busyCurrentMonth = false);
    }
  }

  Future<void> _generate() async {
    if (_start == null || _end == null) {
      _snack('Please select both start and end dates', Colors.orange);
      return;
    }
    if (_end!.isBefore(_start!)) {
      _snack('End date must be on or after start date', Colors.orange);
      return;
    }

    setState(() {
      _busy = true;
      _lastGapsPreview = null;
    });

    try {
      final end =
          DateTime(_end!.year, _end!.month, _end!.day, 23, 59, 59, 999);
      final checkIns = await _resolveCheckInsForExport(
        start: _start!,
        end: end,
      );
      final result = await _service.exportFilled(
        type: _selected,
        startDate: _start!,
        endDate: end,
        checkIns: checkIns,
        tourists: widget.tourists,
        catalogSpots: widget.catalogSpots,
        scopeLabel: widget.scopeLabel,
        scopeSlug: widget.scopeSlug,
        parseTimestamp: widget.parseTimestamp,
      );
      await downloadXlsxFile(result.filename, result.bytes);
      if (!mounted) return;
      setState(() {
        _lastGapsPreview =
            '${result.summary}\nGaps noted in ATMOS_GAPS sheet (${result.gaps.length}):\n• ${result.gaps.take(3).join('\n• ')}'
            '${result.gaps.length > 3 ? '\n• …' : ''}';
      });
      _snack(
        xlsxDownloadUsesShareSheet
            ? 'Excel ready — use the share sheet to save'
            : 'Download started: ${result.filename}',
        widget.primaryColor,
      );
    } on DotReportTemplateFetchException catch (e) {
      if (!mounted) return;
      _snack(e.message, Colors.red.shade700);
    } catch (e) {
      if (!mounted) return;
      _snack('Export failed: $e', Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _downloadBlank(DotBlankTemplate template) async {
    setState(() => _busy = true);
    try {
      final bytes = await _service.downloadBlankTemplate(template);
      await downloadXlsxFile(template.objectFilename, bytes);
      if (!mounted) return;
      _snack(
        xlsxDownloadUsesShareSheet
            ? 'Template ready — use the share sheet to save'
            : 'Blank template download started',
        widget.primaryColor,
      );
    } on DotReportTemplateFetchException catch (e) {
      if (!mounted) return;
      _snack(e.message, Colors.red.shade700);
    } catch (e) {
      if (!mounted) return;
      _snack('Download failed: $e', Colors.red.shade700);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
