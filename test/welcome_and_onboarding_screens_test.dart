import 'package:atmos_trs_system/screens/mobile_onboarding_screen.dart';
import 'package:atmos_trs_system/screens/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Welcome shows headline and the three entry buttons', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: WelcomeScreen()));
    await tester.pump();

    expect(find.text('Discover Misamis Occidental'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
    expect(find.text('Sign Up'), findsOneWidget);
  });

  testWidgets('onboarding slides use the tourism copy and skip control', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MobileOnboardingScreen()));
    await tester.pump();

    expect(find.text('Explore Misamis Occidental'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.textContaining('VR 360'), findsNothing);
  });
}
