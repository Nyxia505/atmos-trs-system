import 'package:atmos_trs_system/config/auth_config.dart';
import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/models/spot_review.dart';
import 'package:atmos_trs_system/services/spot_review_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Full list of reviews for a tourist spot.
class SpotReviewsScreen extends StatelessWidget {
  const SpotReviewsScreen({
    super.key,
    required this.spotId,
    required this.spotName,
    this.fallbackRating,
  });

  final String spotId;
  final String spotName;
  final double? fallbackRating;

  static const Color _textDark = Color(0xFF111827);
  static const Color _textMuted = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primary;
    final currentUid =
        AuthConfig.currentUserUid ?? FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        title: const Text('Reviews'),
      ),
      body: StreamBuilder<SpotReviewSummary>(
        stream: SpotReviewService.watchSpotReviews(spotId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final summary = snapshot.data ?? SpotReviewSummary.empty;
          final reviews = summary.reviews;
          final displayRating = summary.reviewCount > 0
              ? summary.averageRating
              : (fallbackRating ?? 0);
          final displayCount = summary.reviewCount;

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
                      'Be the first to review $spotName after a QR check-in.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _textMuted),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withValues(alpha: 0.12)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.star_rounded, color: accent, size: 28),
                    const SizedBox(width: 8),
                    Text(
                      displayRating.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$displayCount review${displayCount == 1 ? '' : 's'}',
                      style: const TextStyle(color: _textMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ...reviews.map(
                (r) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ReviewCard(
                    review: r,
                    accent: accent,
                    isOwnReview: currentUid != null && r.userId == currentUid,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.review,
    required this.accent,
    this.isOwnReview = false,
  });

  final SpotReview review;
  final Color accent;
  final bool isOwnReview;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOwnReview
              ? accent.withValues(alpha: 0.45)
              : Colors.grey.shade200,
          width: isOwnReview ? 1.5 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: accent.withValues(alpha: 0.15),
            child: Text(
              review.authorName.isNotEmpty
                  ? review.authorName[0].toUpperCase()
                  : '?',
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
                    Expanded(
                      child: Text(
                        review.authorName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (isOwnReview) ...[
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
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
                    Icon(Icons.star_rounded, size: 14, color: accent),
                    Text(
                      review.rating.toStringAsFixed(1),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                Text(
                  review.dateLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: SpotReviewsScreen._textMuted,
                  ),
                ),
                const SizedBox(height: 6),
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
