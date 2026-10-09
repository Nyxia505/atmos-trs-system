import 'dart:async';

import 'package:flutter/material.dart';

import '../data.dart';
import '../trip_preferences_store.dart';
import 'spot_ratings_store.dart';

/// Root navigator used to show the post-Finish rating dialog from a Timer.
final GlobalKey<NavigatorState> tourismRootNavigatorKey =
    GlobalKey<NavigatorState>();

/// After Plan my trip → Finish, waits [delay] then asks to rate the first
/// spot on the saved itinerary.
class TripPostFinishRatingScheduler {
  TripPostFinishRatingScheduler._();
  static final TripPostFinishRatingScheduler instance =
      TripPostFinishRatingScheduler._();

  static const Duration defaultDelay = Duration(minutes: 2);

  Timer? _timer;
  String? _pendingSpotName;
  bool _dialogOpen = false;

  /// Call right after Finish saves the trip.
  void scheduleFirstSpotRating(
    List<List<TouristSpot>> daySpotAssignments, {
    Duration delay = defaultDelay,
  }) {
    TouristSpot? first;
    for (final day in daySpotAssignments) {
      if (day.isNotEmpty) {
        first = day.first;
        break;
      }
    }
    if (first == null) return;

    _timer?.cancel();
    _pendingSpotName = first.name;
    _timer = Timer(delay, () {
      unawaited(_showPromptIfReady());
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pendingSpotName = null;
  }

  Future<void> _showPromptIfReady() async {
    if (_dialogOpen) return;
    final name = _pendingSpotName;
    if (name == null || name.isEmpty) return;

    final spot = findTouristSpotByNameFuzzy(name);
    if (spot == null) return;

    final nav = tourismRootNavigatorKey.currentState;
    final ctx = nav?.context;
    if (ctx == null || !ctx.mounted) {
      _timer = Timer(const Duration(seconds: 5), () {
        unawaited(_showPromptIfReady());
      });
      return;
    }

    _dialogOpen = true;
    _pendingSpotName = null;
    try {
      await showTripSpotRatingDialog(ctx, spot);
    } finally {
      _dialogOpen = false;
    }
  }
}

/// Result from the rating dialog (null = dismissed / Later).
class _RatingDialogResult {
  final double rating;
  final String comment;

  const _RatingDialogResult({required this.rating, required this.comment});
}

/// Centered in-app rating prompt. Saves rating + comment to Firestore via
/// [SpotRatingsStore.add].
Future<bool> showTripSpotRatingDialog(
  BuildContext context,
  TouristSpot spot,
) async {
  final result = await showDialog<_RatingDialogResult>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (ctx) => _TripSpotRatingDialog(spot: spot),
  );

  if (result == null) return false;

  try {
    final reviewer = SpotRatingsStore.currentReviewer();
    await SpotRatingsStore.instance.add(
      SpotRating(
        userName: reviewer.name,
        spotName: spot.name,
        rating: result.rating,
        description: result.comment,
        userId: reviewer.userId,
        profilePhotoPath: reviewer.photo,
        createdAt: DateTime.now(),
      ),
    );
    await TripPreferencesStore.instance.recordSpotRating(
      spot.type,
      result.rating,
    );
  } catch (e) {
    debugPrint('trip rating save failed: $e');
    final errCtx = tourismRootNavigatorKey.currentContext;
    if (errCtx != null && errCtx.mounted) {
      ScaffoldMessenger.of(errCtx).showSnackBar(
        const SnackBar(content: Text('Could not save rating. Try again.')),
      );
    }
    return false;
  }

  final messengerCtx = tourismRootNavigatorKey.currentContext;
  if (messengerCtx != null && messengerCtx.mounted) {
    ScaffoldMessenger.of(messengerCtx).showSnackBar(
      const SnackBar(content: Text('Thanks for your review!')),
    );
  }
  return true;
}

class _TripSpotRatingDialog extends StatefulWidget {
  final TouristSpot spot;

  const _TripSpotRatingDialog({required this.spot});

  @override
  State<_TripSpotRatingDialog> createState() => _TripSpotRatingDialogState();
}

class _TripSpotRatingDialogState extends State<_TripSpotRatingDialog> {
  double _selectedRating = 5.0;
  late final TextEditingController _commentCtrl;

  @override
  void initState() {
    super.initState();
    _commentCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spot = widget.spot;
    return AlertDialog(
      title: const Text('Rate this spot'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              spot.displayName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'How was your visit to the first stop on your trip plan?',
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppColors.textGrey.withValues(alpha: 0.95),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: InteractiveRatingBadge(
                rating: _selectedRating,
                onChanged: (v) => setState(() => _selectedRating = v),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _commentCtrl,
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
          onPressed: () => Navigator.pop(context),
          child: const Text('Later'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            Navigator.pop(
              context,
              _RatingDialogResult(
                rating: _selectedRating,
                comment: _commentCtrl.text.trim(),
              ),
            );
          },
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
