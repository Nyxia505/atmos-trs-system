import 'package:flutter/material.dart';
import 'data.dart';
import 'services/spot_interaction_history.dart';
import 'services/spot_ratings_store.dart';
import 'trip_planner_utils.dart' show formatSpotFeeForDisplay;
import 'trip_preferences_store.dart';
import 'widgets/municipality_image.dart';
import 'widgets/user_profile_avatar.dart';

class SpotDetailScreen extends StatefulWidget {
  final TouristSpot spot;
  const SpotDetailScreen({super.key, required this.spot});

  @override
  State<SpotDetailScreen> createState() => _SpotDetailScreenState();
}

class _SpotDetailScreenState extends State<SpotDetailScreen> {
  bool _isFavorited = false;

  @override
  void initState() {
    super.initState();
    final key = normalizeTourismNameKey(widget.spot.name);
    _isFavorited =
        SpotInteractionHistoryStore.instance.favoritedKeys.contains(key);
    SpotInteractionHistoryStore.instance.recordViewed(widget.spot);
    SpotRatingsStore.instance.ensureLoaded();
  }

  Future<void> _toggleFavorite() async {
    final next = !_isFavorited;
    setState(() => _isFavorited = next);
    await SpotInteractionHistoryStore.instance.recordFavorited(
      widget.spot,
      favorited: next,
    );
  }

