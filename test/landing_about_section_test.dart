import 'package:atmos_trs_system/widgets/landing_about_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const stats = [
    LandingAboutStat(
      value: '…',
      label: 'Registered Tourists',
      icon: Icons.people_rounded,
    ),
    LandingAboutStat(
      value: '37',
      label: 'Tourist Spots',
      icon: Icons.place_rounded,
    ),
    LandingAboutStat(
      value: '17',
      label: 'Cities & Municipalities',
      icon: Icons.location_city_rounded,
    ),
    LandingAboutStat(
      value: '7',
      label: 'VR Tours',
      icon: Icons.vrpano_rounded,
    ),
  ];

  const body =
      'ATMOS-TRS — ATMOS-TRS - Asenso Tourismo Misamis Occidental Smart Tourist Registration System — is the official digital platform for tourism in Misamis Occidental. '
      'We provide seamless tourist registration, VR previews of destinations, itinerary planning, and QR check-ins at spots.\n\n'
      'Our mission is to connect visitors with local communities and create a sustainable, smart tourism ecosystem across the province.';

  Future<void> pumpAt(WidgetTester tester, Size size, {required bool compact, required bool tablet}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: size.width,
              child: LandingAboutShowcase(
                body: body,
                bodyStyle: const TextStyle(fontSize: 15, height: 1.5),
                titleSize: compact ? 28 : 38,
                capitol: const ColoredBox(color: Color(0xFFE2E8F0)),
                stats: stats,
                bleed: 16,
                compact: compact,
                tablet: tablet,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('desktop about section keeps copy, photo captions, and stats', (tester) async {
    await pumpAt(tester, const Size(1280, 900), compact: false, tablet: false);
    expect(find.text('ABOUT ATMOS-TRS'), findsOneWidget);
    expect(find.text('Provincial Governor'), findsOneWidget);
    expect(find.text('Misamis Occidental'), findsOneWidget);
    expect(find.text('Registered Tourists'), findsOneWidget);
    expect(find.text('…'), findsOneWidget);
    expect(find.text('17'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.textContaining('Our mission is to connect visitors'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home can hide the large numbers block and keep the about copy', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: LandingAboutShowcase(
              body: body,
              bodyStyle: const TextStyle(fontSize: 15, height: 1.5),
              titleSize: 38,
              capitol: const ColoredBox(color: Color(0xFFE2E8F0)),
              stats: stats,
              bleed: 16,
              compact: false,
              tablet: false,
              showNumbers: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('ABOUT ATMOS-TRS'), findsOneWidget);
    expect(find.text('By the '), findsNothing);
    expect(find.text('Registered Tourists'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet and mobile about layouts do not overflow', (tester) async {
    await pumpAt(tester, const Size(800, 1000), compact: false, tablet: true);
    expect(tester.takeException(), isNull);
    await pumpAt(tester, const Size(390, 900), compact: true, tablet: false);
    expect(find.text('Tourist Spots'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('registered tourists counts up and stays blank when unavailable', (tester) async {
    Future<void> pumpStats({
      int? liveCount,
      bool liveLoading = false,
      bool liveUnavailable = false,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LandingAboutShowcase(
                body: body,
                bodyStyle: const TextStyle(fontSize: 15, height: 1.5),
                titleSize: 38,
                capitol: const ColoredBox(color: Color(0xFFE2E8F0)),
                bleed: 16,
                compact: false,
                tablet: false,
                stats: [
                  LandingAboutStat(
                    value: '17',
                    label: 'Registered Tourists',
                    icon: Icons.people_rounded,
                    liveCount: liveCount,
                    liveLoading: liveLoading,
                    liveUnavailable: liveUnavailable,
                  ),
                  const LandingAboutStat(
                    value: '37',
                    label: 'Tourist Spots',
                    icon: Icons.place_rounded,
                  ),
                  const LandingAboutStat(
                    value: '17',
                    label: 'Cities & Municipalities',
                    icon: Icons.location_city_rounded,
                  ),
                  const LandingAboutStat(
                    value: '7',
                    label: 'VR Tours',
                    icon: Icons.vrpano_rounded,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpStats(liveLoading: true);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.text('37'), findsOneWidget);

    await pumpStats(liveUnavailable: true);
    await tester.pump();
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0'), findsNothing);

    await pumpStats(liveCount: 1500);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('1,500'), findsOneWidget);
    expect(find.text('37'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
