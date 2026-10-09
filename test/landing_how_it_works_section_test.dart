import 'package:atmos_trs_system/widgets/landing_how_it_works_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const steps = [
    LandingHowItWorksStep(
      number: '01',
      title: 'Register',
      description: 'Create your tourist account with basic information',
      icon: Icons.person_add_rounded,
    ),
    LandingHowItWorksStep(
      number: '02',
      title: 'Get QR Code',
      description: 'Receive your unique tourist QR identification',
      icon: Icons.qr_code_2_rounded,
    ),
    LandingHowItWorksStep(
      number: '03',
      title: 'Explore / Preview',
      description: 'Browse destinations and preview spots in VR',
      icon: Icons.explore_rounded,
    ),
    LandingHowItWorksStep(
      number: '04',
      title: 'Plan Itinerary',
      description: 'Organize your trip and add destinations to your itinerary',
      icon: Icons.map_rounded,
    ),
    LandingHowItWorksStep(
      number: '05',
      title: 'Check-in',
      description: 'Scan your QR at each destination you visit',
      icon: Icons.check_circle_rounded,
    ),
  ];

  Future<void> pumpSection(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: size.width,
              child: const LandingHowItWorksSection(steps: steps),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the five existing steps on a wide screen', (tester) async {
    await pumpSection(tester, const Size(1280, 800));
    expect(find.text('5 EASY STEPS'), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
    expect(find.text('Get QR Code'), findsOneWidget);
    expect(find.text('Explore / Preview'), findsOneWidget);
    expect(find.text('Plan Itinerary'), findsOneWidget);
    expect(find.text('Check-in'), findsOneWidget);
    expect(find.text('Get started with ATMOS-TRS in 5 simple steps'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet and mobile layouts do not overflow', (tester) async {
    await pumpSection(tester, const Size(800, 900));
    expect(tester.takeException(), isNull);
    await pumpSection(tester, const Size(390, 844));
    expect(find.text('01'), findsOneWidget);
    expect(find.text('05'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
