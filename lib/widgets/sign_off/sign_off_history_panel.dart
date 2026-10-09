import 'package:flutter/material.dart';

import 'package:atmos_trs_system/models/sign_off.dart';
import 'package:atmos_trs_system/services/sign_off_service.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';

String formatSignOffTime(DateTime? d) {
  if (d == null) return 'just now';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final l = d.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  return '${m[l.month - 1]} ${l.day}, ${l.year} · $h:${l.minute.toString().padLeft(2, '0')} ${l.hour < 12 ? 'AM' : 'PM'}';
}

/// Signed-save history for one subject (newest first) + integrity check of
/// the live content against the latest signed hash.
class SignOffHistoryPanel extends StatefulWidget {
  const SignOffHistoryPanel({
    super.key,
    required this.ownerId,
    required this.subjectType,
    required this.subjectId,
    this.latest,
    this.liveContentHash,
    this.title = 'Sign-off history',
    this.emptyText = 'No signed saves yet.',
  });

  final String ownerId;
  final String subjectType;
  final String subjectId;
  final SignOffStamp? latest;
  final String? liveContentHash;
  final String title;
  final String emptyText;

  @override
  State<SignOffHistoryPanel> createState() => _SignOffHistoryPanelState();
}

class _SignOffHistoryPanelState extends State<SignOffHistoryPanel> {
  Stream<List<SignOffRecord>>? _stream;
  String _key = '';

