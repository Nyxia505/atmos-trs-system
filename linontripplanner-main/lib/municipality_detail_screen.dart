import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'data.dart';
import 'mapping_screen.dart';
import 'spot_detail_screen.dart';
import 'widgets/bus_terminal_map_markers.dart';
import 'widgets/municipality_image.dart';
import 'widgets/osm_map_tiles.dart';
import 'widgets/responsive_layout.dart';

Widget _gradientPlaceholder() {
  return Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1A6B3C), Color(0xFF2E8B57)],
      ),
    ),
  );
}

class MunicipalityDetailScreen extends StatelessWidget {
  final Municipality municipality;
  const MunicipalityDetailScreen({super.key, required this.municipality});

  @override
  Widget build(BuildContext context) {
    final spotsInMunicipality = municipality.spots.isNotEmpty
        ? municipality.spots
        : allSpots.where((s) {
            final location = s.location.toLowerCase().trim();
            final name = municipality.name.toLowerCase().trim();
            final shortName = municipality.shortName.toLowerCase().trim();
            return location == name || location == shortName;
          }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // Collapsible App Bar with hero image
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: AppColors.primary,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                municipality.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  buildMunicipalityImageForMunicipality(
                    municipality,
                    fallback: _gradientPlaceholder(),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.6),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Description
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'About',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textDark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          municipality.description,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textGrey,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (busTerminalForMap(municipality) != null) ...[
                    const SizedBox(height: 16),
                    _BusTerminalMapCard(municipality: municipality),
                  ],

                  const SizedBox(height: 20),

                  // Tourist Spots
                  const Text(
                    'Tourist Spots',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // Spots Grid
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final cols = tourismSpotGridCrossAxisCount(
                  constraints.crossAxisExtent,
                  maxColumns: 2,
                );
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.78,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    if (index >= spotsInMunicipality.length) {
                      return const SizedBox.shrink();
                    }
                    final spot = spotsInMunicipality[index];
                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SpotDetailScreen(spot: spot),
                        ),
                      ),
                      child: _SpotGridCard(spot: spot),
                    );
                  }, childCount: spotsInMunicipality.length),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BusTerminalMapCard extends StatelessWidget {
  final Municipality municipality;

  const _BusTerminalMapCard({required this.municipality});

  @override
  Widget build(BuildContext context) {
    final terminal = municipality.busTerminal!;
    final pos = busTerminalLatLng(municipality);
    if (pos == null) return const SizedBox.shrink();

    final center = ll.LatLng(pos.latitude, pos.longitude);
    final markers = buildOsmBusTerminalMarkers([municipality]);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: SizedBox(
              height: 160,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 14,
                  minZoom: 10,
                  maxZoom: 18,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                  backgroundColor: const Color(0xFFE8EEF2),
                ),
                children: [
                  osmBasemapTileLayer(),
                  MarkerLayer(markers: markers),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  terminal.kind == 'stop'
                      ? Icons.directions_bus
                      : Icons.directions_bus_filled,
                  color: terminal.kind == 'stop'
                      ? const Color(0xFF7B1FA2)
                      : const Color(0xFF1565C0),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        busTerminalMarkerTitle(terminal),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        terminal.name,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MappingScreen()),
                  ),
                  child: const Text('Full map'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotGridCard extends StatelessWidget {
  final TouristSpot spot;
  const _SpotGridCard({required this.spot});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              child: buildTouristSpotProfileImage(
                spot,
                fallback: Container(
                  color: AppColors.primary.withOpacity(0.08),
                  child: const Center(
                    child: Icon(
                      Icons.landscape,
                      color: AppColors.primary,
                      size: 40,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spot.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textDark,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (spot.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    spot.description,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textGrey,
                      height: 1.25,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  spot.priceRange,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.star, size: 14, color: Colors.amber.shade700),
                    const SizedBox(width: 4),
                    Text(
                      spot.rating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
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
}
