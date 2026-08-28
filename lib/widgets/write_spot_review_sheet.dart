import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/models/spot_review.dart';
import 'package:atmos_trs_system/services/spot_review_service.dart';
import 'package:flutter/material.dart';

/// Bottom sheet for writing or editing a spot review.
Future<bool?> showWriteSpotReviewSheet({
  required BuildContext context,
  required String spotId,
  required String spotName,
  SpotReview? existing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _WriteSpotReviewSheet(
      spotId: spotId,
      spotName: spotName,
      existing: existing,
    ),
  );
}

class _WriteSpotReviewSheet extends StatefulWidget {
  const _WriteSpotReviewSheet({
    required this.spotId,
    required this.spotName,
    this.existing,
  });

  final String spotId;
  final String spotName;
  final SpotReview? existing;

  @override
  State<_WriteSpotReviewSheet> createState() => _WriteSpotReviewSheetState();
}

class _WriteSpotReviewSheetState extends State<_WriteSpotReviewSheet> {
  final _commentController = TextEditingController();
  double _rating = 5;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _rating = existing.rating;
      _commentController.text = existing.comment;
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    final result = await SpotReviewService.submitReview(
      spotId: widget.spotId,
      spotName: widget.spotName,
      rating: _rating,
      comment: _commentController.text,
    );

    if (!mounted) return;
    setState(() => _submitting = false);

    switch (result) {
      case SpotReviewSuccess():
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.existing != null ? 'Review updated' : 'Review posted',
            ),
            backgroundColor: AppTheme.primary,
            behavior: SnackBarBehavior.floating,
          ),
        );
      case SpotReviewFailure(:final message):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final accent = AppTheme.primary;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.existing != null ? 'Edit your review' : 'Write a review',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.spotName,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Text(
            'Your rating',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: List.generate(5, (i) {
              final star = i + 1;
              return IconButton(
                onPressed: () => setState(() => _rating = star.toDouble()),
                icon: Icon(
                  star <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: accent,
                  size: 32,
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commentController,
            minLines: 3,
            maxLines: 6,
            maxLength: 500,
            decoration: InputDecoration(
              hintText: 'Share your experience at this spot…',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You can review after scanning the QR code to check in here.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: AppTheme.onPrimary,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(widget.existing != null ? 'Update review' : 'Post review'),
          ),
        ],
      ),
    );
  }
}
