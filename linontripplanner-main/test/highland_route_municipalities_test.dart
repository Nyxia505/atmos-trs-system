import 'package:flutter_test/flutter_test.dart';
import 'package:trip_plan/data.dart';
import 'package:trip_plan/municipal_road_distances.dart';

Municipality? _byName(String name) {
  for (final m in municipalities) {
    if (m.name == name || m.shortName == name) return m;
  }
  return null;
}

void main() {
  test('Highland Oroquieta → Concepcion lists all towns, not only bus hubs', () {
    final start = _byName('Oroquieta City (Provincial Capital)') ??
        _byName('Oroquieta City');
    final end = _byName('Concepcion');
    expect(start, isNotNull);
    expect(end, isNotNull);

    final options = roadRouteOptionsBetween(start!, end!);
    final highland = options
        .where((o) => o.direction == RoadRouteDirection.highland)
        .firstOrNull;
    expect(highland, isNotNull, reason: 'Highland option should exist');

    final names = highland!.municipalities.map((m) => m.name).toList();
    expect(names.first, start.name);
    expect(names.last, end.name);
    // Must include interior highland corridor towns, not collapse to 2 hubs.
    expect(names.length, greaterThan(2));
    expect(
      names.any((n) => n.contains('Bonifacio') || n.contains('Don Victoriano')),
      isTrue,
    );
    // Names are municipalities, not bus stop/terminal labels.
    for (final n in names) {
      expect(n.toLowerCase(), isNot(contains('bus stop')));
      expect(n.toLowerCase(), isNot(contains('bus terminal')));
    }
  });

  test('Coastal route also returns full municipality path when available', () {
    final start = _byName('Oroquieta City (Provincial Capital)') ??
        _byName('Oroquieta City');
    final end = _byName('Ozamiz City');
    expect(start, isNotNull);
    expect(end, isNotNull);

    final options = roadRouteOptionsBetween(start!, end!);
    final coastal = options
        .where((o) => o.direction == RoadRouteDirection.coastal)
        .firstOrNull;
    if (coastal == null) return; // Only one sensible way for some pairs.
    final names = coastal.municipalities.map((m) => m.name).toList();
    expect(names.first, start.name);
    expect(names.last, end.name);
    expect(names.length, greaterThanOrEqualTo(2));
  });
}
