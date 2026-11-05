import 'package:atmos_trs_system/models/tourist_destination_detail.dart';
import 'package:atmos_trs_system/screens/tourist_destination_detail_screen.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';
import 'package:atmos_trs_system/widgets/save_spot_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var userSeq = 0;

  const destination = TouristDestinationDetail(
    spotId: 'aloran_viewpoint',
    name: 'Aloran Viewpoint',
    municipality: 'Aloran',
    category: 'Mountain',
    rating: 4.5,
    reviewCount: 0,
    shortDescription: 'Scenic viewpoint',
    fullDescription: 'Scenic viewpoint in Aloran.',
    imageUrls: const [],
    openingHours: 'Open daily',
    entranceFee: 'Free',
    address: 'Aloran, Misamis Occidental',
    latitude: 8.4146,
    longitude: 123.8222,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    SaveSpotNotice.resetForTest();
    await UserActivityService.bindToUser('save-button-test-user-${userSeq++}');
    await UserActivityService.ensureSavedSpotsLoaded();
  });

  tearDown(SaveSpotNotice.resetForTest);

  Future<void> pumpDetails(WidgetTester tester) async {
    addTearDown(SaveSpotNotice.resetForTest);
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: TouristDestinationDetailScreen(destination: destination),
      ),
    );
    await tester.pump();
    // Flush review-eligibility timeouts so tests do not leak pending Timers.
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('Save becomes Saved and can be removed', (tester) async {
    await pumpDetails(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Saved'), findsNothing);

    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(UserActivityService.isSpotSavedSync('aloran_viewpoint'), isTrue);
    expect(find.text('Saved'), findsWidgets);
    expect(find.text('Aloran Viewpoint saved!'), findsOneWidget);

    SaveSpotNotice.dismiss(tester.element(find.byType(Scaffold).first));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Saved').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(UserActivityService.isSpotSavedSync('aloran_viewpoint'), isFalse);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Removed from saved places'), findsOneWidget);
    await tester.pump(SaveSpotNotice.displayDuration);
  });

  testWidgets('opening an already-saved spot does not show a save notice', (
    tester,
  ) async {
    await pumpDetails(tester);
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    SaveSpotNotice.dismiss(tester.element(find.byType(Scaffold).first));
    await tester.pump();
    await tester.pump(SaveSpotNotice.displayDuration);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Saved'), findsWidgets);
    expect(find.text('Aloran Viewpoint saved!'), findsNothing);

    await tester.pump();
    expect(find.text('Aloran Viewpoint saved!'), findsNothing);
  });

  testWidgets('rapid Save taps do not create a duplicate record', (tester) async {
    await pumpDetails(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(UserActivityService.isSpotSavedSync('aloran_viewpoint'), isTrue);
    expect(await UserActivityService.getSavedSpotIds(), ['aloran_viewpoint']);
    await tester.pump(SaveSpotNotice.displayDuration);
  });

  testWidgets('Get Directions opens the in-app trip planner map', (tester) async {
    final previousOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final text = details.exceptionAsString();
      if (text.contains('ClientException') ||
          text.contains('openstreetmap') ||
          text.contains('HttpException') ||
          text.contains('SocketException')) {
        return;
      }
      previousOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousOnError);

    await pumpDetails(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('Get Directions'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Aloran Viewpoint'), findsWidgets);
    expect(find.text('Two-wheeler'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Add stops'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  });
}
