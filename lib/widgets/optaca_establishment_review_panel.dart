import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/establishment_approval_service.dart';
import 'package:atmos_trs_system/services/firestore_auth_gate.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_register_compliance_panel.dart';

const _kBorder = Color(0xFFE2E8F0);
const _kSurface = Color(0xFFF8FAFC);
const _kApprove = Color(0xFF15803D);
const _kReject = Color(0xFFBE123C);

typedef _StatusStyle = ({Color fg, Color bg, String label, IconData icon});

_StatusStyle _statusStyle(EstablishmentRegistryEntry e) {
  if (e.isPending) {
    return (
      fg: const Color(0xFFB45309),
      bg: const Color(0xFFFFF7ED),
      label: 'Pending',
      icon: Icons.hourglass_top_rounded,
    );
  }
  if (e.isActive) {
    return (
      fg: const Color(0xFF047857),
      bg: const Color(0xFFECFDF5),
      label: 'Active',
      icon: Icons.verified_rounded,
    );
  }
  if (e.isRejected) {
    return (
      fg: _kReject,
      bg: const Color(0xFFFFF1F2),
      label: 'Rejected',
      icon: Icons.block_rounded,
    );
  }
  return (
    fg: const Color(0xFF475569),
    bg: const Color(0xFFF1F5F9),
    label: e.status.isEmpty ? 'Unknown' : e.status,
    icon: Icons.help_outline_rounded,
  );
}

