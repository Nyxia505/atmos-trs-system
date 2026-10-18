import 'package:atmos_trs_system/models/spot_review.dart';
import 'package:atmos_trs_system/widgets/write_spot_review_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SpotReview review({
    required String userId,
    required double rating,
    required String comment,
  }) {
    return SpotReview(
      id: userId,
      spotId: 'aloran',
      userId: userId,
      authorName: 'Ana',
      rating: rating,
      comment: comment,
      createdAt: DateTime(2026, 10, 12),
    );
  }

  test('a new review updates the count and average without a second copy', () {
    final live = SpotReviewSummary(
      reviews: [review(userId: 'a', rating: 4, comment: 'Nice visit here')],
      averageRating: 4,
      reviewCount: 1,
    );

    final next = live.withReview(
      review(userId: 'b', rating: 2, comment: 'Quiet morning walk'),
    );
    expect(next.reviewCount, 2);
    expect(next.averageRating, 3);

    final edited = next.withReview(
      review(userId: 'b', rating: 5, comment: 'Quiet morning walk'),
    );
    expect(edited.reviewCount, 2);
    expect(edited.reviews.where((item) => item.userId == 'b'), hasLength(1));
    expect(edited.averageRating, 4.5);
  });

  testWidgets('a failed submit keeps the rating and comment for retry', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showWriteSpotReviewSheet(
                    context: context,
                    spotId: 'aloran',
                    spotName: 'Aloran Viewpoint',
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Too short');
    await tester.tap(find.text('Post review'));
    await tester.pumpAndSettle();

    expect(find.text('Please write at least 10 characters.'), findsOneWidget);
    expect(find.text('Too short'), findsOneWidget);
    expect(find.text('Post review'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
