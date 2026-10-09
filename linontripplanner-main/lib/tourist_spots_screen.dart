import 'package:flutter/material.dart';
import 'data.dart';
import 'firestore_loader.dart';
import 'services/tourism_session.dart';
import 'spot_detail_screen.dart';
import 'widgets/municipality_image.dart';
import 'widgets/responsive_layout.dart';
import 'widgets/tourism_plan_ui.dart';

class TouristSpotsScreen extends StatefulWidget {
  /// When true (bottom-nav tab), hide the back button so Home shell stays put.
  final bool embeddedInShell;

  const TouristSpotsScreen({super.key, this.embeddedInShell = false});

  @override
  State<TouristSpotsScreen> createState() => _TouristSpotsScreenState();
}

class _TouristSpotsScreenState extends State<TouristSpotsScreen> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    tourismCatalogRevision.addListener(_onCatalogRevision);
    _ensureSpotsLoaded();
  }

  @override
  void dispose() {
    tourismCatalogRevision.removeListener(_onCatalogRevision);
    super.dispose();
  }

  void _onCatalogRevision() {
    if (mounted) setState(() {});
  }

  Future<void> _ensureSpotsLoaded() async {
    if (!mounted) return;
    // Already in memory — paint immediately; refresh quietly in background.
    if (allSpots.isNotEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      // Only wait for tourist_spots — not the full catalog.
      await loadTouristSpotsFromFirestore();
    } catch (_) {
      try {
        await bootstrapAppFirestoreOnce();
      } catch (_) {
        // Keep empty state; user can leave and return after network recovers.
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<TouristSpot> _dedupedSpots() {
    final byName = <String, TouristSpot>{};
    for (final s in allSpots) {
      final prev = byName[s.name];
      if (prev == null) {
        byName[s.name] = s;
        continue;
      }
      final prevHas = prev.imagePath.trim().isNotEmpty;
      final curHas = s.imagePath.trim().isNotEmpty;
      if (curHas && !prevHas) {
        byName[s.name] = s;
      }
    }
    return byName.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _dedupedSpots();

    return Scaffold(
      backgroundColor: AppColors.planPageBg,
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Tourist Spots'),
        automaticallyImplyLeading: !widget.embeddedInShell,
        leading: widget.embeddedInShell
            ? null
            : IconButton(
                icon: const Icon(
                  Icons.chevron_left_rounded,
                  color: AppColors.textDark,
                  size: 28,
                ),
                onPressed: () => Navigator.pop(context),
              ),
      ),
      body: TourismPlanPageBody(
        child: TourismResponsiveBody(
          maxWidth: 960,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TourismPlanUi.sectionTitleBar(
                  title: 'Explore spots',
                  trailing: '${filtered.length}',
                ),
              ),
              Expanded(
                child: _loading && filtered.isEmpty
                    ? const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      )
                    : filtered.isEmpty
                        ? const TourismEmptyState(
                            icon: Icons.place_outlined,
                            message: 'No tourist spots loaded yet.',
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                            cacheExtent: 480,
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final spot = filtered[index];
                              return TourismSpotListRow(
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: 72,
                                    height: 72,
                                    child: buildTouristSpotProfileImage(
                                      spot,
                                      memCacheWidth: 144,
                                      memCacheHeight: 144,
                                      fallback: ColoredBox(
                                        color: AppColors.primary
                                            .withValues(alpha: 0.1),
                                        child: const Icon(
                                          Icons.landscape_rounded,
                                          color: AppColors.primary,
                                          size: 32,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                title: spot.displayName,
                                subtitle: spot.description,
                                meta:
                                    '${spot.location.isNotEmpty ? spot.location : 'Misamis Occidental'} - ${spot.priceRange} - ${spot.rating.toStringAsFixed(1)}',
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        SpotDetailScreen(spot: spot),
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
