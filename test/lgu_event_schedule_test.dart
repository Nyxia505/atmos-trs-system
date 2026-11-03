import 'package:atmos_trs_system/services/lgu_event_service.dart';
import 'package:atmos_trs_system/widgets/event_description_text.dart';
import 'package:atmos_trs_system/widgets/lgu_events_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all-day range is inclusive and rejects an end before the start', () {
    final error = LguEventService.validateSchedule(
      startDate: DateTime(2026, 10, 16),
      endDate: DateTime(2026, 10, 14),
      allDay: true,
    );
    expect(error, isNotNull);

    expect(
      LguEventService.validateSchedule(
        startDate: DateTime(2026, 10, 14),
        endDate: DateTime(2026, 10, 16),
        allDay: true,
      ),
      isNull,
    );
    expect(
      LguEventService.durationDaysForRange(
        startDate: DateTime(2026, 10, 14),
        endDate: DateTime(2026, 10, 16),
      ),
      3,
    );
  });

  test('timed end before start on the same day is rejected', () {
    final error = LguEventService.validateSchedule(
      startDate: DateTime(2026, 10, 14),
      endDate: DateTime(2026, 10, 14),
      allDay: false,
      startHour: 10,
      startMinute: 0,
      endHour: 9,
      endMinute: 0,
    );
    expect(error, contains('after'));
  });

  test('duration longer than 60 days is rejected', () {
    final error = LguEventService.validateSchedule(
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 4, 1),
      allDay: true,
    );
    expect(error, contains('60'));
  });

  test('phase follows the Manila window', () {
    final start = LguEventService.instantFromManilaWall(
      DateTime(2026, 10, 20, 9),
    );
    final end = LguEventService.instantFromManilaWall(
      DateTime(2026, 10, 20, 17),
    );
    final data = <String, dynamic>{
      'allDay': false,
      'startsAt': start,
      'endsAt': end,
      'published': false,
      'scheduleState': 'scheduled',
    };

    expect(
      LguEventService.schedulePhase(data, DateTime(2026, 10, 1, 8)),
      'Scheduled',
    );
    expect(
      LguEventService.schedulePhase(data, DateTime(2026, 10, 19, 12)),
      'Upcoming',
    );
    expect(
      LguEventService.schedulePhase(data, DateTime(2026, 10, 20, 10)),
      'Ongoing',
    );
    expect(
      LguEventService.schedulePhase(data, DateTime(2026, 10, 20, 17)),
      'Expired',
    );
    expect(
      LguEventService.isVisibleToTourists({...data, 'published': true}),
      isFalse,
    );
    expect(
      LguEventService.isWithinSchedule(data, DateTime(2026, 10, 20, 10)),
      isTrue,
    );
  });

  test('all-day event occupies each day in the range and not the next', () {
    final start = LguEventService.instantFromManilaWall(DateTime(2026, 10, 20));
    final end = LguEventService.instantFromManilaWall(DateTime(2026, 10, 23));
    final data = <String, dynamic>{
      'allDay': true,
      'startsAt': start,
      'endsAt': end,
    };
    expect(LguEventService.occursOnDay(data, DateTime(2026, 10, 20)), isTrue);
    expect(LguEventService.occursOnDay(data, DateTime(2026, 10, 22)), isTrue);
    expect(LguEventService.occursOnDay(data, DateTime(2026, 10, 23)), isFalse);
    expect(LguEventService.eventDurationDays(data), 3);
  });

  testWidgets('calendar shows a month and opens a date on phone and desktop widths',
      (tester) async {
    final start = LguEventService.instantFromManilaWall(DateTime(2026, 10, 20));
    final end = LguEventService.instantFromManilaWall(DateTime(2026, 10, 21));
    DateTime? selected;
    Future<void> pump(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LguEventsCalendar(
              month: DateTime(2026, 10),
              events: [
                {
                  'allDay': true,
                  'startsAt': start,
                  'endsAt': end,
                  'title': 'Festival',
                },
              ],
              accent: const Color(0xFFEA580C),
              onMonthChanged: (_) {},
              onDaySelected: (day) => selected = day,
            ),
          ),
        ),
      );
      expect(find.text('October 2026'), findsOneWidget);
      expect(find.text('Festival'), findsOneWidget);
      await tester.tap(find.text('20'));
      await tester.pump();
      expect(selected, DateTime(2026, 10, 20));
    }

    await pump(const Size(390, 844));
    await pump(const Size(1280, 800));
    addTearDown(tester.view.resetPhysicalSize);
  });

  test('replaced photo wins over a leftover gallery and legacy image field', () {
    const fresh = 'data:image/jpeg;base64,NEWPHOTO';
    final event = {
      'imageBase64': 'NEWPHOTO',
      'image': 'https://cdn.example/old-poster.jpg',
      'imageUrls': ['https://cdn.example/old-poster.jpg'],
    };

    expect(LguEventService.resolveDisplayImage(event), fresh);
    expect(LguEventService.imageUrlsOf(event).first, fresh);

    final catalog = LguEventService.normalizeCatalogEvent('evt1', {
      'title': 'Fiesta',
      'imageBase64': 'NEWPHOTO',
      'image': 'https://cdn.example/old-poster.jpg',
      'municipalityName': 'Oroquieta City',
    });
    expect(LguEventService.resolveDisplayImage(catalog), fresh);
  });

  test('a saved storage url stays the cover after catalog normalize', () {
    const next = 'https://cdn.example/new-poster.jpg';
    final catalog = LguEventService.normalizeCatalogEvent('evt2', {
      'title': 'Parade',
      'imageUrl': next,
      'image': 'https://cdn.example/old-poster.jpg',
      'imageUrls': ['https://cdn.example/old-poster.jpg'],
      'municipalityName': 'Oroquieta City',
    });
    expect(LguEventService.resolveDisplayImage(catalog), next);
    expect(LguEventService.imageUrlsOf(catalog).first, next);
  });

  Map<String, dynamic> allDay(String title, int month, int day) {
    final start = DateTime(2026, month, day);
    final end = start.add(const Duration(days: 1));
    return {
      'title': title,
      'allDay': true,
      'startsAt': LguEventService.instantFromManilaWall(start),
      'endsAt': LguEventService.instantFromManilaWall(end),
    };
  }

  test('events sort upcoming, then ongoing, then recently expired', () {
    final now = DateTime(2026, 10, 30, 12);
    final list = [
      allDay('Drum Corps', 10, 7),
      allDay('November Festival', 11, 5),
      allDay('Town Fair', 10, 30),
      allDay('River Fest', 10, 20),
      allDay('Halloween', 10, 31),
    ];
    list.sort((a, b) => LguEventService.compareBySchedule(a, b, now));
    expect(list.map((event) => event['title']), [
      'Halloween',
      'November Festival',
      'Town Fair',
      'River Fest',
      'Drum Corps',
    ]);

    list[0]['startsAt'] = LguEventService.instantFromManilaWall(DateTime(2026, 10, 1));
    list[0]['endsAt'] =
        LguEventService.instantFromManilaWall(DateTime(2026, 10, 2));
    list.sort((a, b) => LguEventService.compareBySchedule(a, b, now));
    expect(list.last['title'], 'Halloween');
  });

  test('a date-only event is ordered from its calendar day', () {
    final now = DateTime(2026, 10, 30, 9);
    final order = LguEventService.compareBySchedule(
      {'title': 'Market', 'date': '2026-10-31'},
      {'title': 'Old', 'date': '2026-10-07'},
      now,
    );
    expect(order, lessThan(0));
  });

  test('tourist push copy names the event, place, and Manila date', () {
    final now = DateTime(2026, 10, 30, 12);
    final schedule = {
      'title': 'Halloween',
      'allDay': true,
      'startsAt': LguEventService.instantFromManilaWall(DateTime(2026, 10, 31)),
      'endsAt': LguEventService.instantFromManilaWall(DateTime(2026, 11, 1)),
    };
    expect(
      LguEventService.touristNotificationTitle(schedule, now),
      'Upcoming Event: Halloween',
    );
    expect(
      LguEventService.touristNotificationBody(
        title: 'Halloween',
        place: 'Oroquieta City',
        description: '',
        schedule: schedule,
      ),
      'Join the Halloween in Oroquieta City on October 31, 2026!',
    );
    expect(
      LguEventService.touristNotificationBody(
        title: 'Halloween',
        place: 'Oroquieta City',
        description: 'Join the **Halloween** celebration',
        schedule: schedule,
      ),
      'Join the Halloween celebration — Oroquieta City · October 31, 2026',
    );

    final finished = {
      'title': 'Drum Corps Competition',
      'allDay': true,
      'startsAt': LguEventService.instantFromManilaWall(DateTime(2026, 10, 7)),
      'endsAt': LguEventService.instantFromManilaWall(DateTime(2026, 10, 8)),
    };
    expect(LguEventService.schedulePhase(finished, now), 'Expired');
  });

  test('notification text keeps the date, place, and plain description', () {
    expect(
      LguEventService.notificationSummary(
        when: '2026-10-31 · All day · 1 day',
        place: 'Oroquieta City',
        description: 'Join the **Halloween** parade at the plaza.',
      ),
      '2026-10-31 · All day · 1 day · Oroquieta City · Join the Halloween parade at the plaza.',
    );
  });

  test('markdown bold keeps the words and marks them bold', () {
    const style = TextStyle(fontSize: 13);
    final spans = EventDescriptionText.spans(
      'Meet at **Plaza** on **October 31**.',
      style,
    );
    expect(
      spans.map((span) => (span as TextSpan).text).join(),
      'Meet at Plaza on October 31.',
    );
    expect((spans[1] as TextSpan).style?.fontWeight, FontWeight.w700);
    expect(spans.where((span) => (span as TextSpan).text == '**').isEmpty, isTrue);
  });
}
