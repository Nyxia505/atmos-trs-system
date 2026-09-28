import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/establishment_approval_service.dart';
import 'package:atmos_trs_system/services/firestore_auth_gate.dart';

/// OPTACA inbox: approve / reject tourism establishment registrations.
class OptacaEstablishmentReviewPanel extends StatefulWidget {
  const OptacaEstablishmentReviewPanel({
    super.key,
    this.primaryColor = AppTheme.brandOrange,
    this.textDark = const Color(0xFF1F2937),
    this.textMuted = const Color(0xFF6B7280),
  });

  final Color primaryColor;
  final Color textDark;
  final Color textMuted;

  @override
  State<OptacaEstablishmentReviewPanel> createState() =>
      _OptacaEstablishmentReviewPanelState();
}

class _OptacaEstablishmentReviewPanelState
    extends State<OptacaEstablishmentReviewPanel> {
  String _filter = 'pending';
  final _search = TextEditingController();
  final _notes = TextEditingController();
  late Future<bool> _authReady;
  // Created on first use (after auth is ready) and kept across search / filter rebuilds.
  late final Stream<List<EstablishmentRegistryEntry>> _registryStream =
      EstablishmentApprovalService.watchAll();

  @override
  void initState() {
    super.initState();
    _authReady = FirestoreAuthGate.ensureFreshIdToken();
  }

  @override
  void dispose() {
    _search.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<EstablishmentRegistryEntry> _applyFilter(
    List<EstablishmentRegistryEntry> all,
  ) {
    final q = _search.text.trim().toLowerCase();
    return all.where((e) {
      final statusOk = switch (_filter) {
        'pending' => e.isPending,
        'active' => e.isActive,
        'rejected' => e.isRejected,
        _ => true,
      };
      if (!statusOk) return false;
      if (q.isEmpty) return true;
      final hay = [
        e.businessName,
        e.category,
        e.ownerName,
        e.municipality,
        e.email,
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  Future<void> _openDetails(EstablishmentRegistryEntry e) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _EstablishmentDetailSheet(
          entry: e,
          textDark: widget.textDark,
          textMuted: widget.textMuted,
          onApprove: e.isPending
              ? () async {
                  Navigator.pop(ctx);
                  await _approve(e);
                }
              : null,
          onReject: e.isPending
              ? () async {
                  Navigator.pop(ctx);
                  await _reject(e);
                }
              : null,
        );
      },
    );
  }

  Future<void> _approve(EstablishmentRegistryEntry e) async {
    final tokenOk = await FirestoreAuthGate.ensureFreshIdToken();
    if (!tokenOk) {
      _snack(FirestoreAuthGate.missingAuthMessage(), error: true);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve establishment?'),
        content: Text(
          '${e.businessName} (${e.municipality}) will become active on ATMOS-TRS.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await EstablishmentApprovalService.approve(e.id);
      if (!mounted) return;
      _snack('Approved ${e.businessName}');
    } catch (err) {
      if (!mounted) return;
      _snack('Approve failed: $err', error: true);
    }
  }

  Future<void> _reject(EstablishmentRegistryEntry e) async {
    final tokenOk = await FirestoreAuthGate.ensureFreshIdToken();
    if (!tokenOk) {
      _snack(FirestoreAuthGate.missingAuthMessage(), error: true);
      return;
    }
    _notes.clear();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject establishment?'),
        content: TextField(
          controller: _notes,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            border: OutlineInputBorder(),
          ),
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
    if (ok != true) return;
    try {
      await EstablishmentApprovalService.reject(e.id, notes: _notes.text);
      if (!mounted) return;
      _snack('Rejected ${e.businessName}');
    } catch (err) {
      if (!mounted) return;
      _snack('Reject failed: $err', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : widget.primaryColor,
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
          'Establishments registry',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: widget.textDark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap an establishment to view full details. Approve pending ones so they can run stay QR confirmation.',
          style:
              TextStyle(fontSize: 12.5, color: widget.textMuted, height: 1.35),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in const [
              ('pending', 'Pending'),
              ('active', 'Active'),
              ('rejected', 'Rejected'),
              ('all', 'All'),
            ])
              FilterChip(
                label: Text(f.$2),
                selected: _filter == f.$1,
                onSelected: (_) => setState(() => _filter = f.$1),
                selectedColor: widget.primaryColor.withValues(alpha: 0.18),
                checkmarkColor: widget.primaryColor,
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Search name, municipality, owner…',
            prefixIcon: const Icon(Icons.search, size: 20),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
          ),
        ),
        const SizedBox(height: 14),
        FutureBuilder<bool>(
          future: _authReady,
          builder: (context, authSnap) {
            if (authSnap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return StreamBuilder<List<EstablishmentRegistryEntry>>(
              stream: _registryStream,
              builder: (context, snap) {
                if (snap.hasError) {
                  final authHint = authSnap.data == true
                      ? ''
                      : '\n${FirestoreAuthGate.missingAuthMessage()}';
                  return Text(
                    'Could not load establishments: ${snap.error}$authHint',
                    style: TextStyle(color: Colors.red.shade700),
                  );
                }
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final items = _applyFilter(snap.data!);
                if (items.isEmpty) {
                  return Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      _filter == 'pending'
                          ? 'No pending establishments.'
                          : 'No establishments match this filter.',
                      style: TextStyle(color: widget.textMuted),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final e in items) ...[
                      _card(e),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _card(EstablishmentRegistryEntry e) {
    final statusColor = e.isPending
        ? const Color(0xFF9A3412)
        : e.isActive
            ? const Color(0xFF065F46)
            : const Color(0xFF9F1239);
    final statusBg = e.isPending
        ? const Color(0xFFFFF7ED)
        : e.isActive
            ? const Color(0xFFECFDF5)
            : const Color(0xFFFFF1F2);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => _openDetails(e),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      e.businessName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: widget.textDark,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      e.status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: widget.textMuted,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                [
                  if (e.category.isNotEmpty) e.category,
                  if (e.municipality.isNotEmpty) e.municipality,
                  if (e.barangay.isNotEmpty) e.barangay,
                ].join(' · '),
                style: TextStyle(fontSize: 13, color: widget.textMuted),
              ),
              if (e.ownerName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  'Owner: ${e.ownerName}',
                  style: TextStyle(fontSize: 13, color: widget.textDark),
                ),
              ],
              if (e.isPending) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton(
                      onPressed: () => _approve(e),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                      ),
                      child: const Text('Approve'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _reject(e),
                      child: const Text('Reject'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => _openDetails(e),
                      child: const Text('Details'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EstablishmentDetailSheet extends StatelessWidget {
  const _EstablishmentDetailSheet({
    required this.entry,
    required this.textDark,
    required this.textMuted,
    this.onApprove,
    this.onReject,
  });

  final EstablishmentRegistryEntry entry;
  final Color textDark;
  final Color textMuted;
  final Future<void> Function()? onApprove;
  final Future<void> Function()? onReject;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final statusColor = e.isPending
        ? const Color(0xFF9A3412)
        : e.isActive
            ? const Color(0xFF065F46)
            : const Color(0xFF9F1239);
    final statusBg = e.isPending
        ? const Color(0xFFFFF7ED)
        : e.isActive
            ? const Color(0xFFECFDF5)
            : const Color(0xFFFFF1F2);
    final reviewed = e.reviewedAt == null
        ? null
        : _formatReviewedAt(e.reviewedAt!);
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH, maxWidth: 640),
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.businessName,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: textDark,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              e.status.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _section('Business', [
                        _row('Category', e.category),
                        _row('Municipality', e.municipality),
                        _row('Municipality ID', e.municipalityId),
                        _row('Barangay', e.barangay),
                        _row(
                          'Year established',
                          e.yearEstablished?.toString() ?? '',
                        ),
                        _row(
                          'Total rooms',
                          e.roomCount?.toString() ?? '',
                        ),
                      ]),
                      const SizedBox(height: 16),
                      _section('Owner & contact', [
                        _row('Owner', e.ownerName),
                        _row('Email', e.email),
                        _row('Contact number', e.contactNumber),
                      ]),
                      const SizedBox(height: 16),
                      _section('Permit & review', [
                        _row('Business permit no.', e.businessPermitNo),
                        _row('Reviewed at', reviewed ?? ''),
                        _row('Review notes', e.reviewNotes),
                        _row('Registry ID', e.id),
                      ]),
                      if (e.businessPermitUrl.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            final uri = Uri.tryParse(e.businessPermitUrl);
                            if (uri != null) {
                              await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                            }
                          },
                          icon: const Icon(Icons.photo_outlined),
                          label: const Text('View permit photo'),
                        ),
                      ],
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: e.id));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Registry ID copied'),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('Copy registry ID'),
                      ),
                      if (onApprove != null || onReject != null) ...[
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            if (onApprove != null)
                              Expanded(
                                child: FilledButton(
                                  onPressed: () => onApprove!(),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.green.shade700,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                  child: const Text('Approve'),
                                ),
                              ),
                            if (onApprove != null && onReject != null)
                              const SizedBox(width: 10),
                            if (onReject != null)
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => onReject!(),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red.shade700,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                  child: const Text('Reject'),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: textDark,
            ),
          ),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    final v = value.trim().isEmpty ? '—' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: textMuted),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatReviewedAt(DateTime d) {
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
    final h24 = d.hour;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final ampm = h24 >= 12 ? 'PM' : 'AM';
    final mm = d.minute.toString().padLeft(2, '0');
    return '${months[d.month - 1]} ${d.day}, ${d.year} · $h12:$mm $ampm';
  }
}
