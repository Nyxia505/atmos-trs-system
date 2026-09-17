import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/models/spot_review.dart';
import 'package:atmos_trs_system/services/spot_review_service.dart';
import 'package:atmos_trs_system/utils/spot_review_navigation.dart';
import 'package:atmos_trs_system/widgets/write_spot_review_sheet.dart';
import 'package:flutter/material.dart';

/// Lists every review the signed-in tourist has posted.
class MyReviewsScreen extends StatelessWidget {
  const MyReviewsScreen({super.key});

  static const Color _textDark = Color(0xFF111827);
  static const Color _textMuted = Color(0xFF6B7280);

  Future<void> _openSpot(BuildContext context, SpotReview review) async {
    await openSpotFromReview(context, review);
  }

  Future<void> _editReview(BuildContext context, SpotReview review) async {
    await showWriteSpotReviewSheet(
      context: context,
      spotId: review.spotId,
      spotName: review.displaySpotName,
      existing: review,
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        title: const Text('My Reviews'),
      ),
      body: StreamBuilder<List<SpotReview>>(
        stream: SpotReviewService.watchUserReviews(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final reviews = snapshot.data ?? const <SpotReview>[];

          if (reviews.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.rate_review_outlined, size: 48, color: accent),
                    const SizedBox(height: 12),
                    const Text(
                      'No reviews yet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _textDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Scan a QR code to check in at a spot, then leave a review '
                      'from the destination page.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _textMuted, height: 1.45),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: reviews.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final review = reviews[index];
              return _MyReviewCard(
                review: review,
                accent: accent,
                onViewSpot: () => _openSpot(context, review),
                onEdit: () => _editReview(context, review),
              );
            },
          );
        },
      ),
    );
  }
}

class _MyReviewCard extends StatelessWidget {
  const _MyReviewCard({
    required this.review,
    required this.accent,
    required this.onViewSpot,
    required this.onEdit,
  });

  final SpotReview review;
  final Color accent;
  final VoidCallback onViewSpot;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.displaySpotName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: MyReviewsScreen._textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      review.dateLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: MyReviewsScreen._textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, color: accent, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      review.rating.toStringAsFixed(1),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            review.comment,
            style: const TextStyle(fontSize: 14, height: 1.45),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              TextButton.icon(
                onPressed: onViewSpot,
                icon: const Icon(Icons.place_outlined, size: 18),
                label: const Text('View spot'),
                style: TextButton.styleFrom(foregroundColor: accent),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit'),
                style: TextButton.styleFrom(foregroundColor: accent),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
