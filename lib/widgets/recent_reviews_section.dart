import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/models/spot_review.dart';
import 'package:atmos_trs_system/services/spot_review_service.dart';
import 'package:atmos_trs_system/utils/spot_review_navigation.dart';
import 'package:flutter/material.dart';

/// Home feed of the latest public reviews from all tourists.
class RecentReviewsSection extends StatelessWidget {
  const RecentReviewsSection({super.key, this.maxItems = 8});

  final int maxItems;

  static const Color _textMuted = Color(0xFF6B7280);

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.forum_outlined, size: 20, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Recent reviews',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Latest from visitors across Misamis Occidental',
                      style: TextStyle(
                        color: AppTheme.unselectedMuted,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          StreamBuilder<List<SpotReview>>(
            stream: SpotReviewService.watchRecentReviews(limit: maxItems),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }

              final reviews = snapshot.data ?? const <SpotReview>[];

              if (reviews.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 20,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: accent.withValues(alpha: 0.12)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.rate_review_outlined,
                        size: 40,
                        color: accent.withValues(alpha: 0.55),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          'No reviews yet. Check in at a destination via QR scan '
                          'and be the first to share your experience.',
                          style: TextStyle(
                            color: AppTheme.unselectedMuted,
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children: [
                  for (var i = 0; i < reviews.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _RecentReviewCard(
                      review: reviews[i],
                      accent: accent,
                      onTap: () => openSpotFromReview(context, reviews[i]),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RecentReviewCard extends StatelessWidget {
  const _RecentReviewCard({
    required this.review,
    required this.accent,
    required this.onTap,
  });

  final SpotReview review;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
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
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: accent.withValues(alpha: 0.12),
                      child: Text(
                        review.authorName.isNotEmpty
                            ? review.authorName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
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
                          const SizedBox(height: 2),
                          Text(
                            review.displaySpotName,
                            style: TextStyle(
                              color: accent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded, size: 14, color: accent),
                          const SizedBox(width: 2),
                          Text(
                            review.rating.toStringAsFixed(1),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
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
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  review.dateLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: RecentReviewsSection._textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