  Future<void> _openWriteReview() async {
    double selectedRating = 5.0;
    final descriptionController = TextEditingController();
    final result = await showDialog<({double rating, String comment})>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Rate this spot'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.spot.displayName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: InteractiveRatingBadge(
                        rating: selectedRating,
                        onChanged: (v) =>
                            setDialogState(() => selectedRating = v),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      minLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: 'Comment (optional)',
                        hintText: 'Share anything about your visit...',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.pop(
                      ctx,
                      (
                        rating: selectedRating,
                        comment: descriptionController.text.trim(),
                      ),
                    );
                  },
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
    final comment = result?.comment ?? '';
    final rating = result?.rating;
    // Dispose after the dialog route is fully removed from the tree.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      descriptionController.dispose();
    });
    if (rating == null || !mounted) return;

    final reviewer = SpotRatingsStore.currentReviewer();
    await SpotRatingsStore.instance.add(
      SpotRating(
        userName: reviewer.name,
        spotName: widget.spot.name,
        rating: rating,
        description: comment,
        userId: reviewer.userId,
        profilePhotoPath: reviewer.photo,
        createdAt: DateTime.now(),
      ),
    );
    await TripPreferencesStore.instance.recordSpotRating(
      widget.spot.type,
      rating,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Thanks for your review!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final spot = widget.spot;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
            slivers: [
              // Hero image app bar
              SliverAppBar(
                expandedHeight: 340,
                pinned: true,
                backgroundColor: AppColors.primary,
                iconTheme: const IconThemeData(color: Colors.white),
                actions: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: IconButton(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black.withValues(alpha: 0.35),
                      ),
                      icon: Icon(
                        _isFavorited ? Icons.favorite : Icons.favorite_border,
                        color: _isFavorited ? Colors.redAccent : Colors.white,
                      ),
                      onPressed: _toggleFavorite,
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      buildTouristSpotProfileImage(
                        spot,
                        fallback: _gradientPlaceholder(),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.5),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.black.withValues(alpha: 0.05),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                spot.displayName,
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textDark,
                                  height: 1.15,
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  StarRating(
                                    rating: spot.rating,
                                    size: 18,
                                    color: AppColors.primary,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    spot.rating.toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 14,
                                      color: AppColors.textDark,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _SpotFactChip(
                                    icon: Icons.category_outlined,
                                    label: spot.isHotel ? 'Hotel' : spot.type,
                                  ),
                                  if (spot.location.trim().isNotEmpty)
                                    _SpotFactChip(
                                      icon: Icons.location_on_outlined,
                                      label: spot.location,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.listTilePeach,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.sell_outlined,
                                color: AppColors.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Price range',
                                    style: TextStyle(
                                      color: AppColors.textGrey,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    spot.priceRange.trim().isEmpty
                                        ? 'Not listed'
                                        : spot.priceRange,
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Estimated cost breakdown (values from admin form)
                      _CostBreakdownCard(
                        entranceFee: spot.entranceFee,
                        foodAndDrinksPrice: spot.foodAndDrinksPrice,
                        otherSouvenirsPrice: spot.otherSouvenirsPrice,
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        'About this place',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.05),
                          ),
                        ),
                        child: Text(
                          spot.description.isEmpty
                              ? 'No description available.'
                              : spot.description,
                          style: const TextStyle(
                            fontSize: 14.5,
                            color: AppColors.textGrey,
                            height: 1.65,
                          ),
                        ),
                      ),
                      if (_categoryHighlights(spot).isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'Highlights',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _categoryHighlights(spot).map((h) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.listTilePeach,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                h,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textDark,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],

                      const SizedBox(height: 24),

                      ValueListenableBuilder<int>(
                        valueListenable: SpotRatingsStore.instance.revision,
                        builder: (context, revision, child) {
                          final reviews =
                              SpotRatingsStore.instance.forSpot(spot.name);
                          return _SpotReviewsSection(
                            reviews: reviews,
                            onWriteReview: _openWriteReview,
                          );
                        },
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
    );
  }

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

  /// Only the place category from Firestore (`category`, else `type`).
  List<String> _categoryHighlights(TouristSpot spot) {
    final category = spot.category.trim();
    if (category.isNotEmpty) return [category];
    final type = spot.type.trim();
    if (type.isNotEmpty && type != 'spot' && type != 'hotel') return [type];
    return const [];
  }

}

class _SpotReviewsSection extends StatelessWidget {
  final List<SpotRating> reviews;
  final VoidCallback onWriteReview;

  const _SpotReviewsSection({
    required this.reviews,
    required this.onWriteReview,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reviews',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: FilledButton.icon(
            onPressed: onWriteReview,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.rate_review_outlined, size: 18),
            label: const Text(
              'Write a review',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (reviews.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withOpacity(0.06)),
            ),
            child: const Text(
              'No reviews yet. Be the first to rate this spot.',
              style: TextStyle(color: AppColors.textGrey, fontSize: 13.5),
            ),
          )
        else
          ...reviews.map((r) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _ReviewCard(review: r),
              )),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final SpotRating review;

  const _ReviewCard({required this.review});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildReviewerAvatar(
            userId: review.userId,
            profilePhotoPath: review.profilePhotoPath,
            size: 46,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  review.userName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    StarRating(
                      rating: review.rating,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      review.rating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                if (review.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    review.description,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.45,
                      color: AppColors.textGrey,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotFactChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? iconColor;

  const _SpotFactChip({
    required this.icon,
    required this.label,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.planPageBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor ?? AppColors.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CostBreakdownCard extends StatelessWidget {
  final String entranceFee;
  final String foodAndDrinksPrice;
  final String otherSouvenirsPrice;

  const _CostBreakdownCard({
    required this.entranceFee,
    required this.foodAndDrinksPrice,
    required this.otherSouvenirsPrice,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = [
      ('Entrance', formatSpotFeeForDisplay(entranceFee), Icons.confirmation_number_outlined),
      ('Food', formatSpotFeeForDisplay(foodAndDrinksPrice), Icons.restaurant_outlined),
      ('Souvenirs', formatSpotFeeForDisplay(otherSouvenirsPrice), Icons.card_giftcard_outlined),
      ('Transport', 'Varies', Icons.directions_bus_outlined),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Visit costs',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textDark,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = (constraints.maxWidth - 10) / 2;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final tile in tiles)
                  SizedBox(
                    width: width,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.05),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(tile.$3, size: 18, color: AppColors.primary),
                          const SizedBox(height: 8),
                          Text(
                            tile.$1,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textGrey,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tile.$2,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

