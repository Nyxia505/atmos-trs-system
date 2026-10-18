import 'package:atmos_trs_system/widgets/save_spot_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a new save replaces the previous notice with that destination', (
    tester,
  ) async {
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
