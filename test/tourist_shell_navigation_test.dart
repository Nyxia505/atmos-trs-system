import 'package:atmos_trs_system/features/navigation/main_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveTouristShellBack', () {
    test('pops the tab stack before leaving the tab', () {
      expect(
        resolveTouristShellBack(currentTabCanPop: true, currentIndex: 0),
        TouristShellBackResult.popTabRoute,
      );
      expect(
        resolveTouristShellBack(currentTabCanPop: true, currentIndex: 2),
        TouristShellBackResult.popTabRoute,
      );
    });

    test('returns to Home when the active tab is already at its root', () {
      expect(
        resolveTouristShellBack(currentTabCanPop: false, currentIndex: 1),
        TouristShellBackResult.goHomeTab,
      );
    });

    test('leaves the app from the Home dashboard', () {
      expect(
        resolveTouristShellBack(currentTabCanPop: false, currentIndex: 0),
        TouristShellBackResult.exitApp,
      );
    });
  });

  testWidgets('spot details stay above a shared bottom bar', (tester) async {
    final tabNav = GlobalKey<NavigatorState>();
    var selected = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: IndexedStack(
                index: selected,
                children: [
                  Navigator(
                    key: tabNav,
                    onGenerateRoute: (settings) {
                      return MaterialPageRoute<void>(
                        settings: settings,
                        builder: (routeContext) => Center(
                          child: TextButton(
                            onPressed: () {
                              Navigator.of(routeContext).push<void>(
                                MaterialPageRoute<void>(
                                  builder: (_) => const Text('Spot details'),
                                ),
                              );
                            },
                            child: const Text('Open Bless Amare'),
                          ),
                        ),
                      );
                    },
                  ),
                  const Center(child: Text('Scan tab')),
                ],
              ),
              bottomNavigationBar: Row(
                children: [
                  TextButton(
                    onPressed: () => setState(() => selected = 0),
                    child: const Text('Home'),
                  ),
                  TextButton(
                    onPressed: () => setState(() => selected = 1),
                    child: const Text('Scan'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('Open Bless Amare'));
    await tester.pumpAndSettle();
    expect(find.text('Spot details'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);

    await tester.tap(find.text('Scan'));
    await tester.pumpAndSettle();
    expect(find.text('Scan tab'), findsOneWidget);
    expect(find.text('Spot details'), findsNothing);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Spot details'), findsOneWidget);
  });

  testWidgets('re-selecting a tab pops back to its dashboard', (tester) async {
    final tabNav = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Navigator(
            key: tabNav,
            onGenerateRoute: (settings) {
              return MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => const Text('Home dashboard'),
              );
            },
          ),
        ),
      ),
    );

    tabNav.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const Text('Spot details'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Spot details'), findsOneWidget);

    tabNav.currentState!.popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();
    expect(find.text('Home dashboard'), findsOneWidget);
    expect(find.text('Spot details'), findsNothing);
  });
}
