import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/models/municipality.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/features/explore/explore_screen.dart' show TouristSpot, kMockSpots;
import 'package:atmos_trs_system/features/tourism/tourist_spot_detail_screen.dart';
import 'package:atmos_trs_system/widgets/app_search_bar.dart';
import 'package:atmos_trs_system/screens/municipality_map_and_spots_screen.dart';
import 'package:atmos_trs_system/data/tourist_spots_by_municipality.dart';
import 'package:atmos_trs_system/widgets/atmos_osm_tile_layer.dart';

// -----------------------------------------------------------------------------
// Constants (colors from AppTheme)
// -----------------------------------------------------------------------------

const double _kRadius = 12;
const double _kPadding = 20;

// -----------------------------------------------------------------------------
// Screen
// -----------------------------------------------------------------------------

class MisamisOccidentalScreen extends StatefulWidget {
  const MisamisOccidentalScreen({super.key, this.showBackButton = true});

  /// When false (e.g. used as Explore tab in bottom nav), back button is hidden.
  final bool showBackButton;

  @override
  State<MisamisOccidentalScreen> createState() =>
      _MisamisOccidentalScreenState();
}

class _MisamisOccidentalScreenState extends State<MisamisOccidentalScreen> {
  final _searchController = TextEditingController();
  final _sheetController = DraggableScrollableController();
  final _listScrollController = ScrollController();

  late List<Municipality> _municipalities;
  Municipality? _selectedMunicipality;
  /// When non-null, map is in drill-down mode: zoomed to this municipality, showing only tourist spot markers.
  Municipality? _drillDownMunicipality;
  String _searchQuery = '';
  MunicipalityCategory _selectedFilter = MunicipalityCategory.all;
  bool _showAppBarSearch = false;

  @override
  void initState() {
    super.initState();
    _municipalities = getMisamisOccidentalMunicipalities();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _sheetController.dispose();
    _listScrollController.dispose();
    super.dispose();
  }

  List<Municipality> get _filteredMunicipalities {
    var list = _municipalities;
    if (_selectedFilter != MunicipalityCategory.all) {
      list = list.where((m) => m.category == _selectedFilter).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((m) => m.name.toLowerCase().contains(q)).toList();
    }
    return list;
  }

