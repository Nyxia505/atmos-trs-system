import 'package:atmos_trs_system/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const destinations = [
    {'name': 'Bless Amare Sunrise Beach', 'spotId': 'bless_amare_sunrise_beach'},
    {'name': 'Asenso Wellness Park', 'spotId': 'ozamiz_asenso_wellness_park'},
    {'name': 'Asenso Global Gardens', 'spotId': 'tangub_asenso_global_gardens'},
    {'name': 'St. John the Baptist Church', 'spotId': 'jimenez_st_john_the_baptist_church'},
    {'name': 'City Boulevard', 'spotId': 'oroquieta_city_boulevard_and_peoples_park'},
    {'name': 'Asenso Aquamarine Park', 'spotId': 'sinacaban_asenso_aquamarine_park'},
  ];

  Future<void> pumpCarousel(
    WidgetTester tester, {
    required DiscoverCarouselHandle handle,
    required List<Map<String, dynamic>> items,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscoverFeaturedCarousel(
            items: items,
            compact: false,
            handle: handle,
            cardBuilder: (destination) => Text(destination['name'] as String),
          ),
        ),
      ),
    );
  }

  Future<void> elapse(WidgetTester tester, Duration duration) async {
    final steps = duration.inMilliseconds ~/ 50;
    for (var i = 0; i < steps; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('slides to the next destination every 4 seconds and loops', (tester) async {
    final handle = DiscoverCarouselHandle();
    await pumpCarousel(tester, handle: handle, items: destinations);
    expect(handle.logicalIndex, 0);
    expect(find.text('Bless Amare Sunrise Beach'), findsWidgets);

    await elapse(tester, const Duration(seconds: 4, milliseconds: 600));
    expect(handle.logicalIndex, 1);

    await elapse(tester, const Duration(seconds: 4, milliseconds: 600));
    expect(handle.logicalIndex, 2);

    handle.animateToLogical?.call(5);
    await elapse(tester, const Duration(milliseconds: 700));
    expect(handle.logicalIndex, 5);

    await elapse(tester, const Duration(seconds: 4, milliseconds: 600));
    expect(handle.logicalIndex, 0);
  });

  testWidgets('one destination does not advance or throw', (tester) async {
    final handle = DiscoverCarouselHandle();
    await pumpCarousel(
      tester,
      handle: handle,
      items: [destinations.first],
    );
    await tester.pump(const Duration(seconds: 5));
    expect(handle.logicalIndex, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty and single-result filters stay stable', (tester) async {
    final handle = DiscoverCarouselHandle();
    await pumpCarousel(tester, handle: handle, items: const []);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);

    await pumpCarousel(
      tester,
      handle: handle,
      items: [destinations[3]],
    );
    await tester.pump(const Duration(seconds: 5));
    expect(handle.logicalIndex, 0);
    expect(find.text('St. John the Baptist Church'), findsOneWidget);
  });

  testWidgets('manual swipe pauses autoplay for about 5 seconds', (tester) async {
    final handle = DiscoverCarouselHandle();
    await pumpCarousel(tester, handle: handle, items: destinations);
    await tester.pump(const Duration(seconds: 1));

    await tester.drag(find.byType(PageView), const Offset(-520, 0));
    await elapse(tester, const Duration(milliseconds: 800));
    final afterSwipe = handle.logicalIndex;
    expect(afterSwipe, 1);

    await elapse(tester, const Duration(seconds: 4));
    expect(handle.logicalIndex, afterSwipe);

    await elapse(tester, const Duration(seconds: 6));
    expect(handle.logicalIndex, afterSwipe + 1);
  });
}
