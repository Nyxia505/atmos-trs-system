import 'package:atmos_trs_system/services/lgu_event_service.dart';
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
}
