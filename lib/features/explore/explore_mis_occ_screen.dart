// ignore_for_file: avoid_print
//
// MISAMIS OCCIDENTAL EXPLORE — OpenStreetMap screen (ATMOS TRS)
//
// Uses flutter_map with OpenStreetMap tiles - no API key required!
//

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/models/municipality.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/features/explore/explore_data.dart' show TouristSpot, kMockSpots;
import 'package:atmos_trs_system/widgets/app_search_bar.dart';
import 'package:atmos_trs_system/widgets/atmos_osm_tile_layer.dart';
import 'package:atmos_trs_system/widgets/map_zoom_controls.dart';
import 'package:atmos_trs_system/screens/municipality_map_and_spots_screen.dart';

// -----------------------------------------------------------------------------
// Constants
// -----------------------------------------------------------------------------

const double _kSheetMin = 0.18;
const double _kSheetInitial = 0.30;
const double _kSheetMax = 0.85;
const double _kPadding = 20;
const double _kRadius = 12;

// Initial camera: Misamis Occidental (center).
const double _kMapCenterLat = 8.35;
const double _kMapCenterLng = 123.72;
const double _kMapZoom = 9.2;

// Bounds covering Misamis Occidental only; prevents scrolling outside the province.
final LatLngBounds _kMisamisOccidentalBounds = LatLngBounds(
  const LatLng(7.92, 123.38),
  const LatLng(8.72, 124.02),
);

// -----------------------------------------------------------------------------
// Screen
// -----------------------------------------------------------------------------

class ExploreMisOccScreen extends StatefulWidget {
  const ExploreMisOccScreen({super.key});

  @override
  State<ExploreMisOccScreen> createState() => _ExploreMisOccScreenState();
}

class _ExploreMisOccScreenState extends State<ExploreMisOccScreen> {
  final _searchController = TextEditingController();
  final _sheetController = DraggableScrollableController();
  final MapController _mapController = MapController();

  late List<Municipality> _allMunicipalities;
  Municipality? _selectedMunicipality;
  String _searchQuery = '';
  MunicipalityCategory _selectedCategory = MunicipalityCategory.all;

  @override
  void initState() {
    super.initState();
    _allMunicipalities = getMisamisOccidentalMunicipalities();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _sheetController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  List<Municipality> get filteredMunicipalities {
    var list = _allMunicipalities;
    if (_selectedCategory != MunicipalityCategory.all) {
      list = list.where((m) => m.category == _selectedCategory).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((m) => m.name.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  void _animateToMunicipality(Municipality m) {
    _mapController.move(LatLng(m.lat, m.lng), 12);
  }

  void _recenterProvince() {
    _mapController.move(
      const LatLng(_kMapCenterLat, _kMapCenterLng),
      _kMapZoom,
    );
  }

  void _onMarkerTap(Municipality m) {
    setState(() => _selectedMunicipality = m);
    _animateToMunicipality(m);
    _showMarkerPreviewSheet(m);
  }

  void _showMarkerPreviewSheet(Municipality m) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _MarkerPreviewSheet(
        municipality: m,
        onExplore: () {
          Navigator.pop(context);
          _showMunicipalityDetails(m);
        },
      ),
    );
  }

  void _onListMunicipalityTap(Municipality m) {
    setState(() => _selectedMunicipality = m);
    _animateToMunicipality(m);
    _showMunicipalityDetails(m);
  }

  void _showMunicipalityDetails(Municipality m) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _MunicipalityDetailsSheet(municipality: m),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBackground,
      body: Stack(
        children: [
          _buildMap(),
          _buildBottomSheet(),
        ],
      ),
    );
  }

  Widget _buildMap() {
    final markers = _allMunicipalities.map((m) {
      final isSelected = _selectedMunicipality?.id == m.id;
      return Marker(
        point: LatLng(m.lat, m.lng),
        width: 44,
        height: 44,
        child: GestureDetector(
          onTap: () => _onMarkerTap(m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected ? AppTheme.primary : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? Colors.white : AppTheme.primary,
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              m.isCity ? Icons.location_city : Icons.place,
              color: isSelected ? Colors.white : AppTheme.primary,
              size: 24,
            ),
          ),
        ),
      );
    }).toList();

