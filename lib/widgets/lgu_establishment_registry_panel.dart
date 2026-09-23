import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/establishment_approval_service.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

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

class _LguEstablishmentRegistryPanelState
    extends State<LguEstablishmentRegistryPanel> {
  String _filter = 'all';
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
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
        e.barangay,
        e.email,
      ].join(' ').toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final mid = normalizeMunicipalityId(widget.municipalityId);
    final scopeLabel = (widget.municipalityName?.trim().isNotEmpty == true)
        ? widget.municipalityName!.trim()
        : (mid.isNotEmpty ? mid : 'this municipality');

    if (mid.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Text(
          'Municipality is not set for this LGU session, so establishments cannot be scoped.',
          style: TextStyle(color: widget.textMuted, height: 1.4),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Establishments in $scopeLabel',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: widget.textDark,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'View-only inventory for Analytics and local tourism ops. '
          'OPTACA approves new registrations; confirmed stays feed DAE forms.',
          style:
              TextStyle(fontSize: 12.5, color: widget.textMuted, height: 1.35),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<EstablishmentRegistryEntry>>(
          stream: EstablishmentApprovalService.watchForMunicipality(mid),
          builder: (context, snap) {
            if (snap.hasError) {
              return Text(
                'Could not load establishments: ${snap.error}',
                style: TextStyle(color: Colors.red.shade700),
              );
            }
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final all = snap.data!;
            final pending = all.where((e) => e.isPending).length;
            final active = all.where((e) => e.isActive).length;
            final rejected = all.where((e) => e.isRejected).length;
            final items = _applyFilter(all);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _kpi('Total', '${all.length}', widget.primaryColor),
                    _kpi('Active', '$active', const Color(0xFF059669)),
                    _kpi('Pending OPTACA', '$pending', const Color(0xFF9A3412)),
                    _kpi('Rejected', '$rejected', const Color(0xFF9F1239)),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final f in const [
                      ('all', 'All'),
                      ('active', 'Active'),
                      ('pending', 'Pending'),
                      ('rejected', 'Rejected'),
                    ])
                      FilterChip(
                        label: Text(f.$2),
                        selected: _filter == f.$1,
                        onSelected: (_) => setState(() => _filter = f.$1),
                        selectedColor:
                            widget.primaryColor.withValues(alpha: 0.18),
                        checkmarkColor: widget.primaryColor,
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search name, category, owner…',
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
                if (items.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Text(
                      all.isEmpty
                          ? 'No establishments registered in $scopeLabel yet.'
                          : 'No establishments match this filter.',
                      style: TextStyle(color: widget.textMuted),
                    ),
                  )
                else
                  for (final e in items) ...[
                    _card(e),
                    const SizedBox(height: 10),
                  ],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _kpi(String label, String value, Color accent) {
    return Container(
      width: 140,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: widget.textMuted)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
        ],
      ),
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
          const SizedBox(height: 6),
          Text(
            [
              if (e.category.isNotEmpty) e.category,
              if (e.barangay.isNotEmpty) e.barangay,
              if (e.roomCount != null) '${e.roomCount} rooms',
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
          if (e.email.isNotEmpty || e.contactNumber.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              [e.email, e.contactNumber].where((s) => s.isNotEmpty).join(' · '),
              style: TextStyle(fontSize: 12.5, color: widget.textMuted),
            ),
          ],
          if (e.businessPermitUrl.isNotEmpty) ...[
            const SizedBox(height: 4),
            TextButton(
              onPressed: () async {
                final uri = Uri.tryParse(e.businessPermitUrl);
                if (uri != null) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              child: const Text('View permit photo'),
            ),
          ],
          if (e.isPending) ...[
            const SizedBox(height: 8),
            Text(
              'Awaiting OPTACA approval — not yet active for stay QR.',
              style: TextStyle(
                fontSize: 12,
                color: statusColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
