import 'package:atmos_trs_system/features/governor/widgets/charts/governor_donut_chart.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fl_chart gap index -1 is never used as a list index', () {
    expect(governorDonutTouchedIndex(-1, 5), isNull);
    expect(governorDonutTouchedIndex(null, 5), isNull);
    expect(governorDonutTouchedIndex(5, 5), isNull);
    expect(governorDonutTouchedIndex(0, 0), isNull);
    expect(governorDonutTouchedIndex(0, 2), 0);
    expect(governorDonutTouchedIndex(1, 2), 1);
  });
}
