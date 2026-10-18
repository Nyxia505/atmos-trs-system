import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/lgu_report_submission_service.dart';

/// LGU Tourism: build metrics + submit a report package to OPTACA.
class LguSubmitReportToOptacaPanel extends StatefulWidget {
  const LguSubmitReportToOptacaPanel({
    super.key,
    required this.municipalityId,
    required this.municipalityName,
    required this.checkIns,
    required this.submittedByName,
    this.parseTimestamp,
    this.primaryColor = AppTheme.brandOrange,
    this.textDark = const Color(0xFF1F2937),
    this.textMuted = const Color(0xFF6B7280),
  });

  final String municipalityId;
  final String municipalityName;
  final List<Map<String, dynamic>> checkIns;
  final String submittedByName;
  final DateTime? Function(Map<String, dynamic>)? parseTimestamp;
  final Color primaryColor;
  final Color textDark;
  final Color textMuted;

  @override
  State<LguSubmitReportToOptacaPanel> createState() =>
      _LguSubmitReportToOptacaPanelState();
}

class _LguSubmitReportToOptacaPanelState
    extends State<LguSubmitReportToOptacaPanel> {
  final _service = LguReportSubmissionService();
  final _notesController = TextEditingController();
  final _dateFmt = DateFormat('MMM d, yyyy');

  String _reportType = LguReportSubmissionType.monthlySummary;
  late DateTime _start;
  late DateTime _end;
  bool _submitting = false;
  bool _loadingHistory = true;
  List<LguReportSubmission> _history = const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, 1);
    _end = DateTime(now.year, now.month, now.day);
    unawaited(_reloadHistory());
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _metrics => _service.buildMetrics(
        checkIns: widget.checkIns,
        periodStart: _start,
        periodEnd: _end,
        parseTimestamp: widget.parseTimestamp,
      );

  Future<void> _reloadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final list =
          await _service.listForMunicipality(widget.municipalityId);
      if (!mounted) return;
      setState(() {
        _history = list;
        _loadingHistory = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingHistory = false);
      _snack('Could not load submission history: $e', isError: true);
    }
  }

  Future<void> _pickStart() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (d == null || !mounted) return;
    setState(() {
      _start = d;
      if (_end.isBefore(_start)) _end = _start;
    });
  }

  Future<void> _pickEnd() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _end,
      firstDate: _start,
      lastDate: DateTime.now(),
    );
    if (d == null || !mounted) return;
    setState(() => _end = d);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final mid = widget.municipalityId.trim();
    if (mid.isEmpty) {
      _snack('Municipality is not set on this account.', isError: true);
      return;
    }
    final metrics = _metrics;
    final visitors = metrics['visitorCount'] as int? ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit to OPTACA?'),
        content: Text(
          'Send ${LguReportSubmissionType.label(_reportType)} for '
          '${widget.municipalityName} '
          '(${_dateFmt.format(_start)} – ${_dateFmt.format(_end)}) '
          'with $visitors visitors to Provincial Tourism / OPTACA for review.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: widget.primaryColor),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _submitting = true);
    try {
      await _service.submit(
        municipalityId: mid,
        municipalityName: widget.municipalityName,
        reportType: _reportType,
        periodStart: _start,
        periodEnd: _end,
        checkIns: widget.checkIns,
        notes: _notesController.text,
        submittedByName: widget.submittedByName,
        parseTimestamp: widget.parseTimestamp,
      );
      if (!mounted) return;
      _notesController.clear();
      _snack('Report submitted to OPTACA for review.');
      await _reloadHistory();
    } catch (e) {
      if (!mounted) return;
      _snack('Submit failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _withdraw(LguReportSubmission item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw submission?'),
        content: const Text(
          'OPTACA will no longer see this package as pending.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Withdraw',
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.withdraw(item.id);
      if (!mounted) return;
      _snack('Submission withdrawn.');
      await _reloadHistory();
    } catch (e) {
      if (!mounted) return;
      _snack('Withdraw failed: $e', isError: true);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final metrics = _metrics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Submit to OPTACA',
          style: TextStyle(
            color: widget.textDark,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Send a formal report package to Provincial Tourism for review '
          'and approval. Live check-ins are already visible; this creates '
          'an official submission record.',
          style: TextStyle(
            color: widget.textMuted,
            fontSize: 12.5,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                // ignore: deprecated_member_use
                value: _reportType,
                decoration: const InputDecoration(
                  labelText: 'Report type',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final e in LguReportSubmissionType.labels.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: _submitting
                    ? null
                    : (v) {
                        if (v != null) setState(() => _reportType = v);
                      },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting ? null : _pickStart,
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text('From ${_dateFmt.format(_start)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting ? null : _pickEnd,
                      icon: const Icon(Icons.event, size: 18),
                      label: Text('To ${_dateFmt.format(_end)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _metricChip('Check-ins', '${metrics['checkInCount']}'),
                  _metricChip('Visitors', '${metrics['visitorCount']}'),
                  _metricChip('Tourists', '${metrics['uniqueTourists']}'),
                  _metricChip('Spots', '${metrics['activeSpots']}'),
                ],
              ),
              if ((metrics['topSpotName'] as String?)?.isNotEmpty == true) ...[
                const SizedBox(height: 8),
                Text(
                  'Top spot: ${metrics['topSpotName']}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: widget.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                maxLines: 3,
                enabled: !_submitting,
                decoration: const InputDecoration(
                  labelText: 'Notes for OPTACA (optional)',
                  hintText: 'e.g. Peak festival week included',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: widget.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _submitting ? 'Submitting…' : 'Submit report to OPTACA',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: Text(
                'Submission history',
                style: TextStyle(
                  color: widget.textDark,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: _loadingHistory ? null : _reloadHistory,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loadingHistory)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_history.isEmpty)
          Text(
            'No submissions yet.',
            style: TextStyle(color: widget.textMuted, fontSize: 13),
          )
        else
          ..._history.map(_historyCard),
      ],
    );
  }

  Widget _metricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: widget.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: widget.textDark,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: widget.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyCard(LguReportSubmission item) {
    final statusColor = switch (item.status) {
      LguReportSubmissionStatus.approved => Colors.green.shade700,
      LguReportSubmissionStatus.rejected => Colors.red.shade700,
      LguReportSubmissionStatus.underReview => Colors.blue.shade700,
      LguReportSubmissionStatus.withdrawn => Colors.grey.shade600,
      _ => widget.primaryColor,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.reportTypeLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: widget.textDark,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  item.statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_dateFmt.format(item.periodStart)} – ${_dateFmt.format(item.periodEnd)}'
            ' · ${item.visitorCount} visitors · ${item.checkInCount} check-ins',
            style: TextStyle(fontSize: 12.5, color: widget.textMuted),
          ),
          if (item.reviewNotes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'OPTACA: ${item.reviewNotes}',
              style: TextStyle(
                fontSize: 12.5,
                color: widget.textDark,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (item.isOpen) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _withdraw(item),
                child: Text(
                  'Withdraw',
                  style: TextStyle(color: Colors.red.shade700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
