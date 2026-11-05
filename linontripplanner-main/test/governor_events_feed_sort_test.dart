import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trip_plan/admin_announcements_tab.dart';
import 'package:trip_plan/admin_event_form_page.dart';
import 'package:trip_plan/catalog_targeting.dart';
import 'package:trip_plan/data.dart';

void main() {
  test('governor feed shows upcoming, then ongoing, then recent expired', () {
    final now = DateTime(2026, 11, 1, 12);
    final feed = sortGovernorEventsFeed([
      TourismNewsFeedEvent(
        TourismEvent(
          id: 'old',
          title: 'Drum Corps',
          imagePath: '',
          venue: 'Plaza',
          dateTime: DateTime(2026, 10, 7),
        ),
      ),
      TourismNewsFeedEvent(
        TourismEvent(
          id: 'next',
          title: 'Halloween',
          imagePath: '',
          venue: 'Plaza',
          dateTime: DateTime(2026, 11, 2, 18),
        ),
      ),
      TourismNewsFeedAnnouncement(
        TourismAnnouncement(
          id: 'note',
          title: 'Road notice',
          publishedAt: DateTime(2026, 11, 1, 8),
        ),
      ),
      TourismNewsFeedEvent(
        TourismEvent(
          id: 'later',
          title: 'City Fiesta',
          imagePath: '',
          venue: 'Plaza',
          dateTime: DateTime(2026, 11, 20),
        ),
      ),
    ], now);

    expect(
      feed.map(
        (item) => switch (item) {
          TourismNewsFeedEvent(:final event) => event.title,
          TourismNewsFeedAnnouncement(:final announcement) =>
            announcement.title,
        },
      ),
      ['Halloween', 'City Fiesta', 'Road notice', 'Drum Corps'],
    );
    expect(
      governorFeedPhase(DateTime(2026, 11, 2), now),
      GovernorFeedPhase.upcoming,
    );
    expect(
      governorFeedPhase(DateTime(2026, 11, 1, 8), now),
      GovernorFeedPhase.ongoing,
    );
    expect(
      governorFeedPhase(DateTime(2026, 10, 7), now),
      GovernorFeedPhase.expired,
    );
  });

  testWidgets('add event form keeps the existing fields and validation', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: AdminEventFormPage()));
    expect(find.text('Add event'), findsOneWidget);
    expect(find.text('Event Details'), findsOneWidget);
    expect(find.text('Event title *'), findsOneWidget);
    expect(find.text('Event type *'), findsOneWidget);
    expect(find.text('Municipality *'), findsOneWidget);
    expect(find.text('Venue *'), findsOneWidget);
    expect(find.text('Description'), findsWidgets);
    expect(find.text('Image URL (optional)'), findsOneWidget);

    await tester.ensureVisible(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Enter an event title'), findsOneWidget);
    expect(find.text('Select a municipality'), findsOneWidget);
    expect(find.text('Enter a venue'), findsOneWidget);
  });

  testWidgets('add announcement form keeps title, message, and date', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: AdminAnnouncementFormPage()),
    );
    expect(find.text('Add announcement'), findsOneWidget);
    expect(find.text('Title *'), findsOneWidget);
    expect(find.text('Message (optional)'), findsOneWidget);
    expect(find.text('Publish date'), findsOneWidget);
    expect(find.text('Image URL (optional)'), findsOneWidget);

    await tester.ensureVisible(find.text('Save announcement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save announcement'));
    await tester.pump();

    expect(find.text('Enter a title'), findsOneWidget);
  });

  testWidgets(
    'event form keeps a custom type and offers province-wide targeting',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AdminEventFormPage(
            existing: TourismEvent(
              id: 'evt-1',
              title: 'Provincial Games',
              imagePath: '',
              venue: 'Capitol Grounds',
              municipality: kProvinceWideDisplay,
              dateTime: DateTime(2026, 11, 2, 9),
              eventType: 'Provincial Celebration',
              audienceScope: kProvinceWideScope,
            ),
          ),
        ),
      );
      expect(find.text('Provincial Celebration'), findsWidgets);
      expect(find.text(kProvinceWideLabel), findsOneWidget);
      expect(find.text('Capitol Grounds'), findsOneWidget);
    },
  );
}
