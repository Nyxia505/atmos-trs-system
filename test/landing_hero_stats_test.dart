import 'package:atmos_trs_system/widgets/landing_hero_stats.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pumpPanel(WidgetTester tester, List<LandingStatEntry> entries) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LandingHeroStatsPanel(entries: entries, onClose: () {}),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('shows a loader instead of a made-up total', (tester) async {
    await pumpPanel(tester, const [
      LandingStatEntry(
        label: 'Registered Tourists',
        icon: Icons.people_rounded,
        status: LandingStatStatus.loading,
      ),
    ]);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.text('Registered Tourists'), findsOneWidget);
  });

  testWidgets('shows an em dash when a total is unavailable', (tester) async {
    await pumpPanel(tester, const [
      LandingStatEntry(
        label: 'Tourist Spots',
        icon: Icons.place_rounded,
        status: LandingStatStatus.unavailable,
      ),
    ]);
    expect(find.text('—'), findsOneWidget);
    expect(find.text('Public totals are unavailable right now.'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });

  testWidgets('formats a real count', (tester) async {
    await pumpPanel(tester, const [
      LandingStatEntry(
        label: 'Registered Tourists',
        icon: Icons.people_rounded,
        status: LandingStatStatus.ready,
        value: 1500,
      ),
      LandingStatEntry(
        label: 'VR Tours',
        icon: Icons.vrpano_rounded,
        status: LandingStatStatus.ready,
        value: 3,
      ),
    ]);
    expect(find.text('1,500'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
