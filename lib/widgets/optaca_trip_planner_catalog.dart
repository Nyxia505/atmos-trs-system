import 'package:atmos_trs_system/config/supabase_storage_config.dart';
import 'package:atmos_trs_system/config/vr_tour_config.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/data/tourist_spot_image_catalog.dart';
import 'package:atmos_trs_system/features/governor/theme/governor_dashboard_tokens.dart';
import 'package:atmos_trs_system/models/tourist_destination_detail.dart';
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/screens/tourist_destination_detail_screen.dart';
import 'package:atmos_trs_system/screens/vr_webview_screen.dart';
import 'package:atmos_trs_system/services/provincial_tourism_service.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:atmos_trs_system/widgets/spot_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// OPTACA Trip Planner — Destinations + Virtual Tours (view-only).
///
/// Reads the same LGU-managed `tourist_spots` collection. No create / update /
/// delete controls are exposed; Firestore rules also block provincial writes.
class OptacaTripPlannerCatalog extends StatefulWidget {
  const OptacaTripPlannerCatalog({
    super.key,
    this.initialTabIndex = 0,
    this.showSectionTabs = true,
  });

  /// 0 = Destinations, 1 = Virtual Tour.
  final int initialTabIndex;

  /// When false, only Destinations are shown (for the top-level Destinations nav).
  final bool showSectionTabs;

  @override
  State<OptacaTripPlannerCatalog> createState() =>
      _OptacaTripPlannerCatalogState();
}

class _OptacaTripPlannerCatalogState extends State<OptacaTripPlannerCatalog> {
  late int _section;

  @override
  void initState() {
    super.initState();
    _section = widget.showSectionTabs ? widget.initialTabIndex.clamp(0, 1) : 0;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('tourist_spots').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _errorPane(
            'Could not load destinations.',
            snap.error.toString(),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final spots = snap.data!.docs
            .map((d) => <String, dynamic>{'id': d.id, ...d.data()})
            .where(_isProvinceSpot)
            .toList()
          ..sort((a, b) => (a['name']?.toString() ?? '')
              .toLowerCase()
              .compareTo((b['name']?.toString() ?? '').toLowerCase()));
        final vrSpots = mergeKnownVrDestinations(spots);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _header(),
            ),
            if (widget.showSectionTabs) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _sectionSwitcher(spots, vrSpots),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: widget.showSectionTabs && _section == 1
                  ? _OptacaVirtualToursPanel(spots: vrSpots)
                  : _OptacaDestinationsPanel(spots: spots),
            ),
          ],
        );
      },
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.showSectionTabs ? 'Trip Planner' : 'Destinations',
                style: GovernorDashboardTokens.heading(size: 20),
              ),
              const SizedBox(height: 4),
              Text(
                widget.showSectionTabs
                    ? 'Province-wide destinations and virtual tours managed by each LGU.'
                    : 'All LGU-registered tourist destinations across Misamis Occidental.',
                style: GovernorDashboardTokens.body(size: 12.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        const _ViewOnlyBadge(),
      ],
    );
  }

  Widget _sectionSwitcher(
    List<Map<String, dynamic>> spots,
    List<Map<String, dynamic>> vrSpots,
  ) {
    final destCount = spots.length;
    final vrCount = vrSpots.length;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GovernorDashboardTokens.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _sectionChip(
              label: 'Destinations',
              count: destCount,
              icon: Icons.place_rounded,
              selected: _section == 0,
              onTap: () => setState(() => _section = 0),
            ),
          ),
          Expanded(
            child: _sectionChip(
              label: 'Virtual Tour',
              count: vrCount,
              icon: Icons.vrpano_rounded,
              selected: _section == 1,
              onTap: () => setState(() => _section = 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionChip({
    required String label,
    required int count,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final accent = GovernorDashboardTokens.primary;
    return Material(
      color: selected ? accent : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : GovernorDashboardTokens.subtitle,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: GovernorDashboardTokens.sectionTitle(
                    size: 13,
                    color: selected ? Colors.white : GovernorDashboardTokens.text,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.22)
                      : GovernorDashboardTokens.mutedSurface,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$count',
                  style: GovernorDashboardTokens.sectionTitle(
                    size: 11,
                    color: selected
                        ? Colors.white
                        : GovernorDashboardTokens.subtitle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorPane(String title, String detail) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 40, color: GovernorDashboardTokens.subtitle),
            const SizedBox(height: 12),
            Text(title, style: GovernorDashboardTokens.sectionTitle()),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: GovernorDashboardTokens.body(size: 12),
            ),
          ],
        ),
      ),
    );
  }
}

