import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:atmos_trs_system/models/sign_off.dart';
import 'package:atmos_trs_system/services/sign_off_service.dart';
import 'package:atmos_trs_system/widgets/establishment_dash_tokens.dart';

String formatSignOffTime(DateTime? d) {
  if (d == null) return 'just now';
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final l = d.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  return '${m[l.month - 1]} ${l.day}, ${l.year} · '
      '$h:${l.minute.toString().padLeft(2, '0')} ${l.hour < 12 ? 'AM' : 'PM'}';
}

/// Full-month date for audit cards: "November 6, 2026 • 3:48 PM".
String formatSignOffDateTime(DateTime? d) {
  if (d == null) return 'Just now';
  const m = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  final l = d.toLocal();
  final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
  return '${m[l.month - 1]} ${l.day}, ${l.year} • '
      '$h:${l.minute.toString().padLeft(2, '0')} ${l.hour < 12 ? 'AM' : 'PM'}';
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
    this.title = 'Sign-offs',
    this.periodLabel,
    this.description = 'Track signed reports and authorized changes.',
    this.emptyText = 'No signed saves yet.',
  });

  final String ownerId;
  final String subjectType;
  final String subjectId;
  final SignOffStamp? latest;
  final String? liveContentHash;
  final String title;
  final String? periodLabel;
  final String description;
  final String emptyText;

  @override
  State<SignOffHistoryPanel> createState() => _SignOffHistoryPanelState();
}

class _SignOffHistoryPanelState extends State<SignOffHistoryPanel> {
  Stream<List<SignOffRecord>>? _stream;
  String _key = '';

  static const _primary = Color(0xFFF97316);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _border = Color(0xFFE5E7EB);
  static const _darkText = Color(0xFF1F2937);
  static const _mutedText = Color(0xFF64748B);

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
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
      child: StreamBuilder<List<SignOffRecord>>(
        stream: _records,
        builder: (context, snap) {
          final list = snap.data ?? const <SignOffRecord>[];
          final count = snap.hasData ? list.length : null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _header(count),
              const SizedBox(height: 12),
              _integrity(),
              if (snap.hasError)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Could not load sign-offs: ${snap.error}',
                    style: AeDashTokens.body(color: AeDashTokens.danger),
                  ),
                )
              else if (!snap.hasData)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: AeEmptyState(
                    message: widget.emptyText,
                    icon: Icons.draw_outlined,
                    boxed: false,
                  ),
                )
              else
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < list.length; i++)
                      _SignOffCard(
                        record: list[i],
                        isLatest: _isLatest(list[i], i),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  bool _isLatest(SignOffRecord r, int index) {
    final latestId = widget.latest?.id;
    if (latestId != null && latestId.isNotEmpty) return r.id == latestId;
    return index == 0;
  }

  Widget _header(int? count) {
    final period = (widget.periodLabel ?? '').trim();
    final titleText = period.isEmpty ? widget.title : '${widget.title} | $period';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _lightOrange,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: const Icon(Icons.draw_rounded, size: 20, color: _primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titleText,
                style: GoogleFonts.inter(
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  color: _darkText,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                widget.description,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: _mutedText,
                ),
              ),
            ],
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _border),
            ),
            child: Text(
              '$count',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: _darkText,
              ),
            ),
          ),
        ],
        const SizedBox(width: 6),
        Tooltip(
          message:
              'Every save on the register requires a fresh signature. '
              'This list is append-only — signed records cannot be edited or deleted here.',
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              shape: BoxShape.circle,
              border: Border.all(color: _border),
            ),
            child: const Icon(Icons.help_outline_rounded, size: 15, color: _mutedText),
          ),
        ),
      ],
    );
  }

  /// Promotes unsigned mismatches only. Verified state stays quiet.
  Widget _integrity() {
    final latest = widget.latest;
    final live = widget.liveContentHash;
    if (latest == null || live == null || latest.contentHash.isEmpty) {
      return const SizedBox.shrink();
    }
    final ok = latest.contentHash == live;
    if (ok) return const SizedBox.shrink();

    final who = [
      if (latest.name.trim().isNotEmpty) latest.name.trim(),
      if (latest.position.trim().isNotEmpty) latest.position.trim(),
    ].join(' — ');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: const Icon(Icons.report_rounded, color: Color(0xFFDC2626), size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Unsigned Changes Detected',
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFFB91C1C),
                  ),
                ),
                if (who.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    '$who | ${formatSignOffDateTime(latest.at)}',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _darkText,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 3),
                  Text(
                    formatSignOffDateTime(latest.at),
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: _darkText,
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  'Some data was edited outside a signed save — review before relying on these figures.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: _mutedText,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignOffCard extends StatefulWidget {
  const _SignOffCard({required this.record, required this.isLatest});

  final SignOffRecord record;
  final bool isLatest;

  @override
  State<_SignOffCard> createState() => _SignOffCardState();
}

