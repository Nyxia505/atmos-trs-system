import 'package:flutter/material.dart';

import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:atmos_trs_system/screens/governor_entity_analytics_screen.dart';
import 'package:atmos_trs_system/services/establishment_approval_service.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/widgets/spot_image.dart';

/// Governor L2: spots + establishments for one municipality (replaces city list).
class GovernorMunicipalityPlacesScreen extends StatefulWidget {
  const GovernorMunicipalityPlacesScreen({
    super.key,
    required this.municipalityId,
    required this.municipalityName,
    required this.municipalityType,
    required this.spots,
    required this.checkIns,
    required this.tourists,
    this.uniqueVisitors = 0,
    this.embedded = false,
    this.onOpenSpot,
    this.onOpenEstablishment,
  });

  final String municipalityId;
  final String municipalityName;
  final String municipalityType;
  final List<Map<String, dynamic>> spots;
  final List<Map<String, dynamic>> checkIns;
  final List<Map<String, dynamic>> tourists;
  final int uniqueVisitors;

  /// Drawn inside the Governor dashboard (sidebar and header stay visible).
  final bool embedded;
  final void Function(Map<String, dynamic> spot)? onOpenSpot;
  final void Function(EstablishmentRegistryEntry establishment)?
      onOpenEstablishment;

  @override
  State<GovernorMunicipalityPlacesScreen> createState() =>
      _GovernorMunicipalityPlacesScreenState();

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

}

