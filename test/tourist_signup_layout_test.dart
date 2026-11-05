import 'package:atmos_trs_system/screens/signup_screen.dart';
import 'package:atmos_trs_system/utils/logo_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData _theme() {
  return ThemeData(
    useMaterial3: true,
    splashFactory: InkRipple.splashFactory,
  );
}

Future<void> _pumpSignup(WidgetTester tester, {Size size = const Size(390, 844)}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: _theme(),
      home: const SignupScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openLegalAndAgree(WidgetTester tester) async {
  for (final title in const [
    'Data Privacy (RA 10173)',
    'Terms and Conditions',
  ]) {
    await tester.ensureVisible(find.text(title));
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    final views = find.byType(SingleChildScrollView);
    if (views.evaluate().isNotEmpty) {
      await tester.drag(views.last, const Offset(0, -800));
      await tester.pumpAndSettle();
    }
  }
  await tester.ensureVisible(find.textContaining('I have read and agree'));
  await tester.tap(find.textContaining('I have read and agree'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Next'));
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('header shows centered original logo without ATMOS wordmark', (
    tester,
  ) async {
    await _pumpSignup(tester, size: const Size(390, 844));

    expect(find.byType(TransparentLogo), findsWidgets);
    expect(find.text('Step 1'), findsOneWidget);
    expect(find.text('Registration'), findsOneWidget);
    expect(find.text('ATMOS-TRS'), findsNothing);
    expect(find.text('Explore Misamis Occidental'), findsNothing);
    expect(find.text('Personal Details'), findsOneWidget);
    expect(find.text('Personal Info'), findsOneWidget);
    expect(find.text('Contact & Address'), findsWidgets);
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('step 1 basic info helper, login, and fields stay intact', (
    tester,
  ) async {
    await _pumpSignup(tester, size: const Size(390, 844));
    await _openLegalAndAgree(tester);

    expect(find.byType(TransparentLogo), findsWidgets);
    expect(find.text('Step 1'), findsOneWidget);
    expect(find.text('Basic Information'), findsOneWidget);
    expect(
      find.text('Enter your name as it appears on your valid ID.'),
      findsOneWidget,
    );
    expect(find.textContaining('Already have an account?'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    expect(
      find.textContaining('First Name', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Middle Initial', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Last Name', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
  });

  testWidgets('all three steps keep headings, logo, and entered names', (
    tester,
  ) async {
    await _pumpSignup(tester, size: const Size(800, 2400));
    await _openLegalAndAgree(tester);

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'enter your name',
      ),
      'Ana',
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is TextField && w.decoration?.hintText == 'enter your last name',
      ),
      'Cruz',
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Step 2'), findsOneWidget);
    expect(find.text('Personal Information'), findsOneWidget);
    expect(find.byType(TransparentLogo), findsWidgets);
    expect(find.text('ATMOS-TRS'), findsNothing);

    await tester.tap(find.text('Select your sex'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Female').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select nationality'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filipino').last);
    await tester.pumpAndSettle();

    Future<void> pick(String hint, String value) async {
      await tester.ensureVisible(find.text(hint));
      await tester.tap(find.text(hint));
      await tester.pumpAndSettle();
      await tester.tap(find.text(value).last);
      await tester.pumpAndSettle();
    }

    await pick('Month', 'June');
    await pick('Day', '15');
    await pick('Year', '1995');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Step 3'), findsOneWidget);
    expect(find.text('Contact & Address'), findsWidgets);
    expect(find.byType(TransparentLogo), findsWidgets);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Personal Information'), findsOneWidget);
    expect(find.text('Female'), findsWidgets);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Basic Information'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byWidgetPredicate(
              (w) =>
                  w is TextField && w.decoration?.hintText == 'enter your name',
            ),
          )
          .controller
          ?.text,
      'Ana',
    );
  });
}