  void _onPinTap(Municipality m) {
    // Enter drill-down: zoom to municipality and show only its tourist spots.
    setState(() {
      _selectedMunicipality = m;
      _drillDownMunicipality = m;
    });
    final index = _filteredMunicipalities.indexWhere((x) => x.id == m.id);
    if (index >= 0) {
      _sheetController.animateTo(
        0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_listScrollController.hasClients) {
          const itemHeight = 76.0;
          _listScrollController.animateTo(
            math.max(0.0, index * itemHeight - 60),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _backToProvinceView() {
    setState(() {
      _drillDownMunicipality = null;
    });
  }

  void _onTouristSpotTap(TouristSpot spot) {
    _showTouristSpotPopup(spot);
  }

  void _showTouristSpotPopup(TouristSpot spot) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _TouristSpotPopupCard(
        spot: spot,
        onViewDetails: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => TouristSpotDetailScreen(spot: spot),
            ),
          );
        },
      ),
    );
  }

  void _openFilterModal() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _FilterModal(
        current: _selectedFilter,
        onSelect: (c) {
          setState(() => _selectedFilter = c);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _openMunicipalityDetails(Municipality m) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _MunicipalityDetailsSheet(municipality: m),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        final topPadding = MediaQuery.paddingOf(context).top;
        return Scaffold(
          backgroundColor: AppTheme.scaffoldBackground,
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                _buildAppBar(topPadding),
                if (_showAppBarSearch) _buildAppBarSearch(),
                Expanded(
                  child: Stack(
                    children: [
                      _buildMapSection(constraints.maxHeight),
                      if (_drillDownMunicipality != null) _buildBackToProvinceButton(),
                      DraggableScrollableSheet(
                        controller: _sheetController,
                        minChildSize: 0.18,
                        maxChildSize: 0.85,
                        initialChildSize: 0.28,
                        builder: (context, scrollController) =>
                            _buildSheet(scrollController, isWide),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(double topPadding) {
    final isDrillDown = _drillDownMunicipality != null;
    return AppBar(
      backgroundColor: AppTheme.scaffoldBackground,
      elevation: 0,
      leading: widget.showBackButton || isDrillDown
          ? IconButton(
              icon: Icon(
                isDrillDown ? Icons.arrow_back : Icons.arrow_back,
                color: Colors.white,
              ),
              onPressed: () {
                if (isDrillDown) {
                  _backToProvinceView();
                } else {
                  Navigator.of(context).pop();
                }
              },
            )
          : null,
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isDrillDown ? _drillDownMunicipality!.name : 'Misamis Occidental',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          Text(
            isDrillDown
                ? 'Tourist spots'
                : '17 Municipalities & Cities',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            _showAppBarSearch ? Icons.close : Icons.search,
            color: Colors.white,
          ),
          onPressed: () =>
              setState(() => _showAppBarSearch = !_showAppBarSearch),
        ),
        IconButton(
          icon: const Icon(Icons.tune_rounded, color: Colors.white),
          onPressed: _openFilterModal,
        ),
      ],
    );
  }

  Widget _buildAppBarSearch() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.only(bottom: 12),
      color: AppTheme.scaffoldBackground,
      child: AppSearchBar(
        controller: _searchController,
        hintText: 'Search municipality...',
        autofocus: true,
        horizontalPadding: _kPadding,
        onChanged: (value) => setState(() {}),
      ),
    );
  }

  Widget _buildMapSection(double totalHeight) {
    final mapHeight = MediaQuery.sizeOf(context).height * 0.6;
    final drillDownSpots = _drillDownMunicipality != null
        ? getTouristSpotsForMunicipality(_drillDownMunicipality!)
        : <TouristSpot>[];
    return SizedBox(
      height: mapHeight,
      width: double.infinity,
      child: _InteractiveMap(
        municipalities: _municipalities,
        filteredMunicipalities: _filteredMunicipalities,
        selected: _selectedMunicipality,
        drillDownMunicipality: _drillDownMunicipality,
        drillDownSpots: drillDownSpots,
        onPinTap: _onPinTap,
        onTouristSpotTap: _onTouristSpotTap,
        onViewDetails: _openMunicipalityDetails,
      ),
    );
  }

  Widget _buildBackToProvinceButton() {
    return Positioned(
      left: _kPadding,
      top: MediaQuery.paddingOf(context).top + 8,
      child: Material(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(24),
        elevation: 4,
        child: InkWell(
          onTap: _backToProvinceView,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.map_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Back to province',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSheet(ScrollController scrollController, bool isWide) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          _buildDragHandle(),
          _buildSheetSearch(),
          _buildFilterChips(),
          Expanded(
            child: ListView.builder(
              controller: _listScrollController,
              padding: EdgeInsets.fromLTRB(_kPadding, 8, _kPadding, 100),
              itemCount: _filteredMunicipalities.length,
              itemBuilder: (context, index) {
                final m = _filteredMunicipalities[index];
                final isSelected = _selectedMunicipality?.id == m.id;
                return _MunicipalityCard(
                  municipality: m,
                  isSelected: isSelected,
                  onTap: () {
                    setState(() => _selectedMunicipality = m);
                    _openMunicipalityDetails(m);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDragHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildSheetSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      child: AppSearchBar(
        controller: _searchController,
        hintText: 'Search municipality...',
        horizontalPadding: _kPadding,
        onChanged: (value) => setState(() {}),
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
        children: filters.map((f) {
          final selected = _selectedFilter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _selectedFilter = f),
                borderRadius: BorderRadius.circular(24),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.primary : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: selected
                          ? AppTheme.primary
                          : Colors.white.withOpacity(0.9),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icons[f]!,
                        size: 18,
                        color: selected
                            ? Colors.white
                            : AppTheme.unselectedMuted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        labels[f]!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: selected
                              ? Colors.white
                              : AppTheme.unselectedMuted,
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
// Interactive Map with OpenStreetMap (flutter_map)
// -----------------------------------------------------------------------------

class _InteractiveMap extends StatefulWidget {
  const _InteractiveMap({
    required this.municipalities,
    required this.filteredMunicipalities,
    required this.selected,
    this.drillDownMunicipality,
    this.drillDownSpots = const [],
    required this.onPinTap,
    this.onTouristSpotTap,
    required this.onViewDetails,
  });

  final List<Municipality> municipalities;
  final List<Municipality> filteredMunicipalities;
  final Municipality? selected;
  /// When set, map is zoomed to this municipality and shows only [drillDownSpots] (tourist spot markers).
  final Municipality? drillDownMunicipality;
  final List<TouristSpot> drillDownSpots;
  final ValueChanged<Municipality> onPinTap;
  final ValueChanged<TouristSpot>? onTouristSpotTap;
  final ValueChanged<Municipality> onViewDetails;

  @override
  State<_InteractiveMap> createState() => _InteractiveMapState();
}

class _InteractiveMapState extends State<_InteractiveMap> {
  final MapController _mapController = MapController();

  static const LatLng _misamisOccidentalCenter = LatLng(8.35, 123.72);
  static const double _initialZoom = 9.5;

  @override
  void didUpdateWidget(_InteractiveMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.drillDownMunicipality != null) {
      final m = widget.drillDownMunicipality!;
      _mapController.move(LatLng(m.lat, m.lng), 12.5);
    } else if (widget.selected != null && widget.selected != oldWidget.selected && widget.drillDownMunicipality == null) {
      _mapController.move(
        LatLng(widget.selected!.lat, widget.selected!.lng),
        11.0,
      );
    } else if (widget.drillDownMunicipality != oldWidget.drillDownMunicipality && widget.drillDownMunicipality == null) {
      _mapController.move(_misamisOccidentalCenter, _initialZoom);
    }
  }

  bool _isFiltered(Municipality m) {
    return widget.filteredMunicipalities.any((fm) => fm.id == m.id);
  }

  List<Marker> _buildMunicipalityMarkers() {
    return widget.municipalities.map((m) {
      final isSelected = widget.selected?.id == m.id;
      final isInFilter = _isFiltered(m);
      return Marker(
        point: LatLng(m.lat, m.lng),
        width: isSelected ? 200 : 50,
        height: isSelected ? 120 : 60,
        child: GestureDetector(
          onTap: () => widget.onPinTap(m),
          child: isSelected
              ? _buildSelectedMarker(m)
              : _buildLocationPin(m, isInFilter),
        ),
      );
    }).toList();
  }

  List<Marker> _buildTouristSpotMarkers() {
    return widget.drillDownSpots
        .where((s) => s.latitude != 0 || s.longitude != 0)
        .map((spot) {
      return Marker(
        point: LatLng(spot.latitude, spot.longitude),
        width: 44,
        height: 44,
        child: GestureDetector(
          onTap: () => widget.onTouristSpotTap?.call(spot),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  spot.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 2),
              Icon(
                Icons.attractions_rounded,
                size: 28,
                color: AppTheme.primary,
              ),
            ],
          ),
        ),
      );
    }).toList();
  }
  IconData _getCategoryIcon(MunicipalityCategory category) {
    switch (category) {
      case MunicipalityCategory.beaches:
        return Icons.waves_rounded;
      case MunicipalityCategory.mountains:
        return Icons.terrain_rounded;
      case MunicipalityCategory.heritage:
        return Icons.account_balance_rounded;
      case MunicipalityCategory.festivals:
        return Icons.celebration_rounded;
      case MunicipalityCategory.all:
        return Icons.place_rounded;
    }
  }
  
  Color _getCategoryColor(MunicipalityCategory category) {
    switch (category) {
      case MunicipalityCategory.beaches:
        return const Color(0xFF0EA5E9); // Sky blue
      case MunicipalityCategory.mountains:
        return const Color(0xFF22C55E); // Green
      case MunicipalityCategory.heritage:
        return const Color(0xFFA855F7); // Purple
      case MunicipalityCategory.festivals:
        return const Color(0xFFF59E0B); // Amber
      case MunicipalityCategory.all:
        return AppTheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _misamisOccidentalCenter,
            initialZoom: _initialZoom,
            minZoom: 8.0,
            maxZoom: 16.0,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
            onTap: (_, __) {
              // Deselect when tapping on empty area
            },
          ),
          children: [
            buildAtmosOsmTileLayer(
              tileBuilder: (context, child, tile) {
                return ColorFiltered(
                  colorFilter: ColorFilter.matrix(<double>[
                    0.25,
                    0.25,
                    0.25,
                    0,
                    10,
                    0.22,
                    0.22,
                    0.22,
                    0,
                    10,
                    0.30,
                    0.30,
                    0.30,
                    0,
                    15,
                    0,
                    0,
                    0,
                    1,
                    0,
                  ]),
                  child: child,
                );
              },
            ),

            // Dark overlay - MUST use IgnorePointer to allow map interactions
            IgnorePointer(
              child: Container(
                color: AppTheme.scaffoldBackground.withOpacity(0.35),
              ),
            ),

            // Municipality markers (province view) or tourist spot markers (drill-down view)
            MarkerLayer(
              markers: widget.drillDownMunicipality == null
                  ? _buildMunicipalityMarkers()
                  : _buildTouristSpotMarkers(),
            ),
          ],
        ),
        ),

        // Zoom controls overlay (outside FlutterMap so they don't interfere)
        _buildZoomControls(),
        // Map legend (province view only)
        if (widget.drillDownMunicipality == null) _buildMapLegend(),

        // Map attribution
        _buildMapAttribution(),
      ],
    );
  }

  Widget _buildZoomControls() {
    return Positioned(
      right: 16,
      bottom: 24,
      child: Column(
        children: [
          _buildZoomButton(Icons.add, () {
            _mapController.move(
              _mapController.camera.center,
              _mapController.camera.zoom + 1,
            );
          }),
          const SizedBox(height: 8),
          _buildZoomButton(Icons.remove, () {
            _mapController.move(
              _mapController.camera.center,
              _mapController.camera.zoom - 1,
            );
          }),
          const SizedBox(height: 8),
          _buildZoomButton(Icons.my_location, () {
            _mapController.move(_misamisOccidentalCenter, _initialZoom);
          }),
        ],
      ),
    );
  }

  Widget _buildMapLegend() {
    return Positioned(
      left: 12,
      top: 12,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground.withOpacity(0.95),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tourist Destinations',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _buildLegendItem(const Color(0xFF0EA5E9), Icons.waves_rounded, 'Beaches'),
            _buildLegendItem(const Color(0xFF22C55E), Icons.terrain_rounded, 'Mountains'),
            _buildLegendItem(const Color(0xFFA855F7), Icons.account_balance_rounded, 'Heritage'),
            _buildLegendItem(const Color(0xFFF59E0B), Icons.celebration_rounded, 'Festivals'),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLegendItem(Color color, IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on, size: 16, color: color),
          const SizedBox(width: 4),
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }
  
  Widget _buildMapAttribution() {
    return Positioned(
      left: 8,
      bottom: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '© OpenStreetMap',
          style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 9),
        ),
      ),
    );
  }

  Widget _buildLocationPin(Municipality m, bool isActive) {
    final color = isActive ? _getCategoryColor(m.category) : Colors.grey.shade600;
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Location name label
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.7),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            m.name,
            style: TextStyle(
              color: isActive ? Colors.white : Colors.white70,
              fontSize: 9,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 2),
        // Pin icon
        Stack(
          alignment: Alignment.center,
          children: [
            // Shadow
            Icon(
              Icons.location_on,
              size: isActive ? 36 : 30,
              color: Colors.black.withOpacity(0.3),
            ),
            // Main pin
            Icon(
              Icons.location_on,
              size: isActive ? 34 : 28,
              color: color,
            ),
            // Inner icon or dot
            Positioned(
              top: isActive ? 6 : 4,
              child: Container(
                width: isActive ? 14 : 10,
                height: isActive ? 14 : 10,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: m.isCity 
                    ? Icon(Icons.location_city, size: isActive ? 8 : 6, color: color)
                    : Icon(_getCategoryIcon(m.category), size: isActive ? 8 : 6, color: color),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSelectedMarker(Municipality m) {
    final color = _getCategoryColor(m.category);
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Info popup card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      m.isCity ? Icons.location_city : _getCategoryIcon(m.category),
                      color: color,
                      size: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      m.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.place, size: 12, color: Colors.white60),
                  const SizedBox(width: 4),
                  Text(
                    '${m.spotCount} tourist spots',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => widget.onViewDetails(m),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.explore, size: 14, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'View Details',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Arrow pointing down
        CustomPaint(
          size: const Size(16, 10),
          painter: _PopupArrowPainter(color: color),
        ),
        // Location pin below
        Icon(
          Icons.location_on,
          size: 28,
          color: color,
        ),
      ],
    );
  }

  Widget _buildZoomButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: AppTheme.cardBackground,
      borderRadius: BorderRadius.circular(8),
      elevation: 4,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _PopupArrowPainter extends CustomPainter {
  _PopupArrowPainter({this.color = const Color(0xFFF97316)});
  
  final Color color;
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.cardBackground
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, paint);
    canvas.drawLine(
      Offset(0, 0),
      Offset(size.width / 2, size.height),
      borderPaint,
    );
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width / 2, size.height),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _PopupArrowPainter oldDelegate) => oldDelegate.color != color;
}

// -----------------------------------------------------------------------------
// Tourist spot popup card (shown when tapping a tourist spot marker in drill-down)
// -----------------------------------------------------------------------------

class _TouristSpotPopupCard extends StatelessWidget {
  const _TouristSpotPopupCard({
    required this.spot,
    required this.onViewDetails,
  });

  final TouristSpot spot;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Image preview
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
            child: SizedBox(
              height: 160,
              width: double.infinity,
              child: spot.imageUrl.startsWith('http')
                  ? Image.network(
                      spot.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    )
                  : Image.asset(
                      spot.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _placeholder(),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spot.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.primary.withOpacity(0.5)),
                      ),
                      child: Text(
                        spot.category,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.star, size: 18, color: Colors.amber.shade400),
                    const SizedBox(width: 4),
                    Text(
                      spot.rating > 0 ? spot.rating.toStringAsFixed(1) : '—',
                      style: TextStyle(
                        color: Colors.amber.shade400,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.rate_review_outlined, size: 16, color: AppTheme.unselectedMuted),
                    const SizedBox(width: 4),
                    Text(
                      '${spot.reviewCount} reviews',
                      style: TextStyle(
                        color: AppTheme.unselectedMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onViewDetails,
                    icon: const Icon(Icons.photo_library_outlined, size: 20),
                    label: const Text('View details'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppTheme.unselectedMuted.withOpacity(0.2),
      child: Icon(Icons.place, color: AppTheme.unselectedMuted, size: 48),
    );
  }
}

// -----------------------------------------------------------------------------
// Municipality card
// -----------------------------------------------------------------------------

class _MunicipalityCard extends StatelessWidget {
  const _MunicipalityCard({
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
              : AppTheme.cardBackground.withOpacity(0.6),
          borderRadius: BorderRadius.circular(_kRadius),
          border: Border.all(
            color: isSelected
                ? AppTheme.primary
                : Colors.white.withOpacity(0.08),
            width: isSelected ? 1.5 : 1,
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
                    color: isSelected
                        ? AppTheme.primary
                        : Colors.white.withOpacity(0.7),
                    size: 28,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          municipality.name,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${municipality.spotCount} tourist spots',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.6),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.white.withOpacity(0.5),
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

// -----------------------------------------------------------------------------
// Filter modal
// -----------------------------------------------------------------------------

class _FilterModal extends StatelessWidget {
  const _FilterModal({required this.current, required this.onSelect});

  final MunicipalityCategory current;
  final ValueChanged<MunicipalityCategory> onSelect;

  @override
  Widget build(BuildContext context) {
    const options = [
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filter by category',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            ...options.map(
              (c) => ListTile(
                title: Text(
                  labels[c]!,
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: current == c
                    ? Icon(Icons.check, color: AppTheme.primary)
                    : null,
                onTap: () => onSelect(c),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Municipality details sheet
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
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.cardBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                    color: Colors.white.withOpacity(0.3),
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
              const SizedBox(height: 4),
              Text(
                '${spots.length} tourist spots',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                ),
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
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
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
                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14),
                  ),
                )
              else
                ...spots.take(8).map(
                    (spot) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          Icons.place,
                          color: AppTheme.primary.withOpacity(0.9),
                          size: 22,
                        ),
                        title: Text(
                          spot.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: spot.category.isNotEmpty
                            ? Text(
                                spot.category,
                                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12),
                              )
                            : null,
                        trailing: Icon(
                          Icons.chevron_right,
                          color: Colors.white.withOpacity(0.4),
                          size: 20,
                        ),
                      ),
                    ),
                  ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Register visit'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: BorderSide(color: Colors.white.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
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
