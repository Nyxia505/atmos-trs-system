import 'dart:async' show unawaited;

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/config/app_theme_controller.dart';
import 'package:atmos_trs_system/models/spot_review.dart';
import 'package:atmos_trs_system/models/tourist_destination_detail.dart';
import 'package:atmos_trs_system/models/tourist_spot_firestore.dart';
import 'package:atmos_trs_system/screens/spot_reviews_screen.dart';
import 'package:atmos_trs_system/screens/vr_webview_screen.dart';
import 'package:atmos_trs_system/services/spot_review_service.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';
import 'package:atmos_trs_system/widgets/spot_image.dart';
import 'package:atmos_trs_system/widgets/write_spot_review_sheet.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:atmos_trs_system/utils/maps_directions_launcher.dart';

/// Polished destination details — opens from Home Dashboard featured / all places.
class TouristDestinationDetailScreen extends StatefulWidget {
  const TouristDestinationDetailScreen({
    super.key,
    required this.destination,
    this.firestoreSpot,
  });

  final TouristDestinationDetail destination;
  final TouristSpotFirestore? firestoreSpot;

  @override
  State<TouristDestinationDetailScreen> createState() =>
      _TouristDestinationDetailScreenState();
}

class _TouristDestinationDetailScreenState
    extends State<TouristDestinationDetailScreen> {
  static const Color _textDark = Color(0xFF111827);
  static const Color _textMuted = Color(0xFF6B7280);
  static const Color _pageBg = Color(0xFFE8ECF0);

  final PageController _galleryController = PageController();
  int _galleryIndex = 0;
  bool _isSaved = false;
  bool _isSaving = false;
  SpotReview? _userReview;
  bool _canReview = false;

  TouristDestinationDetail get d => widget.destination;

  @override
  void initState() {
    super.initState();
    _loadSaved();
    _loadReviewEligibility();
    unawaited(
      UserActivityService.recordRecentlyViewed(
        spotId: d.spotId,
        spotName: d.name,
        category: d.category,
        imageUrl: d.primaryImage,
      ),
    );
  }

  @override
  void dispose() {
    _galleryController.dispose();
    super.dispose();
  }

  Future<void> _loadSaved() async {
    if (d.spotId.isEmpty) return;
    final saved = await UserActivityService.isSpotSaved(d.spotId);
    if (mounted) setState(() => _isSaved = saved);
  }

  Future<void> _loadReviewEligibility() async {
    if (d.spotId.isEmpty) return;
    final checkedIn = await SpotReviewService.hasCheckedInAtSpot(d.spotId);
    final userReview = await SpotReviewService.getUserReview(d.spotId);
    if (!mounted) return;
    setState(() {
      _canReview = checkedIn;
      _userReview = userReview;
    });
  }

  Future<void> _openWriteReview() async {
    if (d.spotId.isEmpty) return;
    final posted = await showWriteSpotReviewSheet(
      context: context,
      spotId: d.spotId,
      spotName: d.name,
      existing: _userReview,
    );
    if (posted == true) {
      await _loadReviewEligibility();
    }
  }

  void _openAllReviews() {
    if (d.spotId.isEmpty) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SpotReviewsScreen(
          spotId: d.spotId,
          spotName: d.name,
          fallbackRating: d.rating,
        ),
      ),
    );
  }

  Future<void> _toggleSave() async {
    if (d.spotId.isEmpty || _isSaving) return;
    setState(() => _isSaving = true);
    final saved = await UserActivityService.toggleSaveSpot(d.spotId);
    if (!mounted) return;
    setState(() {
      _isSaved = saved;
      _isSaving = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(saved ? 'Saved to your list' : 'Removed from saved'),
        backgroundColor: AppTheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openDirections() async {
    await MapsDirectionsLauncher.open(
      destinationLabel: MapsDirectionsLauncher.placeLabel(
        name: d.name,
        address: d.address,
        municipality: d.municipality,
      ),
      destinationLatitude: d.hasCoordinates ? d.latitude : null,
      destinationLongitude: d.hasCoordinates ? d.longitude : null,
    );
  }

  Future<void> _shareDestination() async {
    final buffer = StringBuffer()
      ..writeln(d.name)
      ..writeln(d.municipality)
      ..writeln()
      ..writeln(d.shortDescription);
    if (d.hasCoordinates) {
      buffer.writeln(
        'https://www.google.com/maps?q=${d.latitude},${d.longitude}',
      );
    }
    buffer.writeln('\nShared via ATMOS-TRS');
    await Share.share(buffer.toString(), subject: d.name);
  }

  Future<void> _startVrTour() async {
    final spot = widget.firestoreSpot;
    await openVrForTouristSpot(
      context,
      spotId: d.spotId,
      spotName: d.name,
      vrLink: d.vrLink ?? spot?.vrLink,
      vrPanoramaUrl: d.vrPanoramaUrl,
      imageUrl: d.primaryImage,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppThemeController.instance,
      builder: (context, _) {
        final accent = AppTheme.primary;
        final maxW = MediaQuery.sizeOf(context).width;
        final contentPad = maxW >= 900 ? 32.0 : 20.0;

        return Scaffold(
          backgroundColor: _pageBg,
          body: StreamBuilder<SpotReviewSummary>(
            stream: d.spotId.isEmpty
                ? Stream.value(SpotReviewSummary.empty)
                : SpotReviewService.watchSpotReviews(d.spotId),
            builder: (context, reviewSnapshot) {
              final reviewSummary =
                  reviewSnapshot.data ?? SpotReviewSummary.empty;

              return CustomScrollView(
            slivers: [
              _buildAppBar(accent),
              // ── Edge-to-edge hero image + hours strip ──
              SliverToBoxAdapter(child: _buildHeroGallery(accent)),
              // ── Padded content ──
              SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        contentPad,
                        20,
                        contentPad,
                        24 + MediaQuery.paddingOf(context).bottom,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeaderInfo(accent, reviewSummary),
                          const SizedBox(height: 20),
                          _buildInfoCard(accent),
                          const SizedBox(height: 20),
                          _buildQuickActions(accent),
                          if (d.hasVrTour) ...[
                            const SizedBox(height: 20),
                            _buildVrSection(accent),
                          ],
                          if (d.nearbyRestaurants.isNotEmpty) ...[
                            const SizedBox(height: 24),
                            _buildNearbySection(
                              'Restaurants',
                              Icons.restaurant_rounded,
                              d.nearbyRestaurants,
                              accent,
                            ),
                          ],
                          if (d.nearbyHotels.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            _buildNearbySection(
                              'Hotels',
                              Icons.hotel_rounded,
                              d.nearbyHotels,
                              accent,
                            ),
                          ],
                          if (d.nearbyCafes.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            _buildNearbySection(
                              'Cafés',
                              Icons.local_cafe_rounded,
                              d.nearbyCafes,
                              accent,
                            ),
                          ],
                          if (d.nearbyAttractions.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            _buildNearbySection(
                              'Tourist Attractions',
                              Icons.attractions_rounded,
                              d.nearbyAttractions,
                              accent,
                            ),
                          ],
                          const SizedBox(height: 24),
                          _buildReviewsSection(accent, reviewSummary),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
            },
          ),
        );
      },
    );
  }

  Widget _buildAppBar(Color accent) {
    return SliverAppBar(
      pinned: true,
      elevation: 0,
      backgroundColor: accent,
      foregroundColor: Colors.white,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.pop(context),
        tooltip: 'Back',
      ),
      title: Text(
        d.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
      ),
      actions: [
        IconButton(
          onPressed: _isSaving ? null : _toggleSave,
          icon: Icon(
            _isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
          ),
          tooltip: _isSaved ? 'Saved' : 'Save',
        ),
      ],
    );
  }

  Widget _buildHeroGallery(Color accent) {
    final images = d.imageUrls;
    final screenW = MediaQuery.sizeOf(context).width;
    final height = screenW >= 600 ? 320.0 : 260.0;

    return Stack(
      children: [
        SizedBox(
          height: height,
          width: double.infinity,
          child: images.length <= 1
              ? SpotImage(
                  imageUrl: images.isNotEmpty ? images.first : null,
                  spotId: d.spotId,
                  spotName: d.name,
                  category: d.category,
                  width: double.infinity,
                  height: height,
                  fit: BoxFit.cover,
                )
              : PageView.builder(
                  controller: _galleryController,
                  itemCount: images.length,
                  onPageChanged: (i) => setState(() => _galleryIndex = i),
                  itemBuilder: (_, i) => SpotImage(
                    imageUrl: images[i],
                    spotId: d.spotId,
                    spotName: d.name,
                    category: d.category,
                    width: double.infinity,
                    height: height,
                    fit: BoxFit.cover,
                  ),
                ),
        ),
        // Dot indicators overlay on bottom-center of image
        if (images.length > 1)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(images.length, (i) {
                final active = i == _galleryIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 22 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _buildOpeningHoursStrip(Color accent) {
    final isOpen = _isCurrentlyOpen(d.openingHours);
    final statusColor = isOpen ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    final statusLabel = isOpen ? 'Open Now' : 'Closed';
    final statusIcon = isOpen ? Icons.check_circle_rounded : Icons.cancel_rounded;

    return Container(
      width: double.infinity,
      color: const Color(0xFF1E2530),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.access_time_rounded, color: Colors.white70, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              d.openingHours,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor.withValues(alpha: 0.6)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, color: statusColor, size: 13),
                const SizedBox(width: 4),
                Text(
                  statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Rough heuristic — checks if current time falls in any "HH AM–HH PM" range
  /// found in [openingHours]. Falls back to `true` (open) if unparseable.
  bool _isCurrentlyOpen(String hours) {
    final now = TimeOfDay.now();
    final nowMins = now.hour * 60 + now.minute;

    // Match patterns like "8 AM–10 PM", "8:00 AM – 5:00 PM", "Open 24 hours"
    if (hours.toLowerCase().contains('24') ||
        hours.toLowerCase().contains('open daily')) {
      return true;
    }
    if (hours.toLowerCase().contains('closed')) return false;

    final timeRange = RegExp(
      r'(\d{1,2})(?::(\d{2}))?\s*(AM|PM)\s*[–\-]\s*(\d{1,2})(?::(\d{2}))?\s*(AM|PM)',
      caseSensitive: false,
    );

    final matches = timeRange.allMatches(hours);
    for (final m in matches) {
      int toMins(int h, int min, String ampm) {
        var hh = h;
        if (ampm.toUpperCase() == 'PM' && hh != 12) hh += 12;
        if (ampm.toUpperCase() == 'AM' && hh == 12) hh = 0;
        return hh * 60 + min;
      }

      final openH = int.tryParse(m.group(1) ?? '') ?? 0;
      final openMin = int.tryParse(m.group(2) ?? '0') ?? 0;
      final openAmPm = m.group(3) ?? 'AM';
      final closeH = int.tryParse(m.group(4) ?? '') ?? 0;
      final closeMin = int.tryParse(m.group(5) ?? '0') ?? 0;
      final closeAmPm = m.group(6) ?? 'PM';

      final openMins = toMins(openH, openMin, openAmPm);
      var closeMins = toMins(closeH, closeMin, closeAmPm);
      // Handle past-midnight (e.g. 9 AM – 3 AM)
      if (closeMins < openMins) closeMins += 24 * 60;

      if (nowMins >= openMins && nowMins < closeMins) return true;
    }
    return false;
  }

  Widget _buildHeaderInfo(Color accent, SpotReviewSummary reviewSummary) {
    final displayCount = reviewSummary.reviewCount;
    final countLabel = displayCount == 0
        ? 'No reviews yet'
        : '$displayCount review${displayCount == 1 ? '' : 's'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                d.category,
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
            if (displayCount > 0) ...[
              const Spacer(),
              Icon(Icons.star_rounded, color: accent, size: 20),
              const SizedBox(width: 4),
              Text(
                reviewSummary.averageRating.toStringAsFixed(1),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: _textDark,
                ),
              ),
              Text(
                '  ($countLabel)',
                style: const TextStyle(color: _textMuted, fontSize: 13),
              ),
            ] else ...[
              const Spacer(),
              Text(
                countLabel,
                style: const TextStyle(color: _textMuted, fontSize: 13),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Text(
          d.name,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: _textDark,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(Icons.location_on_rounded, size: 18, color: accent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                d.municipality,
                style: const TextStyle(
                  color: _textMuted,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          d.shortDescription,
          style: const TextStyle(
            fontSize: 15,
            height: 1.55,
            color: _textDark,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(Color accent) {
    return _surfaceCard(
      child: Column(
        children: [
          _infoRow(Icons.access_time_rounded, 'Opening Hours', d.openingHours, accent),
          _divider(),
          _infoRow(Icons.payments_outlined, 'Entrance Fee', d.entranceFee, accent),
          _divider(),
          _infoRow(Icons.place_outlined, 'Address', d.address, accent),
          if (d.contactNumber != null && d.contactNumber!.isNotEmpty) ...[
            _divider(),
            _infoRow(Icons.phone_outlined, 'Contact', d.contactNumber!, accent),
          ],
          if (d.bestTimeToVisit != null && d.bestTimeToVisit!.isNotEmpty) ...[
            _divider(),
            _infoRow(
              Icons.wb_sunny_outlined,
              'Best Time to Visit',
              d.bestTimeToVisit!,
              accent,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActions(Color accent) {
    final actions = <({String label, IconData icon, VoidCallback? onTap})>[
      (
        label: 'Get Directions',
        icon: Icons.near_me_rounded,
        onTap: _openDirections,
      ),
      (label: 'Save', icon: Icons.favorite_rounded, onTap: _toggleSave),
      (label: 'Share', icon: Icons.ios_share_rounded, onTap: _shareDestination),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: actions.map((a) {
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: a.onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.10),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(a.icon, size: 18, color: accent),
                  const SizedBox(width: 8),
                  Text(
                    a.label,
                    style: TextStyle(
                      color: a.onTap == null ? _textMuted : _textDark,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildVrSection(Color accent) {
    return _surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.vrpano_rounded, color: accent),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Virtual Tour',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _textDark,
                      ),
                    ),
                    Text(
                      'Explore in 360° before you go',
                      style: TextStyle(color: _textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 140,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  SpotImage(
                    imageUrl: d.primaryImage,
                    spotId: d.spotId,
                    spotName: d.name,
                    fit: BoxFit.cover,
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                  ),
                  Center(
                    child: Icon(
                      Icons.threed_rotation_rounded,
                      color: Colors.white.withValues(alpha: 0.9),
                      size: 48,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _startVrTour,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Start VR Tour'),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNearbySection(
    String title,
    IconData icon,
    List<NearbyPlaceCard> items,
    Color accent,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: accent, size: 22),
            const SizedBox(width: 8),
            Text(
              'Nearby $title',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _textDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _NearbyPlaceTile(
              place: items[i],
              accent: accent,
              onDirections: () {
                unawaited(
                  MapsDirectionsLauncher.open(
                    destinationLabel: items[i].directionsLabel,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewsSection(Color accent, SpotReviewSummary reviewSummary) {
    final reviews = _previewReviews(reviewSummary.reviews);
    final totalCount = reviewSummary.reviewCount;

    return _surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reviews',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _textDark,
                    ),
                  ),
                  Text(
                    totalCount == 0
                        ? 'Be the first to review'
                        : '$totalCount visitor review${totalCount == 1 ? '' : 's'}',
                    style: const TextStyle(color: _textMuted, fontSize: 13),
                  ),
                ],
              ),
              if (totalCount > 0) ...[
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withValues(alpha: 0.4), width: 1.2),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.star_rounded, color: accent, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        reviewSummary.averageRating.toStringAsFixed(1),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          if (d.spotId.isNotEmpty) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _canReview || _userReview != null
                  ? _openWriteReview
                  : () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Scan the QR code here to check in, then you can leave a review.',
                          ),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
              icon: Icon(
                _userReview != null
                    ? Icons.edit_outlined
                    : Icons.rate_review_outlined,
              ),
              label: Text(
                _userReview != null ? 'Edit your review' : 'Write a review',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent.withValues(alpha: 0.4)),
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (reviews.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No reviews yet. Check in via QR scan and share your visit!',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
            )
          else
            ...reviews.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _ReviewTile(
                  review: VisitorReview(
                    author: r.authorName,
                    comment: r.comment,
                    rating: r.rating,
                    dateLabel: r.dateLabel,
                  ),
                  accent: accent,
                  isOwnReview: _userReview != null && r.userId == _userReview!.userId,
                ),
              ),
            ),
          if (totalCount > 0)
            OutlinedButton(
              onPressed: _openAllReviews,
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent.withValues(alpha: 0.4)),
                minimumSize: const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                totalCount > 3 ? 'View all $totalCount reviews' : 'View all reviews',
              ),
            ),
        ],
      ),
    );
  }

  List<SpotReview> _previewReviews(List<SpotReview> all) {
    final uid = _userReview?.userId;
    if (uid == null || uid.isEmpty) return all.take(3).toList();
    final own = all.where((r) => r.userId == uid).toList();
    final others = all.where((r) => r.userId != uid).toList();
    return [...own, ...others].take(3).toList();
  }

  Widget _surfaceCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF0F4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFB0BAC5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _infoRow(IconData icon, String label, String value, Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _textDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    color: _textMuted,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Divider(color: Colors.grey.shade200, height: 1);
}

class _NearbyPlaceTile extends StatefulWidget {
  const _NearbyPlaceTile({
    required this.place,
    required this.accent,
    this.onDirections,
  });

  final NearbyPlaceCard place;
  final Color accent;
  final VoidCallback? onDirections;

  @override
  State<_NearbyPlaceTile> createState() => _NearbyPlaceTileState();
}

class _NearbyPlaceTileState extends State<_NearbyPlaceTile> {
  NearbyPlaceCard get place => widget.place;
  Color get accent => widget.accent;

  bool get _hasGallery => place.gallery.length > 1;

  void _showGallery() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NearbyGallerySheet(place: place, accent: accent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _hasGallery ? _showGallery : widget.onDirections,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 176,
          decoration: BoxDecoration(
            color: const Color(0xFFDDE2E8),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withValues(alpha: 0.45), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.none,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                child: Stack(
                  children: [
                    Container(
                      height: 118,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFCDD3DA),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.22),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.14),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SpotImage(
                        imageUrl: place.imageUrl,
                        fit: BoxFit.cover,
                      ),
                    ),
                    if (_hasGallery)
                      Positioned(
                        bottom: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.62),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.photo_library_rounded,
                                  size: 11, color: Colors.white),
                              const SizedBox(width: 3),
                              Text(
                                '${place.gallery.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        place.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const Spacer(),
                      if (place.contact != null &&
                          place.contact!.trim().isNotEmpty)
                        Text(
                          'Contact: ${place.contact}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: accent),
                        ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              place.driveMinutes != null
                                  ? '~${place.driveMinutes!.round()} min drive'
                                  : '${place.distanceKm.toStringAsFixed(1)} km',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ),
                          if (_hasGallery)
                            Icon(Icons.collections_rounded,
                                size: 14, color: accent)
                          else if (widget.onDirections != null)
                            Icon(Icons.directions_rounded,
                                size: 14, color: accent),
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
    );
  }
}

// ---------------------------------------------------------------------------
// Gallery carousel bottom sheet
// ---------------------------------------------------------------------------
class _NearbyGallerySheet extends StatefulWidget {
  const _NearbyGallerySheet({required this.place, required this.accent});
  final NearbyPlaceCard place;
  final Color accent;

  @override
  State<_NearbyGallerySheet> createState() => _NearbyGallerySheetState();
}

class _NearbyGallerySheetState extends State<_NearbyGallerySheet> {
  final PageController _ctrl = PageController();
  int _index = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.place.gallery;
    final accent = widget.accent;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111827),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: bottomPad + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          // Title row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.hotel_rounded, color: accent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.place.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${_index + 1} / ${images.length}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Carousel
          SizedBox(
            height: 280,
            child: PageView.builder(
              controller: _ctrl,
              itemCount: images.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SpotImage(
                    imageUrl: images[i],
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Dot indicators
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(images.length, (i) {
              final active = i == _index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 20 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: active
                      ? accent
                      : Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          // Contact + directions row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                if (widget.place.contact != null &&
                    widget.place.contact!.trim().isNotEmpty)
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: accent.withValues(alpha: 0.4), width: 1),
                      ),
                      child: Text(
                        'Contact: ${widget.place.contact}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                const Spacer(),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: accent),
                  onPressed: () async {
                    Navigator.pop(context);
                    await MapsDirectionsLauncher.open(
                      destinationLabel: widget.place.directionsLabel,
                    );
                  },
                  icon: const Icon(Icons.directions_rounded, size: 16),
                  label: const Text('Directions'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.review,
    required this.accent,
    this.isOwnReview = false,
  });

  final VisitorReview review;
  final Color accent;
  final bool isOwnReview;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: isOwnReview ? const EdgeInsets.all(12) : EdgeInsets.zero,
      decoration: isOwnReview
          ? BoxDecoration(
              color: accent.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.5), width: 1.5),
            )
          : null,
      child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: accent.withValues(alpha: 0.15),
          child: Text(
            review.author.isNotEmpty ? review.author[0].toUpperCase() : '?',
            style: TextStyle(color: accent, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    review.author,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  if (isOwnReview) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Your review',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(Icons.star_rounded, size: 14, color: accent),
                  Text(
                    review.rating.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
              Text(
                review.dateLabel,
                style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 4),
              Text(
                review.comment,
                style: const TextStyle(fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    ),
    );
  }
}
