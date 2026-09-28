import 'package:flutter/material.dart';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/models/establishment_map_pin.dart';
import 'package:atmos_trs_system/models/establishment_stay_review.dart';
import 'package:atmos_trs_system/services/establishment_gallery_service.dart';
import 'package:atmos_trs_system/services/establishment_map_pins_service.dart';
import 'package:atmos_trs_system/services/establishment_stay_review_service.dart';
import 'package:atmos_trs_system/utils/establishment_capability.dart';
import 'package:atmos_trs_system/widgets/misamis_occidental_explore_map.dart'
    show kEstablishmentMapPinColor;

/// Full-screen tourist view of an approved establishment (gallery + stay reviews).
class EstablishmentPublicDetailScreen extends StatefulWidget {
  const EstablishmentPublicDetailScreen({
    super.key,
    required this.pin,
  });

  final EstablishmentMapPin pin;

  @override
  State<EstablishmentPublicDetailScreen> createState() =>
      _EstablishmentPublicDetailScreenState();
}

class _EstablishmentPublicDetailScreenState
    extends State<EstablishmentPublicDetailScreen> {
  late EstablishmentMapPin _pin;
  final _pageController = PageController();
  int _pageIndex = 0;
  // Kept across gallery swipes (setState) so listeners are not re-created.
  late final Stream<List<String>> _galleryStream =
      EstablishmentGalleryService.watchUrls(widget.pin.id);
  late final Stream<EstablishmentStayReviewSummary> _reviewsStream =
      EstablishmentStayReviewService.watchForEstablishment(widget.pin.id);

  @override
  void initState() {
    super.initState();
    _pin = widget.pin;
    _refreshPin();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _refreshPin() async {
    final fresh = await EstablishmentMapPinsService.getById(_pin.id);
    if (!mounted || fresh == null) return;
    setState(() => _pin = fresh);
  }

  String get _subtitle {
    final parts = <String>[
      if (_pin.category.trim().isNotEmpty) _pin.category.trim(),
      if (_pin.barangay.trim().isNotEmpty) _pin.barangay.trim(),
      if (_pin.municipality.trim().isNotEmpty) _pin.municipality.trim(),
    ];
    return parts.join(' · ');
  }

  bool get _isLodging => EstablishmentCapability.isLodging(_pin.category);

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final images = _pin.displayImageUrls;

    return Scaffold(
      backgroundColor: Colors.white,
      body: StreamBuilder<List<String>>(
        stream: _galleryStream,
        builder: (context, gallerySnap) {
          final liveImages = gallerySnap.data;
          final urls = (liveImages != null && liveImages.isNotEmpty)
              ? liveImages
              : images;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: MediaQuery.sizeOf(context).height * 0.42,
                pinned: true,
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                leading: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Center(
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: Colors.white,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (urls.isEmpty)
                        ColoredBox(
                          color: const Color(0xFF0F172A),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.hotel_rounded,
                                  size: 56,
                                  color: kEstablishmentMapPinColor
                                      .withValues(alpha: 0.9),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Photos coming soon',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.75),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        PageView.builder(
                          controller: _pageController,
                          itemCount: urls.length,
                          onPageChanged: (i) =>
                              setState(() => _pageIndex = i),
                          itemBuilder: (context, i) {
                            return Image.network(
                              urls[i],
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => ColoredBox(
                                color: const Color(0xFF1E293B),
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 48,
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                            );
                          },
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            48,
                            20,
                            20 + (urls.length > 1 ? 8 : 0),
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.75),
                              ],
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _pin.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                              ),
                              if (_subtitle.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _subtitle,
                                  style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.88),
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                              if (urls.length > 1) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: List.generate(urls.length, (i) {
                                    final active = i == _pageIndex;
                                    return Container(
                                      width: active ? 18 : 7,
                                      height: 7,
                                      margin: const EdgeInsets.only(right: 5),
                                      decoration: BoxDecoration(
                                        color: active
                                            ? Colors.white
                                            : Colors.white
                                                .withValues(alpha: 0.4),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    );
                                  }),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      // Keep status bar readable
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: topInset + 8,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.35),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_pin.location.trim().isNotEmpty)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.place_outlined,
                              size: 18,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _pin.location.trim(),
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.35,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 12),
                      Text(
                        'Scan this establishment’s QR on arrival to request a stay. '
                        'Reviews below are from guests who checked out.',
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Guest reviews',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: StreamBuilder<EstablishmentStayReviewSummary>(
                  stream: _reviewsStream,
                  builder: (context, snap) {
                    final summary =
                        snap.data ?? EstablishmentStayReviewSummary.empty;
                    if (snap.connectionState == ConnectionState.waiting &&
                        !snap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    if (summary.reviewCount == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            'No guest reviews yet.',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      );
                    }
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.brandOrange
                                  .withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: AppTheme.brandOrange
                                    .withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.star_rounded,
                                  color: AppTheme.brandOrange,
                                  size: 28,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${summary.averageOverall.toStringAsFixed(1)} overall',
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        _isLodging
                                            ? 'Hotel ${summary.averageHotelRating.toStringAsFixed(1)}★ · '
                                                'Room ${summary.averageRoomRating.toStringAsFixed(1)}★ · '
                                                '${summary.reviewCount} review${summary.reviewCount == 1 ? '' : 's'}'
                                            : '${summary.reviewCount} review${summary.reviewCount == 1 ? '' : 's'}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          for (final r in summary.reviews)
                            _ReviewTile(
                              review: r,
                              showRoomDetails: _isLodging,
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({
    required this.review,
    this.showRoomDetails = true,
  });

  final EstablishmentStayReview review;
  final bool showRoomDetails;

  @override
  Widget build(BuildContext context) {
    final rooms = review.roomNumbers
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final roomLabel = rooms.isEmpty ? null : 'Room ${rooms.join(', ')}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor:
                    kEstablishmentMapPinColor.withValues(alpha: 0.15),
                child: Text(
                  review.authorName.isNotEmpty
                      ? review.authorName[0].toUpperCase()
                      : 'G',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: kEstablishmentMapPinColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.authorName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      showRoomDetails
                          ? (roomLabel == null
                              ? 'Hotel ${review.hotelRating.toStringAsFixed(0)}★ · '
                                  'Room ${review.roomRating.toStringAsFixed(0)}★'
                              : 'Hotel ${review.hotelRating.toStringAsFixed(0)}★ · '
                                  '$roomLabel: ${review.roomRating.toStringAsFixed(0)}★')
                          : '${review.hotelRating.toStringAsFixed(0)}★ overall',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showRoomDetails && roomLabel != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Reviewed $roomLabel',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
            ),
          ],
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review.comment,
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Color(0xFF1F2937),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
