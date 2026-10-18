import 'package:atmos_trs_system/screens/signup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Future<void> _openAndRead(WidgetTester tester, String title) async {
  await tester.ensureVisible(find.text(title));
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
  expect(find.text('Tap to close'), findsWidgets);
  final views = find.byType(SingleChildScrollView);
  if (views.evaluate().isNotEmpty) {
    await tester.drag(views.last, const Offset(0, -800));
    await tester.pumpAndSettle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('tourist legal step explains tap, read, then agree', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('Step 1: Tap each section below to read the policies.'),
      findsOneWidget,
    );
    expect(find.text('Tap to read'), findsNWidgets(2));
    expect(find.text('Step 2: Check the box below to agree and continue.'), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsNothing);

    await tester.ensureVisible(find.text('Next'));
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(
      find.textContaining('Tap Data Privacy and Terms and Conditions'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    await _openAndRead(tester, 'Data Privacy (RA 10173)');
    expect(find.text('Read'), findsOneWidget);
    expect(find.text('Step 2: Check the box below to agree and continue.'), findsNothing);

    await _openAndRead(tester, 'Terms and Conditions');
    expect(find.text('Read'), findsNWidgets(2));
    expect(
      find.text('Step 2: Check the box below to agree and continue.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check_rounded), findsNothing);

    await tester.ensureVisible(find.textContaining('I have read and agree'));
    await tester.tap(find.textContaining('I have read and agree'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Basic Information'), findsOneWidget);
  });

  testWidgets('legal arrows stay still when motion is reduced', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: SignupScreen()),
      ),
    );
    await tester.pump();
    expect(find.text('Tap to read'), findsNWidgets(2));
    expect(tester.hasRunningAnimations, isFalse);
  });
}
