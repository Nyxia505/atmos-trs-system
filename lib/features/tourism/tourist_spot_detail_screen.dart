import 'package:flutter/material.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/vr_tour_config.dart';
import 'package:atmos_trs_system/features/explore/explore_screen.dart'
    show TouristSpot, kTextMuted;
import 'package:atmos_trs_system/screens/vr_webview_screen.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';

class TouristSpotDetailScreen extends StatefulWidget {
  const TouristSpotDetailScreen({super.key, required this.spot});

  final TouristSpot spot;

  @override
  State<TouristSpotDetailScreen> createState() =>
      _TouristSpotDetailScreenState();
}

class _TouristSpotDetailScreenState extends State<TouristSpotDetailScreen> {
  TouristSpot get spot => widget.spot;

  @override
  void initState() {
    super.initState();
    final img = spot.imageUrl.trim();
    UserActivityService.recordRecentlyViewed(
      spotId: spot.id,
      spotName: spot.name,
      category: spot.category,
      imageUrl: img.isNotEmpty ? img : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: Text(
          spot.city.isNotEmpty ? spot.city : 'Tourist Spot',
          style: const TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          // Hero image & overlay
          SizedBox(
            height: MediaQuery.sizeOf(context).width < 600 ? 180 : 240,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildHeroImage(),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.2),
                        Colors.black.withOpacity(0.6),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.place_rounded,
                              color: Colors.white.withOpacity(0.9),
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              spot.city.isNotEmpty
                                  ? spot.city
                                  : 'Misamis Occidental',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        spot.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          spot.category,
                          style: TextStyle(
                            color: AppTheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.star, color: Colors.amber, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        spot.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      if (spot.reviewCount > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          '(${spot.reviewCount} reviews)',
                          style: const TextStyle(
                            color: kTextMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Overview',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    spot.description.isNotEmpty
                        ? spot.description
                        : 'Discover this destination in Misamis Occidental.',
                    style: const TextStyle(
                      color: kTextMuted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  if (_spotHasHostedOrPreviewVr) ...[
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _openVrForSpot(context),
                        icon: const Icon(Icons.vrpano_rounded, size: 20),
                        label: Text(
                          _spotHasHostedVr
                              ? 'Open 360° VR in browser'
                              : 'View VR preview',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _spotHasHostedVr =>
      resolveVrTourUrl(
        vrLink: spot.vrLink,
        spotId: spot.id,
        spotName: spot.name,
      ) !=
      null;

  bool get _spotHasHostedOrPreviewVr =>
      _spotHasHostedVr ||
      (spot.vrPanoramaUrl?.trim().isNotEmpty == true &&
          !isOroquietaPlazaSpot(spotId: spot.id, spotName: spot.name));

  void _openVrForSpot(BuildContext context) {
    openVrForTouristSpot(
      context,
      spotId: spot.id,
      spotName: spot.name,
      vrLink: spot.vrLink,
      vrPanoramaUrl: spot.vrPanoramaUrl,
      imageUrl: spot.imageUrl,
    );
  }

  Widget _buildHeroImage() {
    final imagePath = spot.imageUrl.trim();
    if (imagePath.isEmpty) {
      return _buildHeroPlaceholder();
    }

    if (imagePath.startsWith('assets/')) {
      return Image.asset(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildHeroPlaceholder(),
      );
    }

    return Image.network(
      imagePath,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _buildHeroPlaceholder(),
    );
  }

  Widget _buildHeroPlaceholder() {
    return Container(
      color: Colors.black26,
      alignment: Alignment.center,
      child: const Icon(Icons.photo, size: 64, color: Colors.white70),
    );
  }
}