IconData _categoryIcon(String category) {
  final c = category.toLowerCase();
  if (c.contains('resort') || c.contains('beach')) {
    return Icons.beach_access_rounded;
  }
  if (c.contains('inn') ||
      c.contains('lodge') ||
      c.contains('pension') ||
      c.contains('cottage')) {
    return Icons.cottage_rounded;
  }
  if (c.contains('home') || c.contains('house') || c.contains('bnb')) {
    return Icons.house_rounded;
  }
  if (c.contains('restaurant') || c.contains('food') || c.contains('cafe')) {
    return Icons.restaurant_rounded;
  }
  if (c.contains('hotel')) return Icons.hotel_rounded;
  return Icons.apartment_rounded;
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.entry, {this.onDark = false});

  final EstablishmentRegistryEntry entry;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final s = _statusStyle(entry);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(
        color: onDark ? Colors.white : s.bg,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: s.fg.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(s.icon, size: 13, color: s.fg),
          const SizedBox(width: 4),
          Text(
            s.label.toUpperCase(),
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: s.fg,
            ),
          ),
        ],
      ),
    );
  }
}

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
  String _filter = 'all';
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
          primaryColor: widget.primaryColor,
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
    if (!mounted) return;
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
    if (!mounted) return;
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
    return FutureBuilder<bool>(
      future: _authReady,
      builder: (context, authSnap) {
        final authDone = authSnap.connectionState == ConnectionState.done;
        return StreamBuilder<List<EstablishmentRegistryEntry>>(
          stream: authDone ? _registryStream : null,
          builder: (context, snap) {
            final all = snap.data;
            final counts = <String, int>{
              'pending': all?.where((e) => e.isPending).length ?? 0,
              'active': all?.where((e) => e.isActive).length ?? 0,
              'rejected': all?.where((e) => e.isRejected).length ?? 0,
              'all': all?.length ?? 0,
            };

            Widget body;
            if (snap.hasError) {
              final authHint = authSnap.data == true
                  ? ''
                  : '\n${FirestoreAuthGate.missingAuthMessage()}';
              body = _messageCard(
                icon: Icons.error_outline_rounded,
                color: Colors.red.shade700,
                title: 'Could not load establishments',
                message: '${snap.error}$authHint',
              );
            } else if (!authDone || all == null) {
              body = const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            } else {
              final items = _applyFilter(all);
              body = items.isEmpty ? _emptyState() : _grid(items);
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(counts),
                if (all != null && counts['pending']! > 0 && _filter != 'pending')
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _pendingBanner(counts['pending']!),
                  ),
                if (authDone) ...[
                  const SizedBox(height: 14),
                  AeRegisterCompliancePanel(
                    primaryColor: widget.primaryColor,
                    textDark: widget.textDark,
                    textMuted: widget.textMuted,
                  ),
                ],
                const SizedBox(height: 14),
                _filterTabs(counts, loaded: all != null),
                const SizedBox(height: 12),
                _searchField(),
                const SizedBox(height: 14),
                body,
              ],
            );
          },
        );
      },
    );
  }

  Widget _header(Map<String, int> counts) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppTheme.brandOrangeLight,
                widget.primaryColor,
                AppTheme.brandOrangeDark,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: widget.primaryColor.withValues(alpha: 0.28),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.storefront_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Establishments registry',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: widget.textDark,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Tap an establishment to view full details. Approve pending ones so they can file their monthly DOT register.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: widget.textMuted,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _pendingBanner(int pending) {
    return Material(
      color: const Color(0xFFFFF7ED),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _filter = 'pending'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.notifications_active_rounded,
                size: 18,
                color: Color(0xFFB45309),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$pending establishment${pending == 1 ? '' : 's'} awaiting your approval',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF9A3412),
                  ),
                ),
              ),
              const Text(
                'Review',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFB45309),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Color(0xFFB45309),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterTabs(Map<String, int> counts, {required bool loaded}) {
    const tabs = [
      ('all', 'All', Icons.apps_rounded),
      ('pending', 'Pending', Icons.hourglass_top_rounded),
      ('active', 'Active', Icons.verified_rounded),
      ('rejected', 'Rejected', Icons.block_rounded),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in tabs)
          _filterTab(
            id: t.$1,
            label: t.$2,
            icon: t.$3,
            count: loaded ? counts[t.$1] : null,
          ),
      ],
    );
  }

  Widget _filterTab({
    required String id,
    required String label,
    required IconData icon,
    int? count,
  }) {
    final selected = _filter == id;
    final accent = widget.primaryColor;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? accent : Colors.white,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: selected ? accent : _kBorder),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: () => setState(() => _filter = id),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 15,
                  color: selected ? Colors.white : widget.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : widget.textDark,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.25)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    count?.toString() ?? '·',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : widget.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _search,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Search name, municipality, owner…',
        hintStyle: TextStyle(color: widget.textMuted, fontSize: 13.5),
        prefixIcon: Icon(Icons.search_rounded, size: 20, color: widget.textMuted),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(_search.clear),
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: widget.primaryColor, width: 1.4),
        ),
      ),
    );
  }

  Widget _grid(List<EstablishmentRegistryEntry> items) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 12.0;
        final columns = c.maxWidth >= 900 ? 2 : 1;
        final w = (c.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final e in items)
              SizedBox(
                width: w,
                child: _RegistryCard(
                  entry: e,
                  primaryColor: widget.primaryColor,
                  textDark: widget.textDark,
                  textMuted: widget.textMuted,
                  onTap: () => _openDetails(e),
                  onApprove: () => _approve(e),
                  onReject: () => _reject(e),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _emptyState() {
    final searching = _search.text.trim().isNotEmpty;
    final (title, message) = searching
        ? ('No matches', 'Try a different name, municipality, or owner.')
        : _filter == 'pending'
            ? ('All caught up', 'No establishments are waiting for approval.')
            : ('Nothing here yet', 'No establishments match this filter.');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: widget.primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              searching
                  ? Icons.search_off_rounded
                  : _filter == 'pending'
                      ? Icons.task_alt_rounded
                      : Icons.storefront_outlined,
              color: widget.primaryColor,
              size: 28,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: widget.textDark,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: widget.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _messageCard({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w800, color: color),
                ),
                const SizedBox(height: 4),
                Text(message, style: TextStyle(fontSize: 12.5, color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RegistryCard extends StatefulWidget {
  const _RegistryCard({
    required this.entry,
    required this.primaryColor,
    required this.textDark,
    required this.textMuted,
    required this.onTap,
    required this.onApprove,
    required this.onReject,
  });

  final EstablishmentRegistryEntry entry;
  final Color primaryColor;
  final Color textDark;
  final Color textMuted;
  final VoidCallback onTap;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  State<_RegistryCard> createState() => _RegistryCardState();
}

class _RegistryCardState extends State<_RegistryCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final s = _statusStyle(e);
    final location = [
      if (e.municipality.isNotEmpty) e.municipality,
      if (e.barangay.isNotEmpty) e.barangay,
    ].join(' · ');

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hover ? widget.primaryColor.withValues(alpha: 0.45) : _kBorder,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hover ? 0.08 : 0.03),
              blurRadius: _hover ? 18 : 8,
              offset: Offset(0, _hover ? 6 : 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: widget.primaryColor
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Icon(
                                _categoryIcon(e.category),
                                color: widget.primaryColor,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          e.businessName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w800,
                                            color: widget.textDark,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      _StatusPill(e),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  _meta(
                                    _categoryIcon(e.category),
                                    [
                                      if (e.category.isNotEmpty) e.category,
                                      if (location.isNotEmpty) location,
                                    ].join(' · '),
                                  ),
                                  if (e.ownerName.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    _meta(
                                      Icons.person_outline_rounded,
                                      e.ownerName,
                                    ),
                                  ],
                                  if (e.roomCount != null ||
                                      e.yearEstablished != null) ...[
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        if (e.roomCount != null)
                                          _tag(
                                            Icons.bed_outlined,
                                            '${e.roomCount} room${e.roomCount == 1 ? '' : 's'}',
                                          ),
                                        if (e.yearEstablished != null)
                                          _tag(
                                            Icons.event_outlined,
                                            'Est. ${e.yearEstablished}',
                                          ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 2),
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Icon(
                                Icons.chevron_right_rounded,
                                color: _hover
                                    ? widget.primaryColor
                                    : widget.textMuted,
                              ),
                            ),
                          ],
                        ),
                        if (e.isPending) ...[
                          const SizedBox(height: 12),
                          const Divider(height: 1, color: _kBorder),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              FilledButton.icon(
                                onPressed: widget.onApprove,
                                icon: const Icon(Icons.check_rounded, size: 18),
                                label: const Text('Approve'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: _kApprove,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton.icon(
                                onPressed: widget.onReject,
                                icon: const Icon(Icons.close_rounded, size: 18),
                                label: const Text('Reject'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _kReject,
                                  side: BorderSide(
                                    color: _kReject.withValues(alpha: 0.4),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: widget.onTap,
                                style: TextButton.styleFrom(
                                  foregroundColor: widget.primaryColor,
                                ),
                                child: const Text('Details'),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Container(width: 4, color: s.fg),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(icon, size: 14, color: widget.textMuted),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: widget.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _tag(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: widget.textMuted),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: widget.textDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _EstablishmentDetailSheet extends StatelessWidget {
  const _EstablishmentDetailSheet({
    required this.entry,
    required this.primaryColor,
    required this.textDark,
    required this.textMuted,
    this.onApprove,
    this.onReject,
  });

  final EstablishmentRegistryEntry entry;
  final Color primaryColor;
  final Color textDark;
  final Color textMuted;
  final Future<void> Function()? onApprove;
  final Future<void> Function()? onReject;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final reviewed = e.reviewedAt == null
        ? null
        : _formatReviewedAt(e.reviewedAt!);
    final maxH = MediaQuery.sizeOf(context).height * 0.9;
    final hasActions = onApprove != null || onReject != null;
    final checkTimes = e.checkInTime.isNotEmpty || e.checkOutTime.isNotEmpty
        ? '${e.checkInTime.isEmpty ? '—' : e.checkInTime} – '
            '${e.checkOutTime.isEmpty ? '—' : e.checkOutTime}'
        : '';

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH, maxWidth: 660),
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _hero(context),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _statTile(
                              Icons.bed_outlined,
                              e.roomCount?.toString() ?? '—',
                              'Total rooms',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _statTile(
                              Icons.event_outlined,
                              e.yearEstablished?.toString() ?? '—',
                              'Established',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _statTile(
                              Icons.schedule_rounded,
                              checkTimes.isEmpty ? '—' : checkTimes,
                              'Check-in / out',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _section(Icons.storefront_outlined, 'Business', [
                        _row('Category', e.category),
                        _row('Municipality', e.municipality),
                        _row('Municipality ID', e.municipalityId),
                        _row('Barangay', e.barangay),
                      ]),
                      const SizedBox(height: 12),
                      _section(
                        Icons.person_outline_rounded,
                        'Owner & contact',
                        [
                          _row('Owner', e.ownerName),
                          _row(
                            'Email',
                            e.email,
                            actionIcon: Icons.mail_outline_rounded,
                            actionTooltip: 'Send email',
                            onAction: () => _launch(
                              Uri(scheme: 'mailto', path: e.email.trim()),
                            ),
                          ),
                          _row(
                            'Contact number',
                            e.contactNumber,
                            actionIcon: Icons.call_outlined,
                            actionTooltip: 'Call',
                            onAction: () => _launch(
                              Uri(scheme: 'tel', path: e.contactNumber.trim()),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _section(
                        Icons.verified_user_outlined,
                        'Permit & review',
                        [
                          _row('Business permit no.', e.businessPermitNo),
                          _row('Reviewed at', reviewed ?? ''),
                          _row('Review notes', e.reviewNotes),
                          _row(
                            'Registry ID',
                            e.id,
                            mono: true,
                            actionIcon: Icons.copy_rounded,
                            actionTooltip: 'Copy registry ID',
                            onAction: () => _copyId(context),
                          ),
                        ],
                      ),
                      if (e.businessPermitUrl.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            final uri = Uri.tryParse(e.businessPermitUrl);
                            if (uri != null) _launch(uri);
                          },
                          icon: const Icon(Icons.image_outlined, size: 18),
                          label: const Text('View permit photo'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: primaryColor,
                            side: BorderSide(
                              color: primaryColor.withValues(alpha: 0.45),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (hasActions) _actionBar(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) {
    final e = entry;
    final subtitle = [
      if (e.category.isNotEmpty) e.category,
      if (e.municipality.isNotEmpty) e.municipality,
    ].join(' · ');
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.brandOrangeLight,
            primaryColor,
            AppTheme.brandOrangeDark,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            top: -40,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            right: 70,
            bottom: -50,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 10, 18),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Icon(
                        _categoryIcon(e.category),
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.businessName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.15,
                            ),
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          _StatusPill(e, onDark: true),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.18),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: primaryColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: textDark,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(IconData icon, String title, List<Widget> rows) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            color: _kSurface,
            child: Row(
              children: [
                Icon(icon, size: 17, color: primaryColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: textDark,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _kBorder),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                indent: 14,
                endIndent: 14,
                color: Color(0xFFF1F5F9),
              ),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _row(
    String label,
    String value, {
    bool mono = false,
    IconData? actionIcon,
    String? actionTooltip,
    VoidCallback? onAction,
  }) {
    final v = value.trim();
    final empty = v.isEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: textMuted),
            ),
          ),
          Expanded(
            child: SelectableText(
              empty ? 'Not provided' : v,
              style: TextStyle(
                fontSize: mono ? 12.5 : 13.5,
                fontWeight: empty ? FontWeight.w400 : FontWeight.w600,
                fontStyle: empty ? FontStyle.italic : FontStyle.normal,
                fontFamily: mono ? 'monospace' : null,
                letterSpacing: mono ? 0.3 : null,
                color: empty ? const Color(0xFF94A3B8) : textDark,
              ),
            ),
          ),
          if (actionIcon != null && !empty)
            IconButton(
              tooltip: actionTooltip,
              onPressed: onAction,
              visualDensity: VisualDensity.compact,
              iconSize: 17,
              color: primaryColor,
              icon: Icon(actionIcon),
            )
          else
            const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _actionBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        12 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: _kBorder)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          if (onReject != null)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onReject!(),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('Reject'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kReject,
                  side: BorderSide(color: _kReject.withValues(alpha: 0.45)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          if (onApprove != null && onReject != null) const SizedBox(width: 10),
          if (onApprove != null)
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: () => onApprove!(),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Approve establishment'),
                style: FilledButton.styleFrom(
                  backgroundColor: _kApprove,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _copyId(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: entry.id));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Registry ID copied'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static Future<void> _launch(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
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
