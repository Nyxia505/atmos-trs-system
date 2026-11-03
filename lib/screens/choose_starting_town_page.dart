import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/app_theme_controller.dart';
import 'package:atmos_trs_system/data/landing_lgu_destinations.dart';
import 'package:atmos_trs_system/widgets/spot_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:trip_plan/data.dart' as trip;
import 'package:trip_plan/trip_planner_utils.dart'
    show matchMunicipalityByLocalityHint;

/// Full-screen starting-town picker with LGU photos and grouped cities.
class ChooseStartingTownPage extends StatefulWidget {
  const ChooseStartingTownPage({super.key});

  @override
  State<ChooseStartingTownPage> createState() => _ChooseStartingTownPageState();
}

enum _TownFilter { all, cities, municipalities }

class _TownOption {
  const _TownOption({required this.municipality, required this.destination});

  final trip.Municipality municipality;
  final Map<String, String> destination;

  String get name =>
      destination['name'] ??
      (municipality.shortName.isNotEmpty
          ? municipality.shortName
          : municipality.name);

  String get category => destination['category'] ?? 'Municipality';
  String get description => destination['description'] ?? '';
  String get imageUrl => destination['image'] ?? '';
  String? get municipalityId => destination['municipalityId'];

  bool get isCity => category.toLowerCase().contains('city');
  bool get isCapital => category.toLowerCase().contains('capital');
}

class _ChooseStartingTownPageState extends State<ChooseStartingTownPage> {
  static const double _avatarSize = 64;

  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  late final List<_TownOption> _towns;
  _TownFilter _filter = _TownFilter.all;
  String? _pressedName;

  @override
  void initState() {
    super.initState();
    _towns = _buildTownOptions();
    _searchFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<_TownOption> _buildTownOptions() {
    final used = <String>{};
    final options = <_TownOption>[];

    for (final dest in buildLandingLguDestinations()) {
      final match =
          matchMunicipalityByLocalityHint(dest['name'] ?? '') ??
          matchMunicipalityByLocalityHint(dest['municipalityId'] ?? '');
      if (match == null) continue;
      used.add(match.name);
      options.add(_TownOption(municipality: match, destination: dest));
    }

    for (final m in trip.municipalities) {
      if (used.contains(m.name)) continue;
      options.add(
        _TownOption(
          municipality: m,
          destination: {
            'name': m.shortName.isNotEmpty ? m.shortName : m.name,
            'category': 'Municipality',
            'description': '',
            'image': '',
            'municipalityId': '',
          },
        ),
      );
    }
    return options;
  }

  List<_TownOption> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return [
      for (final t in _towns)
        if ((q.isEmpty || _haystack(t).contains(q)) &&
            (_filter == _TownFilter.all ||
                (_filter == _TownFilter.cities && t.isCity) ||
                (_filter == _TownFilter.municipalities && !t.isCity)))
          t,
    ];
  }

  String _haystack(_TownOption t) {
    return [
      t.name,
      t.category,
      t.description,
      t.municipalityId,
      t.municipality.name,
      t.municipality.shortName,
    ].whereType<String>().join(' ').toLowerCase();
  }

