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
  await tester.tap(find.textContaining('I have read and agree'));
  await tester.pumpAndSettle();
}

Future<void> _pickDropdown(
  WidgetTester tester,
  String hint,
  String value,
) async {
  await tester.ensureVisible(find.text(hint));
  await tester.tap(find.text(hint));
  await tester.pumpAndSettle();
  await tester.tap(find.text(value).last);
  await tester.pumpAndSettle();
}

Future<void> _fillPersonalDetails(WidgetTester tester) async {
  await tester.enterText(_fieldWithHint('enter your name'), 'Ana');
  await tester.enterText(_fieldWithHint('enter your last name'), 'Cruz');
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
}

Future<void> _fillPersonalInfo(WidgetTester tester) async {
  await tester.tap(find.text('Select your sex'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Female').last);
  await tester.pumpAndSettle();

  await tester.tap(find.text('Select nationality'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Filipino').last);
  await tester.pumpAndSettle();

  await _pickDropdown(tester, 'Month', 'June');
  await _pickDropdown(tester, 'Day', '15');
  await _pickDropdown(tester, 'Year', '1995');

  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
}

Future<void> _reachContactStep(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        splashFactory: InkRipple.splashFactory,
      ),
      routes: {
        '/login': (_) => const Scaffold(body: Text('Login page')),
      },
      home: const SignupScreen(),
    ),
  );
  await tester.pumpAndSettle();
  await _openLegalAndAgree(tester);
  await tester.tap(find.text('Next'));
  await tester.pumpAndSettle();
  await _fillPersonalDetails(tester);
  await _fillPersonalInfo(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('back arrow returns to previous signup step with data kept', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _reachContactStep(tester);
    expect(find.text('Contact & Address'), findsWidgets);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Personal Information'), findsOneWidget);
    expect(find.text('Female'), findsWidgets);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Basic Information'), findsOneWidget);
    expect(
      tester.widget<TextField>(_fieldWithHint('enter your name')).controller?.text,
      'Ana',
    );
    expect(
      tester
          .widget<TextField>(_fieldWithHint('enter your last name'))
          .controller
          ?.text,
      'Cruz',
    );
  });

  testWidgets('progress chips jump to completed steps and keep later values', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _reachContactStep(tester);
    await tester.enterText(
      _fieldWithHint('enter your email'),
      'ana@example.com',
    );
    await tester.pump();

    await tester.tap(find.text('Personal Details').first);
    await tester.pumpAndSettle();
    expect(find.text('Basic Information'), findsOneWidget);

    await tester.enterText(_fieldWithHint('enter your name'), 'Maria');
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('Personal Information'), findsOneWidget);
    expect(find.text('Female'), findsWidgets);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Contact & Address'), findsWidgets);
    expect(
      tester
          .widget<TextField>(_fieldWithHint('enter your email'))
          .controller
          ?.text,
      'ana@example.com',
    );
    expect(_fieldWithHint('enter your name'), findsNothing);
  });

  testWidgets('unvisited progress steps stay locked', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          splashFactory: InkRipple.splashFactory,
        ),
        home: const SignupScreen(),
      ),
    );
    await tester.pumpAndSettle();
    await _openLegalAndAgree(tester);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Basic Information'), findsOneWidget);

    await tester.tap(find.text('Contact & Address').first);
    await tester.pumpAndSettle();
    expect(find.text('Basic Information'), findsOneWidget);
    expect(find.text('Contact & Address'), findsWidgets);
  });

  testWidgets('Next re-validates after editing a previous step', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _reachContactStep(tester);
    await tester.tap(find.text('Personal Details').first);
    await tester.pumpAndSettle();

    await tester.enterText(_fieldWithHint('enter your name'), '');
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    expect(find.text('First name is required'), findsOneWidget);
    expect(find.text('Basic Information'), findsOneWidget);
  });

  testWidgets('leaving registration asks for confirmation', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          splashFactory: InkRipple.splashFactory,
        ),
        routes: {
          '/login': (_) => const Scaffold(body: Text('Login page')),
        },
        home: const SignupScreen(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Are you sure you want to leave registration? Your entered information may be lost.',
      ),
      findsOneWidget,
    );
    expect(find.text('Continue Registration'), findsOneWidget);
    expect(find.text('Leave Registration'), findsOneWidget);

    await tester.tap(find.text('Continue Registration'));
    await tester.pumpAndSettle();
    expect(find.text('Terms & Data Privacy'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave Registration'));
    await tester.pumpAndSettle();
    expect(find.text('Login page'), findsOneWidget);
  });
}