bool _isProvinceSpot(Map<String, dynamic> s) {
  final mid = ProvincialTourismService.municipalityIdOf(s);
  return mid.isNotEmpty && isMisamisOccidentalMunicipalityId(mid);
}

/// True when the spot has a usable VR URL (Firestore link or known Clear Pano).
bool spotHasVrContent(Map<String, dynamic> s) {
  final resolved = resolveVrTourUrl(
    vrLink: _rawVrLink(s).isEmpty ? null : _rawVrLink(s),
    spotId: s['id']?.toString(),
    spotName: s['name']?.toString(),
  );
  return resolved != null && hostedVrUrlForLaunch(resolved) != null;
}

String _rawVrLink(Map<String, dynamic> s) {
  for (final key in const [
    'vr_link',
    'vrLink',
    'vrTourUrl',
    'vrUrl',
    'vr_url',
  ]) {
    final v = s[key]?.toString().trim() ?? '';
    if (v.isNotEmpty) return v;
  }
  return '';
}

String? _resolvedVrUrl(Map<String, dynamic> s) {
  final link = _rawVrLink(s);
  return resolveVrTourUrl(
    vrLink: link.isEmpty ? null : link,
    spotId: s['id']?.toString(),
    spotName: s['name']?.toString(),
  );
}

String _imageOf(Map<String, dynamic> s) {
  final raw = TouristSpotFirestore.readImageUrl(s);
  return TouristSpotImageCatalog.displayUrl(
    preferred: raw,
    spotId: s['id']?.toString() ?? '',
    spotName: s['name']?.toString() ?? '',
    municipalityId: ProvincialTourismService.municipalityIdOf(s),
    category: s['category']?.toString() ?? '',
  );
}