    return SizedBox.expand(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(_kMapCenterLat, _kMapCenterLng),
              initialZoom: _kMapZoom,
              minZoom: 7,
              maxZoom: 18,
              cameraConstraint: CameraConstraint.contain(
                bounds: _kMisamisOccidentalBounds,
              ),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                scrollWheelVelocity: 0.002,
                pinchZoomThreshold: 0.5,
                pinchMoveThreshold: 20,
              ),
            ),
            children: [
              buildAtmosOsmTileLayer(),
              MarkerLayer(
                markers: markers,
              ),
            ],
          ),
          ),
          OsmMapZoomControls(
            mapController: _mapController,
            minZoom: 7,
            maxZoom: 18,
            onRecenter: _recenterProvince,
            bottom: MediaQuery.of(context).size.height * 0.32,
          ),
          // Map attribution
          Positioned(
            bottom: MediaQuery.of(context).size.height * 0.35,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.8),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '© OpenStreetMap',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSheet() {
    return DraggableScrollableSheet(
      controller: _sheetController,
      minChildSize: _kSheetMin,
      maxChildSize: _kSheetMax,
      initialChildSize: _kSheetInitial,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Column(
            children: [
              _buildDragHandle(),
              _buildSearchField(),
              _buildFilterChips(),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(_kPadding, 8, _kPadding, 100),
                  itemCount: filteredMunicipalities.length,
                  itemBuilder: (context, index) {
                    final m = filteredMunicipalities[index];
                    final isSelected = _selectedMunicipality?.id == m.id;
                    return _MunicipalityListTile(
                      municipality: m,
                      isSelected: isSelected,
                      onTap: () => _onListMunicipalityTap(m),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDragHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppTheme.unselectedMuted.withOpacity(0.5),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      child: AppSearchBar(
        controller: _searchController,
        hintText: 'Search municipality…',
        horizontalPadding: _kPadding,
      ),
    );
  }

  Widget _buildFilterChips() {
    const filters = [
      MunicipalityCategory.all,
      MunicipalityCategory.beaches,
      MunicipalityCategory.mountains,
      MunicipalityCategory.heritage,
      MunicipalityCategory.festivals,
    ];
    final labels = {
      MunicipalityCategory.all: 'All',
      MunicipalityCategory.beaches: 'Beaches',
      MunicipalityCategory.mountains: 'Mountains',
      MunicipalityCategory.heritage: 'Heritage',
      MunicipalityCategory.festivals: 'Festivals',
    };
    final icons = {
      MunicipalityCategory.all: Icons.apps_rounded,
      MunicipalityCategory.beaches: Icons.waves_rounded,
      MunicipalityCategory.mountains: Icons.terrain_rounded,
      MunicipalityCategory.heritage: Icons.account_balance_rounded,
      MunicipalityCategory.festivals: Icons.celebration_rounded,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(_kPadding, 0, _kPadding, 12),
      child: Row(
        children: filters.map((c) {
          final selected = _selectedCategory == c;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _selectedCategory = c),
                borderRadius: BorderRadius.circular(24),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.primary : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: selected ? AppTheme.primary : Colors.white.withOpacity(0.9),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icons[c]!,
                        size: 18,
                        color: selected ? Colors.white : AppTheme.unselectedMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        labels[c]!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected ? Colors.white : AppTheme.unselectedMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

}

// -----------------------------------------------------------------------------
// List tile
// -----------------------------------------------------------------------------

class _MunicipalityListTile extends StatelessWidget {
  const _MunicipalityListTile({
    required this.municipality,
    required this.isSelected,
    required this.onTap,
  });

  final Municipality municipality;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primary.withOpacity(0.2)
              : AppTheme.scaffoldBackground.withOpacity(0.6),
          borderRadius: BorderRadius.circular(_kRadius),
          border: Border.all(
            color: isSelected ? AppTheme.primary : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(_kRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    municipality.isCity ? Icons.location_city : Icons.place,
                    color: isSelected ? AppTheme.primary : AppTheme.unselectedMuted,
                    size: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          municipality.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${municipality.spotCount} spots',
                          style: TextStyle(
                            color: AppTheme.unselectedMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppTheme.unselectedMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Marker preview sheet (quick actions)
// -----------------------------------------------------------------------------

class _MarkerPreviewSheet extends StatelessWidget {
  const _MarkerPreviewSheet({
    required this.municipality,
    required this.onExplore,
  });

  final Municipality municipality;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(_kPadding),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.unselectedMuted.withOpacity(0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            municipality.name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          Text(
            '${municipality.spotCount} tourist spots',
            style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 13),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onExplore,
              icon: const Icon(Icons.explore, size: 18),
              label: const Text('Explore'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Municipality details sheet (top spots + buttons)
// -----------------------------------------------------------------------------

class _MunicipalityDetailsSheet extends StatelessWidget {
  const _MunicipalityDetailsSheet({required this.municipality});

  final Municipality municipality;

  static bool _spotBelongsToMunicipality(TouristSpot spot, Municipality m) {
    final city = spot.city.trim().toLowerCase();
    final name = m.name.toLowerCase();
    if (city == name) return true;
    if (name.startsWith(city) || city.startsWith(name.split(' ').first)) return true;
    if (name.contains(city) || city.contains(name.split(' ').first)) return true;
    return false;
  }

  static List<TouristSpot> _spotsFor(Municipality m) {
    return kMockSpots.where((s) => _spotBelongsToMunicipality(s, m)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final spots = _spotsFor(municipality);

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(_kPadding, 12, _kPadding, 32),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.unselectedMuted.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                municipality.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                ),
              ),
              Text(
                '${spots.length} tourist spots',
                style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 14),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MunicipalityMapAndSpotsScreen(
                          municipalityIdOrName: municipality.name,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.map, size: 18),
                  label: const Text('View on map'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Top tourist spots',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              if (spots.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No tourist spots listed yet for ${municipality.name}.',
                    style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 14),
                  ),
                )
              else
                ...spots.take(8).map((spot) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.place, color: AppTheme.primary.withOpacity(0.9), size: 22),
                        title: Text(spot.name, style: const TextStyle(color: Colors.white, fontSize: 14)),
                        subtitle: spot.category.isNotEmpty
                            ? Text(spot.category, style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 12))
                            : null,
                        trailing: Icon(Icons.chevron_right, color: AppTheme.unselectedMuted, size: 20),
                      ),
                    )),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Register visit'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: AppTheme.unselectedMuted.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
