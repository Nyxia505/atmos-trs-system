import 'package:atmos_trs_system/services/spot_category_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('collapses spaces and rejects blank or All', () {
    expect(SpotCategoryNames.cleaned('  Eco   Park  '), 'Eco Park');
    expect(SpotCategoryNames.cleaned(' '), isNull);
    expect(SpotCategoryNames.cleaned('A'), isNull);
    expect(SpotCategoryNames.cleaned('All'), isNull);
    expect(SpotCategoryNames.cleaned('all'), isNull);
  });

  test('duplicate check ignores capitalization and spacing', () {
    expect(
      SpotCategoryNames.canonicalMatch('  beach ', SpotCategoryService.builtIn),
      'Beach',
    );
    expect(
      SpotCategoryNames.canonicalMatch('ECO PARK', const ['Eco Park']),
      'Eco Park',
    );
    expect(
      SpotCategoryNames.keyOf('Eco Park'),
      SpotCategoryNames.keyOf('eco   park'),
    );
    expect(
      SpotCategoryNames.canonicalMatch('Cave', SpotCategoryService.builtIn),
      isNull,
    );
  });

  test('merge keeps built-in names and adds a custom one once', () {
    final merged = SpotCategoryNames.merge(
      saved: const ['Cave', 'beach', 'Cave'],
      fromSpots: const ['Eco Park', 'Falls'],
    );
    expect(merged.first, 'Beach');
    expect(merged.where((name) => name.toLowerCase() == 'beach'), ['Beach']);
    expect(merged, contains('Cave'));
    expect(merged, contains('Eco Park'));
    expect(merged.where((name) => name == 'Cave'), hasLength(1));
  });
}
