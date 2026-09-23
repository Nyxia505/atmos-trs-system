import 'package:flutter/material.dart';

import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:atmos_trs_system/screens/governor_entity_analytics_screen.dart';
import 'package:atmos_trs_system/services/establishment_approval_service.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';

/// Governor L2: spots + establishments for one municipality (replaces city list).
class GovernorMunicipalityPlacesScreen extends StatelessWidget {
  const GovernorMunicipalityPlacesScreen({
    super.key,
    required this.municipalityId,
    required this.municipalityName,
    required this.municipalityType,
    required this.spots,
    required this.checkIns,
    required this.tourists,
  });

  final String municipalityId;
  final String municipalityName;
  final String municipalityType;
  final List<Map<String, dynamic>> spots;
  final List<Map<String, dynamic>> checkIns;
  final List<Map<String, dynamic>> tourists;

  static Future<void> open(
    BuildContext context, {
    required String municipalityId,
    required String municipalityName,
    required String municipalityType,
    required List<Map<String, dynamic>> spots,
    required List<Map<String, dynamic>> checkIns,
    required List<Map<String, dynamic>> tourists,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GovernorMunicipalityPlacesScreen(
          municipalityId: municipalityId,
          municipalityName: municipalityName,
          municipalityType: municipalityType,
          spots: spots,
          checkIns: checkIns,
          tourists: tourists,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _spotsInMun {
    final mid = normalizeMunicipalityId(municipalityId);
    final aliases = municipalityIdsForQuery(mid).map((e) => e.toLowerCase()).toSet();
    final nameLower = municipalityName.trim().toLowerCase();
    return [
      for (final s in spots)
        if (_spotInMun(s, aliases, nameLower)) s,
    ]..sort(
        (a, b) => (a['name']?.toString() ?? '')
            .toLowerCase()
            .compareTo((b['name']?.toString() ?? '').toLowerCase()),
      );
  }

  bool _spotInMun(
    Map<String, dynamic> s,
    Set<String> aliases,
    String nameLower,
  ) {
    final id = normalizeMunicipalityId(s['municipalityId']?.toString());
    if (id.isNotEmpty && aliases.contains(id)) return true;
    final mun = (s['municipality'] ?? '').toString().trim().toLowerCase();
    if (nameLower.isNotEmpty &&
        (mun == nameLower || mun.contains(nameLower) || nameLower.contains(mun))) {
      return true;
    }
    final fromName = normalizeMunicipalityId(getMunicipalityIdFromName(mun));
    return fromName.isNotEmpty && aliases.contains(fromName);
  }

  ({int unique, int total}) _spotStats(Map<String, dynamic> spot) {
    final spotId = (spot['id'] ?? spot['spotId'] ?? '').toString().trim();
    final spotName = (spot['name'] ?? '').toString().trim().toLowerCase();
    final uids = <String>{};
    var total = 0;
    for (final c in checkIns) {
      final cid = (c['spotId'] ?? c['spot_id'] ?? '').toString().trim();
      final cname =
          (c['spot_name'] ?? c['spotName'] ?? '').toString().trim().toLowerCase();
      final match = (spotId.isNotEmpty && cid == spotId) ||
          (spotName.isNotEmpty && cname == spotName);
      if (!match) continue;
      total++;
      final uid = (c['userId'] ?? c['uid'] ?? c['touristId'] ?? '')
          .toString()
          .trim();
      if (uid.isNotEmpty) uids.add(uid);
    }
    return (unique: uids.length, total: total);
  }

  @override
  Widget build(BuildContext context) {
    final spotsList = _spotsInMun;
    final isCity = municipalityType.toLowerCase() == 'city';
    final accent = isCity
        ? GovernorDashboardTokens.primary
        : GovernorDashboardTokens.primaryDark;

    return Scaffold(
      backgroundColor: GovernorDashboardTokens.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: GovernorDashboardTokens.text,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back to municipalities',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              municipalityName,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            Text(
              'Spots & establishments · tap for full analytics',
              style: TextStyle(
                fontSize: 12,
                color: GovernorDashboardTokens.subtitle,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      body: StreamBuilder<List<EstablishmentRegistryEntry>>(
        stream: EstablishmentApprovalService.watchForMunicipality(
          municipalityId,
        ),
        builder: (context, snap) {
          final establishments = [
            for (final e in snap.data ?? const <EstablishmentRegistryEntry>[])
              if (e.isActive) e,
          ]..sort(
              (a, b) => a.businessName
                  .toLowerCase()
                  .compareTo(b.businessName.toLowerCase()),
            );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _SummaryBanner(
                accent: accent,
                spots: spotsList.length,
                establishments: establishments.length,
                municipalityType: municipalityType,
              ),
              const SizedBox(height: 18),
              Text(
                'Tourist spots',
                style: GovernorDashboardTokens.sectionTitle(),
              ),
              const SizedBox(height: 4),
              Text(
                'Attraction QR check-ins in $municipalityName',
                style: GovernorDashboardTokens.body(size: 12.5),
              ),
              const SizedBox(height: 10),
              if (spotsList.isEmpty)
                _EmptyCard(
                  message: 'No tourist spots registered for this LGU yet.',
                )
              else
                ...[
                  for (final s in spotsList) ...[
                    _PlaceCard(
                      title: (s['name'] ?? 'Spot').toString(),
                      badge: (s['category'] ?? 'Attraction').toString(),
                      icon: Icons.place_rounded,
                      accent: accent,
                      subtitle: () {
                        final st = _spotStats(s);
                        return '${st.unique} unique · ${st.total} check-ins';
                      }(),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => GovernorEntityAnalyticsScreen.spot(
                              municipalityId: municipalityId,
                              municipalityName: municipalityName,
                              spot: s,
                              checkIns: checkIns,
                              tourists: tourists,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              const SizedBox(height: 16),
              Text(
                'Establishments',
                style: GovernorDashboardTokens.sectionTitle(),
              ),
              const SizedBox(height: 4),
              Text(
                'Approved AEs · confirmed stays feed DAE analytics',
                style: GovernorDashboardTokens.body(size: 12.5),
              ),
              const SizedBox(height: 10),
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (establishments.isEmpty)
                _EmptyCard(
                  message:
                      'No active establishments in $municipalityName yet.',
                )
              else
                ...[
                  for (final e in establishments) ...[
                    _PlaceCard(
                      title: e.businessName,
                      badge: e.category.isEmpty ? 'Establishment' : e.category,
                      icon: Icons.hotel_rounded,
                      accent: GovernorDashboardTokens.primaryDark,
                      subtitle: e.barangay.trim().isEmpty
                          ? 'Active · open analytics'
                          : '${e.barangay} · Active',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                GovernorEntityAnalyticsScreen.establishment(
                              municipalityId: municipalityId,
                              municipalityName: municipalityName,
                              establishment: e,
                              tourists: tourists,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
            ],
          );
        },
      ),
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({
    required this.accent,
    required this.spots,
    required this.establishments,
    required this.municipalityType,
  });

  final Color accent;
  final int spots;
  final int establishments;
  final String municipalityType;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: 0.12),
            Colors.white,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _kpi('Spots', '$spots', Icons.place_outlined),
          ),
          Container(width: 1, height: 36, color: GovernorDashboardTokens.border),
          Expanded(
            child: _kpi(
              'Establishments',
              '$establishments',
              Icons.hotel_outlined,
            ),
          ),
          Container(width: 1, height: 36, color: GovernorDashboardTokens.border),
          Expanded(
            child: _kpi(
              'Type',
              municipalityType,
              Icons.location_city_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpi(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            color: GovernorDashboardTokens.text,
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: GovernorDashboardTokens.subtitle,
          ),
        ),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GovernorDashboardTokens.border),
      ),
      child: Text(
        message,
        style: GovernorDashboardTokens.body(size: 13),
      ),
    );
  }
}

class _PlaceCard extends StatefulWidget {
  const _PlaceCard({
    required this.title,
    required this.badge,
    required this.subtitle,
    required this.icon,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String badge;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback onTap;

  @override
  State<_PlaceCard> createState() => _PlaceCardState();
}

class _PlaceCardState extends State<_PlaceCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(18),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  widget.accent.withValues(alpha: 0.04),
                ],
              ),
              border: Border.all(
                color: _hover
                    ? widget.accent.withValues(alpha: 0.45)
                    : GovernorDashboardTokens.border,
              ),
              boxShadow: [
                BoxShadow(
                  color: widget.accent.withValues(alpha: _hover ? 0.14 : 0.06),
                  blurRadius: _hover ? 20 : 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          widget.accent,
                          widget.accent.withValues(alpha: 0.75),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(widget.icon, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: GovernorDashboardTokens.text,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: widget.accent,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                widget.badge,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.subtitle,
                                style: const TextStyle(
                                  color: GovernorDashboardTokens.subtitle,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: widget.accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: widget.accent,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