class _ViewOnlyBadge extends StatelessWidget {
  const _ViewOnlyBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0EA5E9).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: const Color(0xFF0EA5E9).withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_outlined, size: 14, color: Color(0xFF0284C7)),
          const SizedBox(width: 5),
          Text(
            'View Only',
            style: GovernorDashboardTokens.sectionTitle(
              size: 11.5,
              color: const Color(0xFF0284C7),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Destinations (view-only) ───────────────────────────────────────────────

class _OptacaDestinationsPanel extends StatefulWidget {
  const _OptacaDestinationsPanel({required this.spots});

  final List<Map<String, dynamic>> spots;

  @override
  State<_OptacaDestinationsPanel> createState() =>
      _OptacaDestinationsPanelState();
}

class _OptacaDestinationsPanelState extends State<_OptacaDestinationsPanel> {
  final _searchController = TextEditingController();
  String _search = '';
  String _municipality = 'All';
  String _category = 'All';

  static const _categories = [
    'All',
    'Beach',
    'Falls',
    'Historical',
    'Mountain',
    'Resort',
    'Church',
    'Park',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    return widget.spots.where((s) {
      final name = (s['name']?.toString() ?? '').toLowerCase();
      final desc = (s['description']?.toString() ?? '').toLowerCase();
      final mid = ProvincialTourismService.municipalityIdOf(s);
      final mname = ProvincialTourismService.municipalityNameOf(mid);
      final cat = (s['category']?.toString() ?? '').toLowerCase();
      if (q.isNotEmpty &&
          !name.contains(q) &&
          !desc.contains(q) &&
          !mname.toLowerCase().contains(q) &&
          !cat.contains(q)) {
        return false;
      }
      if (_municipality != 'All' && mname != _municipality) return false;
      if (_category != 'All' && !cat.contains(_category.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
  }

  Map<String, int> get _countsByMunicipality {
    final counts = <String, int>{};
    for (final m in getMisamisOccidentalMunicipalities()) {
      counts[m.name] = 0;
    }
    for (final s in widget.spots) {
      final mid = ProvincialTourismService.municipalityIdOf(s);
      final name = ProvincialTourismService.municipalityNameOf(mid);
      counts[name] = (counts[name] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    final munis = [
      'All',
      ...getMisamisOccidentalMunicipalities().map((m) => m.name),
    ];
    final filtered = _filtered;
    final counts = _countsByMunicipality;
    final wide = MediaQuery.sizeOf(context).width >= 960;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _filterBar(munis),
        const SizedBox(height: 12),
        _muniCountStrip(counts),
        const SizedBox(height: 14),
        Text(
          '${filtered.length} destination${filtered.length == 1 ? '' : 's'}'
          '${_municipality == 'All' && _category == 'All' && _search.isEmpty ? ' across ${getMisamisOccidentalMunicipalities().length} LGUs' : ''}',
          style: GovernorDashboardTokens.body(size: 12.5),
        ),
        const SizedBox(height: 10),
        if (filtered.isEmpty)
          _emptyState(
            icon: Icons.travel_explore_rounded,
            title: 'No destinations match',
            message: 'Try another municipality, category, or search term.',
          )
        else if (wide)
          _grid(filtered)
        else
          ...filtered.map(_destinationCard),
      ],
    );
  }

  Widget _filterBar(List<String> munis) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GovernorDashboardTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _search = v),
            decoration: InputDecoration(
              hintText: 'Search destinations',
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _search = '');
                      },
                    ),
              filled: true,
              fillColor: GovernorDashboardTokens.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: GovernorDashboardTokens.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: GovernorDashboardTokens.border),
              ),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final muniField = DropdownButtonFormField<String>(
                initialValue: _municipality,
                isExpanded: true,
                decoration: _dropdownDecoration('Municipality'),
                items: [
                  for (final m in munis)
                    DropdownMenuItem(value: m, child: Text(m)),
                ],
                onChanged: (v) =>
                    setState(() => _municipality = v ?? 'All'),
              );
              final catField = DropdownButtonFormField<String>(
                initialValue: _category,
                isExpanded: true,
                decoration: _dropdownDecoration('Category'),
                items: [
                  for (final cat in _categories)
                    DropdownMenuItem(value: cat, child: Text(cat)),
                ],
                onChanged: (v) => setState(() => _category = v ?? 'All'),
              );
              if (c.maxWidth < 640) {
                return Column(
                  children: [
                    muniField,
                    const SizedBox(height: 10),
                    catField,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: muniField),
                  const SizedBox(width: 10),
                  Expanded(child: catField),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  InputDecoration _dropdownDecoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: GovernorDashboardTokens.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: GovernorDashboardTokens.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: GovernorDashboardTokens.border),
      ),
    );
  }

  Widget _muniCountStrip(Map<String, int> counts) {
    final entries = counts.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final e = entries[i];
          final selected = _municipality == e.key;
          return FilterChip(
            selected: selected,
            label: Text('${e.key} (${e.value})'),
            onSelected: (_) => setState(() {
              _municipality = selected ? 'All' : e.key;
            }),
            selectedColor: GovernorDashboardTokens.primary.withValues(alpha: 0.15),
            checkmarkColor: GovernorDashboardTokens.primary,
            side: BorderSide(
              color: selected
                  ? GovernorDashboardTokens.primary
                  : GovernorDashboardTokens.border,
            ),
          );
        },
      ),
    );
  }

  Widget _grid(List<Map<String, dynamic>> rows) {
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 1280 ? 3 : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rows.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.35,
          ),
          itemBuilder: (context, i) => _destinationCard(rows[i]),
        );
      },
    );
  }

  Widget _destinationCard(Map<String, dynamic> s) {
    final name = s['name']?.toString() ?? 'Destination';
    final category = s['category']?.toString() ?? '';
    final mid = ProvincialTourismService.municipalityIdOf(s);
    final muni = ProvincialTourismService.municipalityNameOf(mid);
    final desc = s['description']?.toString() ?? '';
    final hasVr = spotHasVrContent(s);
    final image = _imageOf(s);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openDestinationDetail(context, s),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: GovernorDashboardTokens.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  height: 110,
                  child: SpotImage(
                    imageUrl: image,
                    spotId: s['id']?.toString(),
                    spotName: name,
                    municipalityId: mid,
                    category: category,
                    fit: BoxFit.cover,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GovernorDashboardTokens.sectionTitle(
                                  size: 14,
                                ),
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              color: GovernorDashboardTokens.subtitle,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 13,
                              color: GovernorDashboardTokens.subtitle,
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                muni,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GovernorDashboardTokens.body(size: 12),
                              ),
                            ),
                          ],
                        ),
                        if (desc.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GovernorDashboardTokens.body(size: 12),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (category.isNotEmpty)
                              _chip(category, GovernorDashboardTokens.primary),
                            if (hasVr)
                              _chip(
                                '360° VR',
                                const Color(0xFF8B5CF6),
                                icon: Icons.vrpano_rounded,
                              ),
                          ],
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
    );
  }
}