class _SignOffCardState extends State<_SignOffCard> {
  static const _primary = Color(0xFFF97316);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _border = Color(0xFFE5E7EB);
  static const _darkText = Color(0xFF1F2937);
  static const _mutedText = Color(0xFF64748B);

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final meta = _signOffMeta(r);
    final narrow = MediaQuery.sizeOf(context).width < 720;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: widget.isLatest
              ? AeDashTokens.success.withValues(alpha: 0.35)
              : _border,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.035),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (narrow)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _signaturePreview(r),
                          const SizedBox(width: 12),
                          Expanded(child: _middle(r, meta)),
                          const SizedBox(width: 8),
                          _trailing(),
                        ],
                      ),
                    ],
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _signaturePreview(r),
                      const SizedBox(width: 14),
                      Expanded(child: _middle(r, meta)),
                      const SizedBox(width: 10),
                      _trailing(),
                    ],
                  ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  alignment: Alignment.topCenter,
                  child: _expanded
                      ? _detailsPanel(r, meta)
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _signaturePreview(SignOffRecord r) {
    return Container(
      width: 118,
      height: 54,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: r.signaturePng == null
          ? const Center(
              child: Icon(
                Icons.visibility_off_outlined,
                color: _mutedText,
                size: 20,
              ),
            )
          : Image.memory(
              r.signaturePng!,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            ),
    );
  }

  Widget _middle(SignOffRecord r, _SignOffMeta meta) {
    final name = r.signerName.trim().isEmpty ? 'Unknown signer' : r.signerName.trim();
    final position = r.signerPosition.trim();
    final displayName = position.isEmpty ? name : '$name ($position)';
    final chips = <String>[
      if (meta.room != null && meta.room!.isNotEmpty) 'Room: ${meta.room}',
      if (meta.guests != null && meta.guests!.isNotEmpty) 'Total: ${meta.guests}',
      if (meta.residence != null && meta.residence!.isNotEmpty) meta.residence!,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          displayName,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _darkText,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          r.actionLabel,
          style: GoogleFonts.inter(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: _darkText,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          formatSignOffDateTime(r.createdAt),
          style: GoogleFonts.inter(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: _mutedText,
          ),
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final c in chips)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _border),
                  ),
                  child: Text(
                    c,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _darkText,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _trailing() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isLatest) ...[
              _badge(
                'Latest',
                bg: const Color(0xFFF0FDF4),
                fg: AeDashTokens.success,
                border: AeDashTokens.success.withValues(alpha: 0.35),
              ),
              const SizedBox(width: 6),
            ],
            _badge(
              'Signed',
              bg: _lightOrange,
              fg: const Color(0xFF9A3412),
              border: const Color(0xFFFDBA74).withValues(alpha: 0.55),
            ),
            const SizedBox(width: 2),
            AnimatedRotation(
              turns: _expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: const Icon(
                Icons.expand_more_rounded,
                size: 22,
                color: _mutedText,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _badge(
    String label, {
    required Color bg,
    required Color fg,
    required Color border,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  Widget _detailsPanel(SignOffRecord r, _SignOffMeta meta) {
    final rows = <(String, String)>[
      ('Action', r.actionLabel),
      if (meta.room != null && meta.room!.isNotEmpty) ('Room', meta.room!),
      if (meta.guests != null && meta.guests!.isNotEmpty) ('Guests', meta.guests!),
      if (meta.residence != null && meta.residence!.isNotEmpty)
        ('Nationality / residence', meta.residence!),
      ('Date & time', formatSignOffDateTime(r.createdAt)),
      ('Signed by', r.signerName),
      if (r.signerPosition.trim().isNotEmpty) ('Position', r.signerPosition.trim()),
      if (r.accountEmail.trim().isNotEmpty) ('Account', r.accountEmail.trim()),
      if (r.signatureSha256.length >= 12)
        ('Signature ref', '#${r.signatureSha256.substring(0, 12)}'),
      if (r.platform.trim().isNotEmpty) ('Platform', r.platform.trim()),
      if (r.summary.trim().isNotEmpty) ('Summary', r.summary.trim()),
      if (r.reason.trim().isNotEmpty) ('Reason', r.reason.trim()),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 14, color: _primary),
                const SizedBox(width: 6),
                Text(
                  'Audit details',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _darkText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final row in rows) _detailRow(row.$1, row.$2),
            if (r.signaturePng != null) ...[
              const SizedBox(height: 8),
              Text(
                'Signature preview',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: _mutedText,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 72,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border),
                ),
                child: Image.memory(
                  r.signaturePng!,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ],
            if (r.details.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Notes',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: _mutedText,
                ),
              ),
              const SizedBox(height: 4),
              for (final d in r.details)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    '• $d',
                    style: GoogleFonts.inter(fontSize: 12, color: _darkText),
                  ),
                ),
            ],
            if (r.changes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Recorded changes (${r.changes.length}${r.changesTruncated > 0 ? '+${r.changesTruncated}' : ''})',
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: _mutedText,
                ),
              ),
              const SizedBox(height: 6),
              for (final c in r.changes) _changeLine(c),
              if (r.changesTruncated > 0)
                Text(
                  '…and ${r.changesTruncated} more',
                  style: GoogleFonts.inter(fontSize: 12, color: _mutedText),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack = constraints.maxWidth < 420;
          if (stack) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _mutedText,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _darkText,
                  ),
                ),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 148,
                child: Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _mutedText,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _darkText,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _changeLine(SignOffChange c) {
    final (icon, color) = switch (c.op) {
      'add' => (Icons.add_circle_outline_rounded, AeDashTokens.success),
      'delete' => (Icons.remove_circle_outline_rounded, AeDashTokens.danger),
      _ => (Icons.edit_outlined, _primary),
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
                Text(
                  c.label,
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _darkText,
                  ),
                ),
                if (c.op == 'edit' || c.op == 'set')
                  for (final d in diffs)
                    Text(
                      d,
                      style: GoogleFonts.inter(fontSize: 12, color: _mutedText),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignOffMeta {
  const _SignOffMeta({this.room, this.guests, this.residence});

  final String? room;
  final String? guests;
  final String? residence;
}

_SignOffMeta _signOffMeta(SignOffRecord r) {
  Map<String, dynamic>? map;
  for (final c in r.changes) {
    map = c.after ?? c.before;
    if (map != null) break;
  }
  if (map == null) return const _SignOffMeta();
  final room = (map['roomNo'] ?? '').toString().trim();
  final guests = map['guests']?.toString().trim() ?? '';
  final residence = (map['residence'] ?? '').toString().trim();
  return _SignOffMeta(
    room: room.isEmpty ? null : room,
    guests: guests.isEmpty ? null : guests,
    residence: residence.isEmpty ? null : residence,
  );
}

/// "field: old → new" lines for changed keys (skips bookkeeping keys).
List<String> signOffDiffLines(
  Map<String, dynamic>? before,
  Map<String, dynamic>? after,
) {
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
      if (show(b[k]) != show(a[k]))
        '${labels[k] ?? k}: ${show(b[k])} → ${show(a[k])}',
  ];
}
