import 'package:flutter/material.dart';
import 'package:atmos_trs_system/widgets/misamis_occidental_explore_map.dart';
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/services/tourist_spots_repository.dart';
import 'package:atmos_trs_system/screens/municipality_map_and_spots_screen.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart'
    as activity;
import 'package:intl/intl.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/widgets/ui_skeleton.dart';
import 'package:atmos_trs_system/config/app_theme_controller.dart';
import 'package:atmos_trs_system/data/misamis_occidental_display_spots.dart';
import 'package:atmos_trs_system/data/tourist_spot_image_catalog.dart';
import 'package:atmos_trs_system/utils/visit_record_image_resolver.dart';

const Color _kDarkText = Color(0xFF111827);
const Color _kMuted = Color(0xFF6B7280);

/// Explore tab screen: full Explore Map (Misamis Occidental with 17 municipality pins).
/// Moved from Home screen; same behavior, styling, markers, zoom controls, and Full Map modal.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  MisamisMapMoveTo? _mapMoveTo;
  List<TouristSpotFirestore> _municipalitySpots =
      MisamisOccidentalDisplaySpots.fromSeeds();

  // Sections under the map
  bool _isLoadingSections = false;
  List<TouristSpotFirestore> _recommendedSpots = [];
  List<activity.VisitRecord> _recentVisits = [];
  List<activity.VisitRecord> _allVisits = [];

  bool get _isMobileLayout => MediaQuery.sizeOf(context).width < 600;

  @override
  void initState() {
    super.initState();
    _loadExploreSections();
  }

  void _openMunicipality(TouristSpotFirestore spot) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            MunicipalityMapAndSpotsScreen(municipalityIdOrName: spot.name),
      ),
    );
  }

  Future<void> _loadExploreSections() async {
    if (mounted) setState(() => _isLoadingSections = true);
    final displaySpots = _municipalitySpots.isNotEmpty
        ? _municipalitySpots
        : MisamisOccidentalDisplaySpots.fromSeeds();
    var visits =
        await activity.UserActivityService.syncVisitedSpotsFromQrCheckins();
    visits = await VisitRecordImageResolver.enrichAndPersist(
      visits,
      spots: displaySpots,
    );
    final recent = visits.take(3).toList();

    List<TouristSpotFirestore> recommended;
    if (visits.isNotEmpty) {
      final Map<String, int> counts = {};
      for (final v in visits) {
        final key = v.category.toLowerCase();
        if (key.isEmpty) continue;
        counts[key] = (counts[key] ?? 0) + 1;
      }
      final topCategories = counts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final Set<String> top = topCategories.take(2).map((e) => e.key).toSet();

      final sortedByRating = List<TouristSpotFirestore>.from(displaySpots)
        ..sort((a, b) => b.rating.compareTo(a.rating));
      recommended = sortedByRating
          .where((s) => top.contains(s.category.toLowerCase()))
          .toList();
      if (recommended.isEmpty) {
        recommended = sortedByRating;
      }
    } else {
      recommended = displaySpots.where((s) => s.rating >= 4.5).toList()
        ..sort((a, b) => b.rating.compareTo(a.rating));
    }

    recommended = recommended.take(8).toList();

    if (!mounted) return;
    setState(() {
      _recommendedSpots = recommended;
      _allVisits = visits;
      _recentVisits = recent;
      _isLoadingSections = false;
    });
  }

  void _showAllVisits() {
    if (_isMobileLayout) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (ctx) => Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
              leadingWidth: 80,
              leading: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Center(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Back',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'My Recent Visits',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _kDarkText,
                    ),
                  ),
                  Text(
                    _allVisits.isEmpty
                        ? 'No check-ins yet'
                        : '${_allVisits.length} place${_allVisits.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            body: _allVisits.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Scan a destination QR code to record your visit.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _kMuted, fontSize: 14),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: _allVisits.length,
                    itemBuilder: (_, i) => _buildRecentVisitTile(_allVisits[i]),
                  ),
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Full visit history is in your Profile tab.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showFullMap() {
    final spots = _municipalitySpots.isNotEmpty
        ? _municipalitySpots
        : MisamisOccidentalDisplaySpots.fromSeeds();
    final isMobile = MediaQuery.sizeOf(context).width < 600;

    if (isMobile) {
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (ctx) => Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0,
              leadingWidth: 80,
              leading: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Center(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Back',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Misamis Occidental Map',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _kDarkText,
                    ),
                  ),
                  Text(
                    '${spots.length} municipalities & cities',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            body: MisamisOccidentalExploreMap(
              key: const ValueKey('explore-fullscreen-map'),
              spots: spots,
              onSpotTap: (spot) {
                Navigator.pop(ctx);
                _openMunicipality(spot);
              },
            ),
          ),
        ),
      );
      return;
    }

    final accent = AppTheme.primary;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final height = MediaQuery.of(context).size.height * 0.9;
        return Container(
          height: height,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accent.withValues(alpha: 0.14),
                      accent.withValues(alpha: 0.04),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.map_rounded, color: accent, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Misamis Occidental Map',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _kDarkText,
                            ),
                          ),
                          Text(
                            '${spots.length} municipalities & cities',
                            style: TextStyle(
                              fontSize: 13,
                              color: _kMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: MisamisOccidentalExploreMap(
                      key: const ValueKey('explore-fullscreen-map'),
                      spots: spots,
                      onSpotTap: (spot) {
                        Navigator.pop(context);
                        _openMunicipality(spot);
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExploreHeader(BuildContext context) {
    final accent = AppTheme.primary;
    final onHeader = AppTheme.onPrimary;
    final topInset = MediaQuery.paddingOf(context).top;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: topInset),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          decoration: BoxDecoration(
            color: accent,
            borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(28),
              bottomRight: Radius.circular(28),
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: onHeader.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: onHeader.withValues(alpha: 0.45),
              ),
            ),
            child: Icon(Icons.explore_rounded, color: onHeader, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Explore Misamis Occidental',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onHeader,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '17 municipalities • tourist spots & check-ins',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onHeader.withValues(alpha: 0.88),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
          ),
        ),
      ],
    );
  }

  Widget _buildMapCard() {
    final accent = AppTheme.primary;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
            child: Row(
              children: [
                Icon(Icons.map_outlined, size: 20, color: accent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Explore Map',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: _kDarkText,
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _showFullMap,
                  icon: const Icon(Icons.fullscreen_rounded, size: 18),
                  label: const Text('Full map'),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent.withValues(alpha: 0.12),
                    foregroundColor: accent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: misamisEmbeddedMapHeight(context),
            child: StreamBuilder<List<TouristSpotFirestore>>(
              stream: TouristSpotsRepository.streamTouristSpots(),
              builder: (context, snapshot) {
                final firestoreSpots = snapshot.data ?? [];
                final baseSpots =
                    MisamisOccidentalDisplaySpots.mergeWithFirestore(
                  firestoreSpots,
                );
                _municipalitySpots = baseSpots;
                final visibleCount = baseSpots.length;

                return Stack(
                  children: [
                    MisamisOccidentalExploreMap(
                      key: const ValueKey('explore-embedded-map'),
                      spots: baseSpots,
                      onMapReady: (moveTo) => _mapMoveTo = moveTo,
                      onSpotTap: _openMunicipality,
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.25),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 10,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.place_rounded,
                              color: accent,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$visibleCount destinations',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      right: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Tap a pin to explore',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _kMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    String? subtitle,
    required IconData icon,
    Widget? trailing,
  }) {
    final accent = AppTheme.primary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _kDarkText,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: _kMuted, fontSize: 12.5),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        final accent = AppTheme.primary;
        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          body: Column(
            children: [
              _buildExploreHeader(context),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: RefreshIndicator(
                    color: accent,
                    onRefresh: _loadExploreSections,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildMapCard(),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: _buildRecommendedSection(),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 24,
                            ),
                            child: _buildRecentVisitsSection(),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 32)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Sections under the map
  // ---------------------------------------------------------------------------

  Widget _buildRecommendedSection() {
    if (_isLoadingSections) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SkeletonListTiles(count: 2),
      );
    }
    if (_recommendedSpots.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'Recommended for You',
          subtitle: 'Based on your visits and top-rated spots',
          icon: Icons.recommend_rounded,
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: MediaQuery.sizeOf(context).width < 600 ? 188 : 228,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _recommendedSpots.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final spot = _recommendedSpots[index];
              return _buildHorizontalSpotCard(spot);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHorizontalSpotCard(TouristSpotFirestore spot) {
    final accent = AppTheme.primary;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final cardSize = compact ? 188.0 : 228.0;
    final imageH = compact ? 80.0 : 100.0;
    final imageUrl = TouristSpotImageCatalog.displayUrlForSpot(spot);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openMunicipality(spot),
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: cardSize,
          height: cardSize,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withValues(alpha: 0.12)),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    SizedBox(
                      height: imageH,
                      width: double.infinity,
                      child: _buildSpotImage(imageUrl),
                    ),
                  ],
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            spot.category,
                            style: TextStyle(
                              color: accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Text(
                            spot.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _kDarkText,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 16,
                              color: Color(0xFFF59E0B),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              spot.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _kDarkText,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                              color: accent,
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

  Widget _buildRecentVisitsSection() {
    if (_isLoadingSections) {
      return const SizedBox.shrink();
    }
    final accent = AppTheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(
          title: 'My Recent Visits',
          subtitle: _recentVisits.isEmpty
              ? 'Check in at destinations to see them here'
              : 'Your latest QR check-ins',
          icon: Icons.history_rounded,
          trailing: _allVisits.isNotEmpty
              ? TextButton(
                  onPressed: _showAllVisits,
                  child: Text(
                    'View all',
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 12),
        if (_allVisits.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: accent.withValues(alpha: 0.15)),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 40,
                  color: accent.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 10),
                const Text(
                  'No visits yet',
                  style: TextStyle(
                    color: _kDarkText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Scan a destination QR code to record your visit and unlock personalized recommendations.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _kMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            children: _recentVisits
                .map((v) => _buildRecentVisitTile(v))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildVisitThumbnail(activity.VisitRecord visit, {double size = 44}) {
    final imageUrl = VisitRecordImageResolver.resolve(
      visit,
      spots: _municipalitySpots,
    );
    if (imageUrl.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          Icons.place_rounded,
          color: AppTheme.primary,
          size: size * 0.55,
        ),
      );
    }
    Widget image;
    if (imageUrl.startsWith('assets/')) {
      image = Image.asset(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(
          Icons.place_rounded,
          color: AppTheme.primary,
          size: size * 0.55,
        ),
      );
    } else {
      image = Image.network(
        imageUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(
          Icons.place_rounded,
          color: AppTheme.primary,
          size: size * 0.55,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(width: size, height: size, child: image),
    );
  }

  Widget _buildRecentVisitTile(activity.VisitRecord visit) {
    final formatter = DateFormat('MMM d, yyyy');
    final accent = AppTheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _buildVisitThumbnail(visit),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    visit.spotName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _kDarkText,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _buildVisitChip(
                        visit.category,
                        accent,
                      ),
                      _buildVisitChip(
                        formatter.format(visit.visitedAt),
                        _kMuted,
                        filled: false,
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

  Widget _buildVisitChip(String label, Color color, {bool filled = true}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.12) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: filled ? color : _kMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Widget _buildSpotImage(String imageUrl) {
    if (imageUrl.isEmpty) {
      return Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.place, color: Colors.grey),
      );
    }
    if (imageUrl.startsWith('assets/')) {
      return Image.asset(
        imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: Colors.grey.shade200,
          child: const Icon(Icons.place, color: Colors.grey),
        ),
      );
    }
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: Colors.grey.shade200,
        child: const Icon(Icons.place, color: Colors.grey),
      ),
    );
  }
}
