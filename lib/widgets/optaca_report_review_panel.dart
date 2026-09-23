import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/lgu_report_submission_service.dart';

/// OPTACA / Provincial Tourism: review LGU report submissions.
class OptacaReportReviewPanel extends StatefulWidget {
  const OptacaReportReviewPanel({
    super.key,
    this.primaryColor = AppTheme.brandOrange,
    this.textDark = const Color(0xFF1F2937),
    this.textMuted = const Color(0xFF6B7280),
  });

  final Color primaryColor;
  final Color textDark;
  final Color textMuted;

  @override
  State<OptacaReportReviewPanel> createState() =>
      _OptacaReportReviewPanelState();
}

class _OptacaReportReviewPanelState extends State<OptacaReportReviewPanel> {
  final _service = LguReportSubmissionService();
  final _dateFmt = DateFormat('MMM d, yyyy');
  final _notesController = TextEditingController();

  String _filter = 'open'; // open | all | approved | rejected
  bool _loading = true;
  List<LguReportSubmission> _items = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      String? status;
      if (_filter == 'approved') {
        status = LguReportSubmissionStatus.approved;
      } else if (_filter == 'rejected') {
        status = LguReportSubmissionStatus.rejected;
      } else if (_filter == 'submitted') {
        status = LguReportSubmissionStatus.submitted;
      }
      var list = await _service.listForProvincial(statusFilter: status);
      if (_filter == 'open') {
        list = list.where((e) => e.isOpen).toList();
      }
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Could not load submissions: $e', isError: true);
    }
  }

  Future<void> _startReview(LguReportSubmission item) async {
    try {
      await _service.markUnderReview(item.id);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      _snack('Update failed: $e', isError: true);
    }
  }

  Future<void> _approve(LguReportSubmission item) async {
    _notesController.text = item.reviewNotes;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve report?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.municipalityName} · ${item.reportTypeLabel}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Optional note to LGU',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.approve(
        id: item.id,
        reviewNotes: _notesController.text,
      );
      if (!mounted) return;
      _snack('Report approved.');
      await _reload();
    } catch (e) {
      if (!mounted) return;
      _snack('Approve failed: $e', isError: true);
    }
  }

  Future<void> _reject(LguReportSubmission item) async {
    _notesController.clear();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject / request revision'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${item.municipalityName} · ${item.reportTypeLabel}'),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Reason (required)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.reject(
        id: item.id,
        reviewNotes: _notesController.text,
      );
      if (!mounted) return;
      _snack('Report rejected — LGU can revise and resubmit.');
      await _reload();
    } catch (e) {
      if (!mounted) return;
      _snack('$e', isError: true);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'LGU report inbox (OPTACA)',
          style: TextStyle(
            color: widget.textDark,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Review formal submissions from municipal tourism offices. '
          'Approve to accept, or reject with a note so the LGU can revise.',
          style: TextStyle(
            color: widget.textMuted,
            fontSize: 12.5,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in const [
              ('open', 'Pending'),
              ('all', 'All'),
              ('approved', 'Approved'),
              ('rejected', 'Rejected'),
            ])
              ChoiceChip(
                label: Text(f.$2),
                selected: _filter == f.$1,
                onSelected: (_) {
                  setState(() => _filter = f.$1);
                  unawaited(_reload());
                },
                selectedColor: widget.primaryColor.withValues(alpha: 0.2),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _filter == f.$1 ? widget.primaryColor : widget.textDark,
                ),
              ),
            IconButton(
              onPressed: _loading ? null : _reload,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_items.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Text(
              _filter == 'open'
                  ? 'No pending LGU report submissions.'
                  : 'No submissions in this filter.',
              style: TextStyle(color: widget.textMuted),
            ),
          )
        else
          ..._items.map(_card),
      ],
    );
  }

  Widget _card(LguReportSubmission item) {
    final statusColor = switch (item.status) {
      LguReportSubmissionStatus.approved => Colors.green.shade700,
      LguReportSubmissionStatus.rejected => Colors.red.shade700,
      LguReportSubmissionStatus.underReview => Colors.blue.shade700,
      LguReportSubmissionStatus.withdrawn => Colors.grey.shade600,
      _ => widget.primaryColor,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.municipalityName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: widget.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.reportTypeLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: widget.textMuted,
                      ),
                    ),
                  ],
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
          const SizedBox(height: 10),
          Text(
            'Period: ${_dateFmt.format(item.periodStart)} – '
            '${_dateFmt.format(item.periodEnd)}',
            style: TextStyle(fontSize: 13, color: widget.textDark),
          ),
          const SizedBox(height: 4),
          Text(
            '${item.visitorCount} visitors · ${item.checkInCount} check-ins · '
            '${item.uniqueTourists} tourists · ${item.activeSpots} spots',
            style: TextStyle(fontSize: 12.5, color: widget.textMuted),
          ),
          if (item.topSpotName != null && item.topSpotName!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Top spot: ${item.topSpotName}',
              style: TextStyle(fontSize: 12.5, color: widget.textMuted),
            ),
          ],
          if (item.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'LGU notes: ${item.notes}',
              style: TextStyle(fontSize: 12.5, color: widget.textDark),
            ),
          ],
          Text(
            'Submitted ${_dateFmt.format(item.submittedAt)}'
            '${item.submittedByEmail.isEmpty ? '' : ' · ${item.submittedByEmail}'}',
            style: TextStyle(fontSize: 11.5, color: widget.textMuted),
          ),
          if (item.isOpen) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (item.status == LguReportSubmissionStatus.submitted)
                  OutlinedButton(
                    onPressed: () => _startReview(item),
                    child: const Text('Mark under review'),
                  ),
                FilledButton(
                  onPressed: () => _approve(item),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                  ),
                  child: const Text('Approve'),
                ),
                OutlinedButton(
                  onPressed: () => _reject(item),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                  ),
                  child: const Text('Reject'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
