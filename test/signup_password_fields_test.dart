import 'package:atmos_trs_system/screens/establishment_signup_screen.dart';
import 'package:atmos_trs_system/screens/signup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Finder _fieldWithHint(String hint) {
  return find.byWidgetPredicate((widget) {
    if (widget is! TextField) return false;
    return widget.decoration?.hintText == hint;
  });
}

Future<void> _openLegalAndAgree(
  WidgetTester tester, {
  bool scrollToEnd = false,
}) async {
  for (final title in const [
    'Data Privacy (RA 10173)',
    'Terms and Conditions',
  ]) {
    await tester.ensureVisible(find.text(title));
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
    if (scrollToEnd) {
      final views = find.byType(SingleChildScrollView);
      if (views.evaluate().isNotEmpty) {
        await tester.drag(views.last, const Offset(0, -800));
        await tester.pumpAndSettle();
      }
    }
  }
  await tester.tap(find.textContaining('I have read and agree'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('establishment passwords stay editable after a mismatch', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: EstablishmentSignupScreen()),
    );
    await tester.pumpAndSettle();

    await _openLegalAndAgree(tester);
    await tester.tap(find.text('Continue to registration'));
    await tester.pumpAndSettle();

    final password = _fieldWithHint('At least 6 characters');
    final confirm = _fieldWithHint('Confirm your password');
    await tester.ensureVisible(password);
    await tester.enterText(password, 'secret1');
    await tester.pump();
    await tester.ensureVisible(confirm);
    await tester.enterText(confirm, 'secret2');
    await tester.pump();

    expect(find.text('Passwords do not match.'), findsOneWidget);

    await tester.enterText(password, 'secret2');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Passwords do not match.'), findsNothing);
    expect(tester.widget<TextField>(password).controller?.text, 'secret2');
    expect(tester.widget<TextField>(confirm).enabled, isTrue);
    expect(tester.widget<TextField>(password).readOnly, isFalse);
    expect(tester.widget<TextField>(confirm).readOnly, isFalse);

    await tester.enterText(confirm, 'secret3');
    await tester.pump();
    expect(find.text('Passwords do not match.'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create account')).onPressed, isNotNull);
  });

  testWidgets('tourist passwords stay editable after a mismatch', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MaterialApp(home: SignupScreen()));
    await tester.pumpAndSettle();

    await _openLegalAndAgree(tester, scrollToEnd: true);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    await tester.enterText(_fieldWithHint('enter your name'), 'Ana');
    await tester.enterText(_fieldWithHint('enter your last name'), 'Cruz');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select your sex'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Female').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select nationality'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Filipino').last);
    await tester.pumpAndSettle();

    Future<void> pickDropdown(String hint, String value) async {
      await tester.ensureVisible(find.text(hint));
      await tester.tap(find.text(hint));
      await tester.pumpAndSettle();
      await tester.tap(find.text(value).last);
      await tester.pumpAndSettle();
    }

    await pickDropdown('Month', 'June');
    await pickDropdown('Day', '15');
    await pickDropdown('Year', '1995');

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    final password = _fieldWithHint('enter your password');
    final confirm = _fieldWithHint('confirm your password');
    await tester.ensureVisible(password);
    await tester.enterText(password, 'secret12');
    await tester.pump();
    await tester.ensureVisible(confirm);
    await tester.enterText(confirm, 'secret99');
    await tester.pump();

    expect(find.text('Passwords do not match'), findsOneWidget);

    await tester.enterText(password, 'secret99');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Passwords do not match'), findsNothing);
    expect(tester.widget<TextField>(password).controller?.text, 'secret99');
    expect(tester.widget<TextField>(password).readOnly, isFalse);
    expect(tester.widget<TextField>(confirm).readOnly, isFalse);
    expect(tester.widget<TextField>(confirm).enabled, isTrue);
  });
}