  Stream<List<SignOffRecord>> get _records {
    final k = '${widget.ownerId}|${widget.subjectType}|${widget.subjectId}';
    if (k != _key || _stream == null) {
      _key = k;
      _stream = SignOffService.watchForSubject(
        ownerId: widget.ownerId,
        subjectType: widget.subjectType,
        subjectId: widget.subjectId,
      );
    }
    return _stream!;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AeDashTokens.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.draw_rounded, size: 20, color: AeDashTokens.accent),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.title, style: AeDashTokens.heading(size: 16))),
          ]),
          const SizedBox(height: 4),
          Text(
            'Every save is signed with a name, position and fresh signature. Records cannot be edited or deleted.',
            style: AeDashTokens.body(size: 12),
          ),
          const SizedBox(height: 12),
          _integrity(),
          StreamBuilder<List<SignOffRecord>>(
            stream: _records,
            builder: (context, snap) {
              if (snap.hasError) {
                return Text('Could not load sign-offs: ${snap.error}',
                    style: AeDashTokens.body(color: AeDashTokens.danger));
              }
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final list = snap.data!;
              if (list.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(widget.emptyText, style: AeDashTokens.body()),
                );
              }
              return Column(children: [for (final r in list) _SignOffTile(record: r)]);
            },
          ),
        ],
      ),
    );
  }

  Widget _integrity() {
    final latest = widget.latest;
    final live = widget.liveContentHash;
    if (latest == null || live == null || latest.contentHash.isEmpty) return const SizedBox.shrink();
    final ok = latest.contentHash == live;
    final color = ok ? AeDashTokens.success : AeDashTokens.danger;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(ok ? Icons.verified_rounded : Icons.report_rounded, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            ok
                ? 'Matches the latest signed save by ${latest.name} (${latest.position}), '
                    '${formatSignOffTime(latest.at)}.'
                : 'Changed after the last signature by ${latest.name} (${latest.position}). '
                    'Some data was edited outside a signed save — review before relying on these figures.',
            style: AeDashTokens.body(size: 12.5, color: AeDashTokens.text, weight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

class _SignOffTile extends StatelessWidget {
  const _SignOffTile({required this.record});

  final SignOffRecord record;

  @override
  Widget build(BuildContext context) {
    final r = record;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AeDashTokens.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AeDashTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                width: 150,
                height: 54,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AeDashTokens.border),
                ),
                child: r.signaturePng == null
                    ? const Center(child: Icon(Icons.image_not_supported_outlined, color: AeDashTokens.muted))
                    : Image.memory(r.signaturePng!, fit: BoxFit.contain, gaplessPlayback: true),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 180, maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.actionLabel, style: AeDashTokens.section(size: 13.5)),
                    Text('${r.signerName} · ${r.signerPosition}',
                        style: AeDashTokens.body(size: 12.5, color: AeDashTokens.text, weight: FontWeight.w700)),
                    Text(formatSignOffTime(r.createdAt), style: AeDashTokens.body(size: 11.5)),
                  ],
                ),
              ),
            ],
          ),
          if (r.summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(r.summary, style: AeDashTokens.body(size: 12.5, color: AeDashTokens.text)),
          ],
          if (r.reason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Reason: ${r.reason}',
                style: AeDashTokens.body(size: 12.5, color: AeDashTokens.text).copyWith(fontStyle: FontStyle.italic)),
          ],
          if (r.changes.isNotEmpty)
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 6),
                dense: true,
                title: Text(
                  '${r.changes.length + r.changesTruncated} change(s)',
                  style: AeDashTokens.body(size: 12.5, color: AeDashTokens.info, weight: FontWeight.w700),
                ),
                children: [
                  for (final c in r.changes) _changeLine(c),
                  if (r.changesTruncated > 0)
                    Text('…and ${r.changesTruncated} more', style: AeDashTokens.body(size: 12)),
                ],
              ),
            ),
          Text(
            [
              if (r.accountEmail.isNotEmpty) 'Account: ${r.accountEmail}',
              if (r.platform.isNotEmpty) r.platform,
              if (r.signatureSha256.length >= 12) 'Signature #${r.signatureSha256.substring(0, 12)}',
            ].join(' · '),
            style: AeDashTokens.body(size: 10.5),
          ),
        ],
      ),
    );
  }

  Widget _changeLine(SignOffChange c) {
    final (icon, color) = switch (c.op) {
      'add' => (Icons.add_circle_outline_rounded, AeDashTokens.success),
      'delete' => (Icons.remove_circle_outline_rounded, AeDashTokens.danger),
      _ => (Icons.edit_outlined, AeDashTokens.info),
    };
    final diffs = signOffDiffLines(c.before, c.after);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.label, style: AeDashTokens.body(size: 12.5, color: AeDashTokens.text, weight: FontWeight.w600)),
                if (c.op == 'edit' || c.op == 'set')
                  for (final d in diffs) Text(d, style: AeDashTokens.body(size: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "field: old → new" lines for changed keys (skips bookkeeping keys).
List<String> signOffDiffLines(Map<String, dynamic>? before, Map<String, dynamic>? after) {
  const skip = {'day', 'seed'};
  const labels = {
    'date': 'Date',
    'roomNo': 'Room',
    'residence': 'Residence',
    'phRegion': 'PH region',
    'guests': 'Guests',
    'female': 'Female',
    'male': 'Male',
    'checkedInDay': 'Checked in this day',
    'rate': 'Rate',
    'chargesA': 'Charges (A)',
    'chargesB': 'Charges (B)',
    'noGuests': 'No guests',
    'status': 'Status',
    'totalRooms': 'Total rooms',
    'aeType': 'AE type',
    'classificationCode': 'Classification code',
    'hostsMice': 'Hosts events (MICE)',
    'dateStart': 'Start date',
    'dateEnd': 'End date',
    'eventName': 'Event',
    'eventType': 'Event type',
    'category': 'Category',
    'organizer': 'Organizer',
    'hours': 'Hours',
    'participants': 'Participants',
    'foreign': 'Foreign',
    'exhibitors': 'Exhibitors',
    'remarks': 'Remarks',
  };
  String show(dynamic v) {
    if (v == null || (v is String && v.isEmpty)) return '—';
    if (v is bool) return v ? 'Yes' : 'No';
    if (v is num && v == v.roundToDouble()) return v.round().toString();
    return v.toString();
  }

  final b = before ?? const {};
  final a = after ?? const {};
  final keys = {...b.keys, ...a.keys}.where((k) => !skip.contains(k));
  return [
    for (final k in keys)
      if (show(b[k]) != show(a[k])) '${labels[k] ?? k}: ${show(b[k])} → ${show(a[k])}',
  ];
}
