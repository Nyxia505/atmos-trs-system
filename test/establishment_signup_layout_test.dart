import 'package:atmos_trs_system/screens/establishment_signup_screen.dart';
import 'package:atmos_trs_system/utils/logo_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

ThemeData _testTheme() {
  return ThemeData(
    useMaterial3: true,
    splashFactory: InkRipple.splashFactory,
  );
}

Future<void> _pumpSignup(
  WidgetTester tester, {
  Size size = const Size(800, 2400),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: _testTheme(),
      home: const EstablishmentSignupScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapInScroll(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    400,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  final top = tester.getRect(finder).top;
  if (top < 88) {
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 100));
    await tester.pumpAndSettle();
  }
  await tester.tap(finder);
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
  }
  await tester.ensureVisible(find.textContaining('I have read and agree'));
  await tester.tap(find.textContaining('I have read and agree'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Continue to registration'));
  await tester.tap(find.text('Continue to registration'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('signup shows logo-only branding and four form sections', (
    tester,
  ) async {
    await _pumpSignup(tester, size: const Size(390, 844));
    await _openLegalAndAgree(tester);

    expect(find.byType(TransparentLogo), findsWidgets);
    expect(find.text('Tourism Establishment Signup'), findsOneWidget);
    expect(find.text('Register your tourism business.'), findsOneWidget);
    expect(find.text('Register your business for ATMOS-TRS'), findsNothing);
    expect(find.textContaining('Asenso Turismo'), findsNothing);
    expect(find.text('ATMOS TRS'), findsNothing);

    expect(find.text('Business Details'), findsOneWidget);
    expect(find.text('Contact Details'), findsOneWidget);
    expect(find.text('Location'), findsOneWidget);
    expect(find.text('Account Setup'), findsOneWidget);
    expect(find.text('+ Add New Category'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Name of Business'), findsOneWidget);
    expect(find.text('Category Type'), findsOneWidget);
    expect(find.text('Municipality / City'), findsOneWidget);
    expect(find.text('Barangay'), findsOneWidget);
    expect(find.text('Map Pin / Get Location'), findsOneWidget);
  });

  testWidgets('suggest category rejects empty and duplicate official names', (
    tester,
  ) async {
    await _pumpSignup(tester);
    await _openLegalAndAgree(tester);

    await _tapInScroll(tester, find.text('+ Add New Category'));

    expect(find.text('Suggest a category'), findsOneWidget);
    await tester.tap(find.text('Use this category'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a category name.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Hotel');
    await tester.tap(find.text('Use this category'));
    await tester.pumpAndSettle();
    expect(find.textContaining('already on the official list'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Homestay');
    await tester.tap(find.text('Use this category'));
    await tester.pumpAndSettle();

    expect(find.text('Suggest a category'), findsNothing);
    expect(find.textContaining('pending OPTACA review'), findsOneWidget);
    expect(find.textContaining('Homestay'), findsWidgets);
  });

  testWidgets('existing official category can still be selected', (
    tester,
  ) async {
    await _pumpSignup(tester);
    await _openLegalAndAgree(tester);

    await _tapInScroll(tester, find.text('Select your category'));
    await tester.tap(find.text('Resort').last);
    await tester.pumpAndSettle();

    expect(find.text('Resort'), findsWidgets);
    expect(find.textContaining('pending OPTACA review'), findsNothing);
  });
}