  void _select(_TownOption town) {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(town.municipality);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        final filtered = _filtered;
        final query = _search.text.trim();
        final cities = filtered.where((t) => t.isCity).toList();
        final municipalities = filtered.where((t) => !t.isCity).toList();
        final grouped = query.isEmpty && _filter == _TownFilter.all;

        return Scaffold(
          backgroundColor: AppTheme.pageBackground,
          body: Column(
            children: [
              _header(filtered.length),
              Expanded(
                child: filtered.isEmpty
                    ? _emptyState(query)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        children: [
                          if (grouped) ...[
                            if (cities.isNotEmpty) ...[
                              _sectionLabel('Cities', cities.length),
                              const SizedBox(height: 10),
                              for (var i = 0; i < cities.length; i++) ...[
                                _townCard(cities[i]),
                                if (i < cities.length - 1)
                                  const SizedBox(height: 10),
                              ],
                              const SizedBox(height: 22),
                            ],
                            if (municipalities.isNotEmpty) ...[
                              _sectionLabel(
                                'Municipalities',
                                municipalities.length,
                              ),
                              const SizedBox(height: 10),
                              for (var i = 0; i < municipalities.length; i++) ...[
                                _townCard(municipalities[i]),
                                if (i < municipalities.length - 1)
                                  const SizedBox(height: 10),
                              ],
                            ],
                          ] else
                            for (var i = 0; i < filtered.length; i++) ...[
                              _townCard(filtered[i]),
                              if (i < filtered.length - 1)
                                const SizedBox(height: 10),
                            ],
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _header(int resultCount) {
    final focused = _searchFocus.hasFocus;
    return Material(
      color: AppTheme.cardBackground,
      elevation: 0,
      child: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                    color: AppTheme.textPrimary,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Start your trip',
                          style: GoogleFonts.montserrat(
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            height: 1.15,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Choose a starting town',
                          style: GoogleFonts.montserrat(
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                            color: AppTheme.unselectedMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 50,
              padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
              decoration: BoxDecoration(
                color: AppTheme.surfaceMuted,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: focused ? AppTheme.brandOrange : AppTheme.border,
                  width: focused ? 1.6 : 1,
                ),
                boxShadow: focused
                    ? [
                        BoxShadow(
                          color: AppTheme.brandOrange.withValues(alpha: 0.16),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search_rounded,
                    color: focused
                        ? AppTheme.brandOrange
                        : AppTheme.unselectedMuted,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _search,
                      focusNode: _searchFocus,
                      cursorColor: AppTheme.brandOrange,
                      onChanged: (_) => setState(() {}),
                      style: GoogleFonts.montserrat(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Search Misamis Occidental…',
                        hintStyle: GoogleFonts.montserrat(
                          color: AppTheme.unselectedMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  if (_search.text.isNotEmpty)
                    IconButton(
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                      icon: Icon(
                        Icons.cancel_rounded,
                        size: 18,
                        color: AppTheme.unselectedMuted,
                      ),
                      tooltip: 'Clear search',
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                _filterChip(_TownFilter.all, 'All', _towns.length),
                const SizedBox(width: 8),
                _filterChip(
                  _TownFilter.cities,
                  'Cities',
                  _towns.where((t) => t.isCity).length,
                ),
                const SizedBox(width: 8),
                _filterChip(
                  _TownFilter.municipalities,
                  'Towns',
                  _towns.where((t) => !t.isCity).length,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                resultCount == 1
                    ? '1 place'
                    : '$resultCount places in Misamis Occidental',
                style: GoogleFonts.montserrat(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.unselectedMuted,
                ),
              ),
            ),
          ),
          Container(height: 1, color: AppTheme.border),
        ],
      ),
    );
  }

  Widget _filterChip(_TownFilter value, String label, int count) {
    final selected = _filter == value;
    return Expanded(
      child: Material(
        color: selected ? AppTheme.brandOrange : AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _filter = value);
          },
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '$label  $count',
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : AppTheme.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String title, int count) {
    return Row(
      children: [
        Text(
          title.toUpperCase(),
          style: GoogleFonts.montserrat(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: AppTheme.unselectedMuted,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.surfaceMuted,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: GoogleFonts.montserrat(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _emptyState(String query) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppTheme.brandOrange.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.explore_off_rounded,
                size: 34,
                color: AppTheme.brandOrange,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              query.isEmpty ? 'No towns here' : 'No towns match “$query”',
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                color: AppTheme.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try another name, or show all towns.',
              textAlign: TextAlign.center,
              style: GoogleFonts.montserrat(
                color: AppTheme.unselectedMuted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                _search.clear();
                setState(() => _filter = _TownFilter.all);
              },
              child: const Text('Show all towns'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _townCard(_TownOption town) {
    final selected = _pressedName == town.name;
    return Material(
      color: selected
          ? AppTheme.brandOrange.withValues(alpha: 0.08)
          : AppTheme.cardBackground,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () => _select(town),
        onHighlightChanged: (down) {
          setState(() => _pressedName = down ? town.name : null);
        },
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? AppTheme.brandOrange.withValues(alpha: 0.45)
                  : AppTheme.border,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: AppTheme.isDark ? 0.18 : 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(
              children: [
                _townAvatar(town),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              town.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.montserrat(
                                color: AppTheme.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                          ),
                          if (town.isCapital) ...[
                            const SizedBox(width: 8),
                            _capitalBadge(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        town.description.trim().isEmpty
                            ? town.category
                            : '${town.category} · ${town.description}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.montserrat(
                          color: AppTheme.unselectedMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.unselectedMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _capitalBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.brandOrange.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Capital',
        style: GoogleFonts.montserrat(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: AppTheme.brandOrangeDark,
        ),
      ),
    );
  }

  Widget _townAvatar(_TownOption town) {
    return Container(
      width: _avatarSize,
      height: _avatarSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: town.isCity
              ? AppTheme.brandOrange.withValues(alpha: 0.7)
              : const Color(0xFFF4D5C2),
          width: 2.4,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.brandOrange.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipOval(
        child: SpotImage(
          imageUrl: town.imageUrl.isEmpty ? null : town.imageUrl,
          municipalityId: town.municipalityId,
          spotName: town.name,
          category: town.category,
          width: _avatarSize,
          height: _avatarSize,
          fit: BoxFit.cover,
          placeholderIcon: Icons.location_city_rounded,
        ),
      ),
    );
  }
}
