import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/establishment_approval_service.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/widgets/ae_register/ae_register_compliance_panel.dart';
import 'package:atmos_trs_system/widgets/ui_skeleton.dart';

/// LGU view-only registry of establishments in this municipality.
/// Approval stays with OPTACA; LGU uses this for inventory + Analytics context.
class LguEstablishmentRegistryPanel extends StatefulWidget {
  const LguEstablishmentRegistryPanel({
    super.key,
    required this.municipalityId,
    this.municipalityName,
    this.primaryColor = AppTheme.brandOrange,
    this.textDark = const Color(0xFF1F2937),
    this.textMuted = const Color(0xFF6B7280),
  });

  final String? municipalityId;
  final String? municipalityName;
  final Color primaryColor;
  final Color textDark;
  final Color textMuted;

  @override
  State<LguEstablishmentRegistryPanel> createState() =>
      _LguEstablishmentRegistryPanelState();
}

const _kBorder = Color(0xFFE2E8F0);
const _kActive = Color(0xFF059669);
const _kPending = Color(0xFFD97706);
const _kRejected = Color(0xFFE11D48);

enum _SortMode { name, rooms, status }

class _LguEstablishmentRegistryPanelState
    extends State<LguEstablishmentRegistryPanel> {
  String _filter = 'all';
  _SortMode _sort = _SortMode.status;
  final _search = TextEditingController();

  // Kept across search / filter rebuilds so typing does not re-subscribe.
  Stream<List<EstablishmentRegistryEntry>>? _registryStream;
  String _registryStreamMid = '';

  Stream<List<EstablishmentRegistryEntry>> _registryStreamFor(String mid) {
    if (_registryStream == null || _registryStreamMid != mid) {
      _registryStreamMid = mid;
      _registryStream = EstablishmentApprovalService.watchForMunicipality(mid);
    }
    return _registryStream!;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<EstablishmentRegistryEntry> _applyFilter(
    List<EstablishmentRegistryEntry> all,
  ) {
    final q = _search.text.trim().toLowerCase();
    final list = all.where((e) {
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
        e.barangay,
        e.email,
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();

    int statusRank(EstablishmentRegistryEntry e) =>
        e.isPending ? 0 : (e.isActive ? 1 : 2);
    switch (_sort) {
      case _SortMode.name:
        list.sort((a, b) => a.businessName
            .toLowerCase()
            .compareTo(b.businessName.toLowerCase()));
      case _SortMode.rooms:
        list.sort((a, b) => (b.roomCount ?? 0).compareTo(a.roomCount ?? 0));
      case _SortMode.status:
        list.sort((a, b) {
          final r = statusRank(a).compareTo(statusRank(b));
          if (r != 0) return r;
          return a.businessName
              .toLowerCase()
              .compareTo(b.businessName.toLowerCase());
        });
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final mid = normalizeMunicipalityId(widget.municipalityId);
    final scopeLabel = (widget.municipalityName?.trim().isNotEmpty == true)
        ? widget.municipalityName!.trim()
        : (mid.isNotEmpty ? mid : 'this municipality');

    if (mid.isEmpty) {
      return _EmptyState(
        icon: Icons.location_off_outlined,
        title: 'Municipality not set',
        message:
            'Municipality is not set for this LGU session, so establishments cannot be scoped.',
        color: widget.textMuted,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(scopeLabel),
        const SizedBox(height: 16),
        AeRegisterCompliancePanel(
          municipalityId: mid,
          primaryColor: widget.primaryColor,
          textDark: widget.textDark,
          textMuted: widget.textMuted,
        ),
        const SizedBox(height: 20),
        StreamBuilder<List<EstablishmentRegistryEntry>>(
          stream: _registryStreamFor(mid),
          builder: (context, snap) {
            if (snap.hasError) {
              return _EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Could not load establishments',
                message: '${snap.error}',
                color: _kRejected,
              );
            }
            if (!snap.hasData) return const _RegistrySkeleton();

            final all = snap.data!;
            final pending = all.where((e) => e.isPending).length;
            final active = all.where((e) => e.isActive).length;
            final rejected = all.where((e) => e.isRejected).length;
            final rooms = all
                .where((e) => e.isActive)
                .fold<int>(0, (sum, e) => sum + (e.roomCount ?? 0));
            final items = _applyFilter(all);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildKpis(
                  total: all.length,
                  active: active,
                  pending: pending,
                  rejected: rejected,
                  rooms: rooms,
                ),
                const SizedBox(height: 18),
                _buildToolbar(
                  total: all.length,
                  active: active,
                  pending: pending,
                  rejected: rejected,
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      items.length == all.length
                          ? '${all.length} establishment${all.length == 1 ? '' : 's'}'
                          : 'Showing ${items.length} of ${all.length}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: widget.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  _EmptyState(
                    icon: all.isEmpty
                        ? Icons.apartment_rounded
                        : Icons.search_off_rounded,
                    title: all.isEmpty
                        ? 'No establishments yet'
                        : 'No matches',
                    message: all.isEmpty
                        ? 'No establishments registered in $scopeLabel yet. '
                            'New registrations appear here once submitted to OPTACA.'
                        : 'No establishments match this filter or search.',
                    color: widget.textMuted,
                  )
                else
                  _buildGrid(items),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildHeader(String scopeLabel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    widget.primaryColor,
                    Color.lerp(widget.primaryColor, Colors.black, 0.15)!,
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.apartment_rounded,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Establishments in $scopeLabel',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: widget.textDark,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Accommodation & tourism business inventory',
                    style: TextStyle(fontSize: 12.5, color: widget.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 18, color: Color(0xFF2563EB)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'View only. OPTACA approves new registrations. Active hotels '
                  'fill a monthly DOT register (DAE-1B) that feeds the DAE forms in Analytics.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: Color(0xFF1E3A8A),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKpis({
    required int total,
    required int active,
    required int pending,
    required int rejected,
    required int rooms,
  }) {
    final cards = [
      (
        filter: 'all',
        label: 'Total',
        value: total,
        icon: Icons.apartment_rounded,
        color: widget.primaryColor,
      ),
      (
        filter: 'active',
        label: 'Active',
        value: active,
        icon: Icons.verified_rounded,
        color: _kActive,
      ),
      (
        filter: 'pending',
        label: 'Pending OPTACA',
        value: pending,
        icon: Icons.hourglass_top_rounded,
        color: _kPending,
      ),
      (
        filter: 'rejected',
        label: 'Rejected',
        value: rejected,
        icon: Icons.block_rounded,
        color: _kRejected,
      ),
      (
        filter: '',
        label: 'Active rooms',
        value: rooms,
        icon: Icons.bed_rounded,
        color: const Color(0xFF7C3AED),
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        const gap = 12.0;
        final perRow = c.maxWidth >= 900
            ? 5
            : c.maxWidth >= 560
                ? 3
                : 2;
        final w = (c.maxWidth - gap * (perRow - 1)) / perRow;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final k in cards)
              SizedBox(
                width: w,
                child: _KpiCard(
                  label: k.label,
                  value: '${k.value}',
                  icon: k.icon,
                  color: k.color,
                  selected: k.filter.isNotEmpty && _filter == k.filter,
                  onTap: k.filter.isEmpty
                      ? null
                      : () => setState(() => _filter = k.filter),
                  textMuted: widget.textMuted,
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildToolbar({
    required int total,
    required int active,
    required int pending,
    required int rejected,
  }) {
    final search = TextField(
      controller: _search,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Search name, category, owner, barangay…',
        hintStyle: TextStyle(color: widget.textMuted, fontSize: 14),
        prefixIcon: Icon(Icons.search_rounded, size: 20, color: widget.textMuted),
        suffixIcon: _search.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(_search.clear),
              ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: widget.primaryColor, width: 1.5),
        ),
      ),
    );

    final sort = Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_SortMode>(
          value: _sort,
          icon: Icon(Icons.expand_more_rounded, color: widget.textMuted),
          borderRadius: BorderRadius.circular(12),
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: widget.textDark,
          ),
          items: const [
            DropdownMenuItem(
              value: _SortMode.status,
              child: Text('Sort: Status'),
            ),
            DropdownMenuItem(
              value: _SortMode.name,
              child: Text('Sort: Name A–Z'),
            ),
            DropdownMenuItem(
              value: _SortMode.rooms,
              child: Text('Sort: Most rooms'),
            ),
          ],
          onChanged: (v) {
            if (v != null) setState(() => _sort = v);
          },
        ),
      ),
    );

    final pills = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final f in [
          ('all', 'All', total, widget.primaryColor),
          ('active', 'Active', active, _kActive),
          ('pending', 'Pending', pending, _kPending),
          ('rejected', 'Rejected', rejected, _kRejected),
        ])
          _FilterPill(
            label: f.$2,
            count: f.$3,
            color: f.$4,
            selected: _filter == f.$1,
            onTap: () => setState(() => _filter = f.$1),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 720;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 10),
                  sort,
                ],
              )
            else ...[
              search,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: sort),
            ],
            const SizedBox(height: 12),
            pills,
          ],
        );
      },
    );
  }

  Widget _buildGrid(List<EstablishmentRegistryEntry> items) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 12.0;
        final cols = c.maxWidth >= 1400
            ? 3
            : c.maxWidth >= 860
                ? 2
                : 1;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final e in items)
              SizedBox(
                width: w,
                child: _EstablishmentCard(
                  entry: e,
                  primaryColor: widget.primaryColor,
                  textDark: widget.textDark,
                  textMuted: widget.textMuted,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatefulWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
    required this.textMuted,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback? onTap;
  final Color textMuted;

  @override
  State<_KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<_KpiCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    final active = widget.selected || (_hover && widget.onTap != null);
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: widget.selected ? c.withValues(alpha: 0.06) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.selected ? c.withValues(alpha: 0.55) : _kBorder,
              width: widget.selected ? 1.5 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: active ? 0.07 : 0.03),
                blurRadius: active ? 14 : 8,
                offset: Offset(0, active ? 5 : 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icon, color: c, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.value,
                      style: TextStyle(
                        fontSize: 22,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                        color: c,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: widget.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: BoxDecoration(
            color: selected ? color : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? color : _kBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : const Color(0xFF334155),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.25)
                      : color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EstablishmentCard extends StatefulWidget {
  const _EstablishmentCard({
    required this.entry,
    required this.primaryColor,
    required this.textDark,
    required this.textMuted,
  });

  final EstablishmentRegistryEntry entry;
  final Color primaryColor;
  final Color textDark;
  final Color textMuted;

  @override
  State<_EstablishmentCard> createState() => _EstablishmentCardState();
}

class _EstablishmentCardState extends State<_EstablishmentCard> {
  bool _hover = false;

  static IconData _categoryIcon(String category) {
    final c = category.toLowerCase();
    if (c.contains('resort') || c.contains('beach')) {
      return Icons.beach_access_rounded;
    }
    if (c.contains('hotel')) return Icons.hotel_rounded;
    if (c.contains('home') || c.contains('bnb') || c.contains('b&b')) {
      return Icons.house_rounded;
    }
    if (c.contains('inn') ||
        c.contains('lodg') ||
        c.contains('pension') ||
        c.contains('hostel') ||
        c.contains('apartel')) {
      return Icons.night_shelter_rounded;
    }
    if (c.contains('restaurant') || c.contains('food') || c.contains('cafe')) {
      return Icons.restaurant_rounded;
    }
    if (c.contains('travel') || c.contains('tour')) return Icons.flight_rounded;
    return Icons.storefront_rounded;
  }

  static String _formatClock(String raw) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(raw.trim());
    if (m == null) return raw;
    final h = int.parse(m.group(1)!);
    final min = m.group(2)!;
    final suffix = h >= 12 ? 'PM' : 'AM';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$min $suffix';
  }

  static String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final statusColor =
        e.isPending ? _kPending : (e.isActive ? _kActive : _kRejected);
    final statusLabel =
        e.isPending ? 'Pending' : (e.isActive ? 'Active' : 'Rejected');

    final facts = <({IconData icon, String text})>[
      if (e.roomCount != null)
        (icon: Icons.bed_rounded, text: '${e.roomCount} rooms'),
      if (e.checkInTime.isNotEmpty)
        (icon: Icons.login_rounded, text: 'In ${_formatClock(e.checkInTime)}'),
      if (e.checkOutTime.isNotEmpty)
        (
          icon: Icons.logout_rounded,
          text: 'Out ${_formatClock(e.checkOutTime)}',
        ),
      if (e.yearEstablished != null)
        (icon: Icons.history_rounded, text: 'Since ${e.yearEstablished}'),
    ];

    final subtitle = [
      if (e.category.isNotEmpty) e.category,
      if (e.barangay.isNotEmpty) 'Brgy. ${e.barangay}',
    ].join(' · ');

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: _hover ? statusColor.withValues(alpha: 0.35) : _kBorder,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: _hover ? 0.08 : 0.035),
              blurRadius: _hover ? 18 : 10,
              offset: Offset(0, _hover ? 8 : 3),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 4, color: statusColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
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
                              color:
                                  widget.primaryColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(14),
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
                                Text(
                                  e.businessName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 16,
                                    height: 1.25,
                                    fontWeight: FontWeight.w800,
                                    color: widget.textDark,
                                  ),
                                ),
                                if (subtitle.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    subtitle,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: widget.textMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusBadge(label: statusLabel, color: statusColor),
                        ],
                      ),
                      if (facts.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final f in facts)
                              _FactChip(
                                icon: f.icon,
                                text: f.text,
                                textColor: widget.textDark,
                              ),
                          ],
                        ),
                      ],
                      if (e.ownerName.isNotEmpty ||
                          e.email.isNotEmpty ||
                          e.contactNumber.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Divider(height: 1, color: _kBorder),
                        const SizedBox(height: 10),
                        if (e.ownerName.isNotEmpty)
                          _InfoLine(
                            icon: Icons.person_outline_rounded,
                            text: e.ownerName,
                            label: 'Owner',
                            color: widget.textMuted,
                            textColor: widget.textDark,
                          ),
                        if (e.email.isNotEmpty)
                          _InfoLine(
                            icon: Icons.mail_outline_rounded,
                            text: e.email,
                            color: widget.textMuted,
                            textColor: widget.textDark,
                            onTap: () => _launch('mailto:${e.email}'),
                          ),
                        if (e.contactNumber.isNotEmpty)
                          _InfoLine(
                            icon: Icons.phone_outlined,
                            text: e.contactNumber,
                            color: widget.textMuted,
                            textColor: widget.textDark,
                            onTap: () => _launch(
                              'tel:${e.contactNumber.replaceAll(RegExp(r'[^0-9+]'), '')}',
                            ),
                          ),
                      ],
                      if (e.isPending) ...[
                        const SizedBox(height: 10),
                        const _Notice(
                          icon: Icons.hourglass_top_rounded,
                          text:
                              'Awaiting OPTACA approval — cannot file a DOT register yet.',
                          color: _kPending,
                          background: Color(0xFFFFFBEB),
                        ),
                      ],
                      if (e.isRejected) ...[
                        const SizedBox(height: 10),
                        _Notice(
                          icon: Icons.error_outline_rounded,
                          text: e.reviewNotes.trim().isNotEmpty
                              ? 'Rejected by OPTACA: ${e.reviewNotes.trim()}'
                              : 'Rejected by OPTACA.',
                          color: _kRejected,
                          background: const Color(0xFFFFF1F2),
                        ),
                      ],
                      if (e.businessPermitUrl.isNotEmpty ||
                          e.businessPermitNo.isNotEmpty ||
                          e.reviewedAt != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            if (e.businessPermitUrl.isNotEmpty)
                              OutlinedButton.icon(
                                onPressed: () =>
                                    _launch(e.businessPermitUrl),
                                icon: const Icon(Icons.description_outlined,
                                    size: 16),
                                label: const Text('View permit'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: widget.primaryColor,
                                  side: BorderSide(
                                    color: widget.primaryColor
                                        .withValues(alpha: 0.4),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                              )
                            else if (e.businessPermitNo.isNotEmpty)
                              Flexible(
                                child: Text(
                                  'Permit No. ${e.businessPermitNo}',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: widget.textMuted,
                                  ),
                                ),
                              ),
                            const Spacer(),
                            if (e.reviewedAt != null)
                              Text(
                                'Reviewed ${_formatDate(e.reviewedAt!)}',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: widget.textMuted,
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
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({
    required this.icon,
    required this.text,
    required this.textColor,
  });

  final IconData icon;
  final String text;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF64748B)),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.text,
    required this.color,
    required this.textColor,
    this.label,
    this.onTap,
  });

  final IconData icon;
  final String text;
  final Color color;
  final Color textColor;
  final String? label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          if (label != null)
            Text(
              '$label: ',
              style: TextStyle(fontSize: 13, color: color),
            ),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: onTap != null ? const Color(0xFF2563EB) : textColor,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: row),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.text,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String text;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.4, color: color),
          ),
        ],
      ),
    );
  }
}

class _RegistrySkeleton extends StatelessWidget {
  const _RegistrySkeleton();

  @override
  Widget build(BuildContext context) {
    return ShimmerScope(
      child: LayoutBuilder(
        builder: (context, c) {
          final perRow = c.maxWidth >= 900 ? 5 : (c.maxWidth >= 560 ? 3 : 2);
          final kpiW = (c.maxWidth - 12 * (perRow - 1)) / perRow;
          final cols = c.maxWidth >= 860 ? 2 : 1;
          final cardW = (c.maxWidth - 12 * (cols - 1)) / cols;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < 5; i++)
                    SkeletonBox(width: kpiW, height: 70, borderRadius: 16),
                ],
              ),
              const SizedBox(height: 18),
              const SkeletonBox(height: 48, borderRadius: 12),
              const SizedBox(height: 12),
              const SkeletonBox(width: 320, height: 34, borderRadius: 999),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var i = 0; i < 4; i++)
                    SkeletonBox(width: cardW, height: 150, borderRadius: 18),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
