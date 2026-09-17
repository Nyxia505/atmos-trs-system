import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/features/profile/widgets/profile_info_row.dart';
import 'package:atmos_trs_system/models/spot_review.dart';
import 'package:atmos_trs_system/screens/my_reviews_screen.dart';
import 'package:atmos_trs_system/services/spot_review_service.dart';
import 'package:flutter/material.dart';

/// Profile summary of the tourist's posted spot reviews.
class MyReviewsSection extends StatelessWidget {
  const MyReviewsSection({super.key});

  static const Color _textMuted = Color(0xFF6B7280);

  void _openAll(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const MyReviewsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primary;

    return StreamBuilder<List<SpotReview>>(
      stream: SpotReviewService.watchUserReviews(),
      builder: (context, snapshot) {
        final reviews = snapshot.data ?? const <SpotReview>[];
        final preview = reviews.take(2).toList();
        final loading =
            snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData;

        return ProfileSectionCard(
          title: 'My reviews',
          subtitle: 'Spots you reviewed after QR check-in',
          icon: Icons.rate_review_outlined,
          children: [
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (reviews.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                child: Text(
                  'No reviews yet. Check in at a destination via QR scan, '
                  'then share your experience from the spot page.',
                  style: TextStyle(color: _textMuted, height: 1.45, fontSize: 14),
                ),
              )
            else ...[
              ...preview.map(
                (review) => _ReviewPreviewRow(review: review, accent: accent),
              ),
              if (reviews.length > preview.length)
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 4),
                  child: Text(
                    '+ ${reviews.length - preview.length} more review${reviews.length - preview.length == 1 ? '' : 's'}',
                    style: TextStyle(color: _textMuted, fontSize: 13),
                  ),
                ),
            ],
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: loading ? null : () => _openAll(context),
                icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                label: Text(
                  reviews.isEmpty
                      ? 'View my reviews'
                      : 'View all ${reviews.length} review${reviews.length == 1 ? '' : 's'}',
                ),
                style: TextButton.styleFrom(foregroundColor: accent),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ReviewPreviewRow extends StatelessWidget {
  const _ReviewPreviewRow({required this.review, required this.accent});

  final SpotReview review;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.star_rounded, color: accent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  review.displaySpotName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  review.comment,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: MyReviewsSection._textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
