import 'package:atmos_trs_system/widgets/landing_features_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpSection(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: size.width,
              child: const LandingFeaturesSection(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('desktop features layout has the five cards', (tester) async {
    await pumpSection(tester, const Size(1280, 900));
    expect(find.text('QR Code Registration'), findsOneWidget);
    expect(find.text('360° Virtual Tours'), findsOneWidget);
    expect(find.text('Smart Check-ins'), findsOneWidget);
    expect(find.text('Digital Tourist ID'), findsOneWidget);
    expect(find.text('Itinerary Planner'), findsOneWidget);
    expect(find.text('Explore Now'), findsNothing);
    expect(find.text('Start Planning'), findsNothing);
    expect(find.text('Learn More'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet and mobile layouts do not overflow', (tester) async {
    await pumpSection(tester, const Size(800, 900));
    expect(tester.takeException(), isNull);
    await pumpSection(tester, const Size(390, 844));
    expect(find.text('See How It Works'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