// ─── Virtual Tours (view-only) ──────────────────────────────────────────────

class _OptacaVirtualToursPanel extends StatefulWidget {
  const _OptacaVirtualToursPanel({required this.spots});

  final List<Map<String, dynamic>> spots;

  @override
  State<_OptacaVirtualToursPanel> createState() =>
      _OptacaVirtualToursPanelState();
}

class _OptacaVirtualToursPanelState extends State<_OptacaVirtualToursPanel> {
  final _searchController = TextEditingController();
  String _search = '';
  String _municipality = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _withVr => widget.spots;

  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    return _withVr.where((s) {
      final name = (s['name']?.toString() ?? '').toLowerCase();
      final mid = ProvincialTourismService.municipalityIdOf(s);
      final mname = ProvincialTourismService.municipalityNameOf(mid);
      if (q.isNotEmpty &&
          !name.contains(q) &&
          !mname.toLowerCase().contains(q)) {
        return false;
      }
      if (_municipality != 'All' && mname != _municipality) return false;
      return true;
    }).toList();
  }

  Map<String, int> get _countsByMunicipality {
    final counts = <String, int>{};
    for (final m in getMisamisOccidentalMunicipalities()) {
      counts[m.name] = 0;
    }
    for (final s in _withVr) {
      final mid = ProvincialTourismService.municipalityIdOf(s);
      final name = ProvincialTourismService.municipalityNameOf(mid);
      counts[name] = (counts[name] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Widget build(BuildContext context) {
    final munis = [
      'All',
      ...getMisamisOccidentalMunicipalities().map((m) => m.name),
    ];
    final filtered = _filtered;
    final counts = _countsByMunicipality;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: GovernorDashboardTokens.border),
          ),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: 'Search virtual tours',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: GovernorDashboardTokens.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: GovernorDashboardTokens.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: GovernorDashboardTokens.border),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _municipality,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Municipality',
                  isDense: true,
                  filled: true,
                  fillColor: GovernorDashboardTokens.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: GovernorDashboardTokens.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: GovernorDashboardTokens.border),
                  ),
                ),
                items: [
                  for (final m in munis)
                    DropdownMenuItem(value: m, child: Text(m)),
                ],
                onChanged: (v) =>
                    setState(() => _municipality = v ?? 'All'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _muniCountStrip(counts),
        const SizedBox(height: 14),
        Text(
          '${filtered.length} virtual tour${filtered.length == 1 ? '' : 's'} available',
          style: GovernorDashboardTokens.body(size: 12.5),
        ),
        const SizedBox(height: 10),
        if (_withVr.isEmpty)
          _emptyState(
            icon: Icons.vrpano_outlined,
            title: 'No virtual tours yet',
            message:
                'When an LGU links a 360° tour to a destination, it will appear here automatically.',
          )
        else if (filtered.isEmpty)
          _emptyState(
            icon: Icons.filter_alt_off_outlined,
            title: 'No tours match',
            message: 'Try another municipality or search term.',
          )
        else
          ...filtered.map(_tourCard),
      ],
    );
  }

  Widget _muniCountStrip(Map<String, int> counts) {
    final entries = counts.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final e = entries[i];
          final selected = _municipality == e.key;
          return FilterChip(
            selected: selected,
            label: Text('${e.key} (${e.value})'),
            onSelected: (_) => setState(() {
              _municipality = selected ? 'All' : e.key;
            }),
            selectedColor:
                const Color(0xFF8B5CF6).withValues(alpha: 0.12),
            checkmarkColor: const Color(0xFF7C3AED),
            side: BorderSide(
              color: selected
                  ? const Color(0xFF8B5CF6)
                  : GovernorDashboardTokens.border,
            ),
          );
        },
      ),
    );
  }

  Widget _tourCard(Map<String, dynamic> s) {
    final name = s['name']?.toString() ?? 'Destination';
    final mid = ProvincialTourismService.municipalityIdOf(s);
    final muni = ProvincialTourismService.municipalityNameOf(mid);
    final category = s['category']?.toString() ?? '';
    final image = _imageOf(s);
    final url = _resolvedVrUrl(s);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: GovernorDashboardTokens.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 140,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SpotImage(
                    imageUrl: image,
                    spotId: s['id']?.toString(),
                    spotName: name,
                    municipalityId: mid,
                    category: category,
                    fit: BoxFit.cover,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.05),
                          Colors.black.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 10,
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.location_on_outlined,
                        size: 14,
                        color: GovernorDashboardTokens.subtitle,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          muni,
                          style: GovernorDashboardTokens.body(size: 12.5),
                        ),
                      ),
                      _chip(
                        'View Only',
                        const Color(0xFF0EA5E9),
                        icon: Icons.visibility_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (url == null)
                    _emptyState(
                      icon: Icons.link_off_rounded,
                      title: 'No tour content',
                      message:
                          'This destination is marked for VR but has no usable tour URL.',
                      compact: true,
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _openDestinationDetail(context, s),
                            icon: const Icon(Icons.info_outline_rounded, size: 18),
                            label: const Text('Details'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => openVrForTouristSpot(
                              context,
                              spotId: s['id']?.toString() ?? '',
                              spotName: name,
                              vrLink: url,
                              imageUrl: SupabaseStorageConfig.resolve(image),
                              allowWeb: true,
                            ),
                            icon: const Icon(Icons.vrpano_rounded, size: 18),
                            label: const Text('Preview'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _chip(String label, Color color, {IconData? icon}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(99),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          style: GovernorDashboardTokens.sectionTitle(size: 11, color: color),
        ),
      ],
    ),
  );
}

Widget _emptyState({
  required IconData icon,
  required String title,
  required String message,
  bool compact = false,
}) {
  return Padding(
    padding: EdgeInsets.symmetric(vertical: compact ? 8 : 28),
    child: Column(
      children: [
        Container(
          width: compact ? 40 : 52,
          height: compact ? 40 : 52,
          decoration: BoxDecoration(
            color: GovernorDashboardTokens.softOrange,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: GovernorDashboardTokens.primaryDark),
        ),
        SizedBox(height: compact ? 8 : 10),
        Text(title, style: GovernorDashboardTokens.sectionTitle()),
        const SizedBox(height: 4),
        Text(
          message,
          textAlign: TextAlign.center,
          style: GovernorDashboardTokens.body(size: 12.5),
        ),
      ],
    ),
  );
}

void _openDestinationDetail(BuildContext context, Map<String, dynamic> s) {
  final id = s['id']?.toString() ?? '';
  final fs = TouristSpotFirestore.fromFirestore(s, id);
  final detail = TouristDestinationDetail.fromFirestoreSpot(fs);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => TouristDestinationDetailScreen(
        destination: detail,
        firestoreSpot: fs,
      ),
    ),
  );
}