class _GovernorMunicipalityPlacesScreenState
    extends State<GovernorMunicipalityPlacesScreen> {
  String _query = '';
  String _category = 'All';

  List<Map<String, dynamic>> get _spotsInMun {
    final mid = normalizeMunicipalityId(widget.municipalityId);
    final aliases = municipalityIdsForQuery(mid).map((e) => e.toLowerCase()).toSet();
    final nameLower = widget.municipalityName.trim().toLowerCase();
    return [
      for (final s in widget.spots)
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
    for (final c in widget.checkIns) {
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
    final isCity = widget.municipalityType.toLowerCase() == 'city';
    final accent = isCity
        ? GovernorDashboardTokens.primary
        : GovernorDashboardTokens.primaryDark;

    final body = StreamBuilder<List<EstablishmentRegistryEntry>>(
        stream: EstablishmentApprovalService.watchForMunicipality(
          widget.municipalityId,
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

          final categories = <String>{
            for (final s in spotsList)
              (s['category'] ?? 'Attraction').toString().trim(),
            for (final e in establishments)
              e.category.trim().isEmpty ? 'Establishment' : e.category.trim(),
          }.toList()
            ..sort();
          final spotsShown = [
            for (final s in spotsList)
              if (_matches(
                (s['name'] ?? '').toString(),
                (s['category'] ?? 'Attraction').toString(),
              ))
                s,
          ];
          final establishmentsShown = [
            for (final e in establishments)
              if (_matches(
                e.businessName,
                e.category.isEmpty ? 'Establishment' : e.category,
              ))
                e,
          ];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _SummaryBanner(
                accent: accent,
                spots: spotsList.length,
                establishments: establishments.length,
                uniqueVisitors: widget.uniqueVisitors,
              ),
              const SizedBox(height: 14),
              TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search spots or establishments',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE7E5E4)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final label in ['All', ...categories])
                    ChoiceChip(
                      label: Text(label),
                      selected: _category == label,
                      onSelected: (_) => setState(() => _category = label),
                      selectedColor: const Color(0xFFFFEDD5),
                      labelStyle: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _category == label
                            ? const Color(0xFF9A3412)
                            : const Color(0xFF1C1917),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                'Tourist spots',
                style: GovernorDashboardTokens.sectionTitle(),
              ),
              const SizedBox(height: 4),
              Text(
                'Attraction QR check-ins in ${widget.municipalityName}',
                style: const TextStyle(
                  color: Color(0xFF44403C),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              if (spotsShown.isEmpty)
                _EmptyCard(
                  message: spotsList.isEmpty
                      ? 'No tourist spots registered for this LGU yet.'
                      : 'No tourist spots match this search.',
                )
              else
                ...[
                  for (final s in spotsShown) ...[
                    _PlaceCard(
                      title: (s['name'] ?? 'Spot').toString(),
                      badge: (s['category'] ?? 'Attraction').toString(),
                      icon: Icons.place_rounded,
                      accent: accent,
                      thumbnail: SpotImage(
                        imageUrl: (s['image'] ?? s['imageUrl'] ?? s['photoUrl'])
                            ?.toString(),
                        spotId: (s['id'] ?? s['spotId'])?.toString(),
                        municipalityId: widget.municipalityId,
                        spotName: (s['name'] ?? '').toString(),
                        category: (s['category'] ?? '').toString(),
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(10),
                        placeholderIcon: Icons.place_rounded,
                      ),
                      subtitle: () {
                        final st = _spotStats(s);
                        return '${st.unique} unique · ${st.total} check-ins';
                      }(),
                      onTap: () => _openSpot(s),
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
              const Text(
                'Approved AEs · monthly DOT registers feed DAE analytics',
                style: TextStyle(
                  color: Color(0xFF44403C),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 10),
              if (snap.connectionState == ConnectionState.waiting &&
                  !snap.hasData)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (establishmentsShown.isEmpty)
                _EmptyCard(
                  message: establishments.isEmpty
                      ? 'No active establishments in ${widget.municipalityName} yet.'
                      : 'No establishments match this search.',
                )
              else
                ...[
                  for (final e in establishmentsShown) ...[
                    _PlaceCard(
                      title: e.businessName,
                      badge: e.category.isEmpty ? 'Establishment' : e.category,
                      icon: Icons.hotel_rounded,
                      accent: GovernorDashboardTokens.primaryDark,
                      thumbnail: _EstablishmentThumb(
                        accent: GovernorDashboardTokens.primaryDark,
                      ),
                      subtitle: e.barangay.trim().isEmpty
                          ? 'Active · open analytics'
                          : '${e.barangay} · Active',
                      onTap: () => _openEstablishment(e),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
            ],
          );
        },
      );

    if (widget.embedded) return body;

    return Scaffold(
      backgroundColor: GovernorDashboardTokens.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: const Color(0xFF1C1917),
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: 16,
        title: _ReadableBackButton(
          label: 'Back to municipalities',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: body,
    );
  }

  bool _matches(String name, String category) {
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty &&
        !name.toLowerCase().contains(q) &&
        !category.toLowerCase().contains(q)) {
      return false;
    }
    if (_category != 'All' &&
        category.toLowerCase() != _category.toLowerCase()) {
      return false;
    }
    return true;
  }

  void _openSpot(Map<String, dynamic> spot) {
    if (widget.onOpenSpot != null) {
      widget.onOpenSpot!(spot);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GovernorEntityAnalyticsScreen.spot(
          municipalityId: widget.municipalityId,
          municipalityName: widget.municipalityName,
          spot: spot,
          checkIns: widget.checkIns,
          tourists: widget.tourists,
        ),
      ),
    );
  }

  void _openEstablishment(EstablishmentRegistryEntry establishment) {
    if (widget.onOpenEstablishment != null) {
      widget.onOpenEstablishment!(establishment);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GovernorEntityAnalyticsScreen.establishment(
          municipalityId: widget.municipalityId,
          municipalityName: widget.municipalityName,
          establishment: establishment,
          tourists: widget.tourists,
        ),
      ),
    );
  }
}

class _ReadableBackButton extends StatelessWidget {
  const _ReadableBackButton({
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF9A3412),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EstablishmentThumb extends StatelessWidget {
  const _EstablishmentThumb({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE7E5E4)),
      ),
      child: Icon(Icons.hotel_rounded, color: accent, size: 26),
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({
    required this.accent,
    required this.spots,
    required this.establishments,
    required this.uniqueVisitors,
  });

  final Color accent;
  final int spots;
  final int establishments;
  final int uniqueVisitors;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7E5E4)),
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
              'Unique visitors',
              '$uniqueVisitors',
              Icons.people_outline,
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
            fontSize: 20,
            color: Color(0xFF1C1917),
            height: 1.1,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF44403C),
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
    required this.thumbnail,
    required this.onTap,
  });

  final String title;
  final String badge;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final Widget thumbnail;
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _hover
                    ? const Color(0xFFD6D3D1)
                    : const Color(0xFFE7E5E4),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Row(
                children: [
                  Container(width: 5, color: widget.accent),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          widget.thumbnail,
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                    color: Color(0xFF1C1917),
                                    height: 1.25,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  widget.badge,
                                  style: TextStyle(
                                    color: widget.accent,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.subtitle,
                                  style: const TextStyle(
                                    color: Color(0xFF44403C),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: widget.onTap,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF9A3412),
                              backgroundColor: const Color(0xFFFFF7ED),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            child: const Text('View Analytics'),
                          ),
                        ],
                      ),
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
