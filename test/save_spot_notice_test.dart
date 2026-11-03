import 'package:atmos_trs_system/widgets/save_spot_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(SaveSpotNotice.resetForTest);
  tearDown(SaveSpotNotice.resetForTest);

  testWidgets('a new save replaces the previous notice with that destination', (
    tester,
  ) async {
    addTearDown(SaveSpotNotice.resetForTest);
    final observer = SaveSpotNoticeNavigatorObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: const _NoticeHarness(),
      ),
    );

    await tester.tap(find.text('Save Aloran'));
    await tester.pump();
    expect(find.text('Aloran Viewpoint saved!'), findsOneWidget);

    await tester.tap(find.text('Save Jimenez'));
    await tester.pump();
    expect(find.text('Aloran Viewpoint saved!'), findsNothing);
    expect(find.text('Jimenez Church saved!'), findsOneWidget);

    await tester.tap(find.text('Open other screen'));
    await tester.pumpAndSettle();
    expect(find.text('Jimenez Church saved!'), findsNothing);
  });

  testWidgets('the notice dismisses itself after two seconds', (tester) async {
    addTearDown(SaveSpotNotice.resetForTest);
    await tester.pumpWidget(
      const MaterialApp(home: _NoticeHarness()),
    );

    await tester.tap(find.text('Save Aloran'));
    await tester.pump();
    expect(find.text('Aloran Viewpoint saved!'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);

    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(bar.duration, SaveSpotNotice.displayDuration);
    expect(bar.behavior, SnackBarBehavior.floating);
    expect(bar.showCloseIcon, isFalse);
    expect(bar.margin, isNotNull);

    await tester.pump(SaveSpotNotice.displayDuration);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Aloran Viewpoint saved!'), findsNothing);
  });

  testWidgets('rapid identical saves do not stack notices', (tester) async {
    addTearDown(SaveSpotNotice.resetForTest);
    await tester.pumpWidget(
      const MaterialApp(home: _NoticeHarness()),
    );

    await tester.tap(find.text('Save Aloran'));
    await tester.pump();
    await tester.tap(find.text('Save Aloran'));
    await tester.pump();
    expect(find.text('Aloran Viewpoint saved!'), findsOneWidget);
    await tester.pump(SaveSpotNotice.displayDuration);
    await tester.pump(const Duration(milliseconds: 400));
  });
}

class _NoticeHarness extends StatelessWidget {
  const _NoticeHarness();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            onPressed: () =>
                SaveSpotNotice.show(context, 'Aloran Viewpoint saved!'),
            child: const Text('Save Aloran'),
          ),
          TextButton(
            onPressed: () =>
                SaveSpotNotice.show(context, 'Jimenez Church saved!'),
            child: const Text('Save Jimenez'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('Other screen')),
                ),
              );
            },
            child: const Text('Open other screen'),
          ),
        ],
      ),
    );
  }
}
