import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/utils/municipality_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hides municipalities that already have an office', () {
    final all = getMisamisOccidentalMunicipalities();
    final open = municipalitiesWithoutOffice(all, ['oroquieta', 'ozamis']);

    expect(open.map((m) => m.id), isNot(contains('oroquieta')));
    expect(open.map((m) => m.id), isNot(contains('ozamiz')));
    expect(open.map((m) => m.id), contains('tangub'));
    expect(open.length, all.length - 2);
  });

  test('empty office list leaves every municipality available', () {
    final all = getMisamisOccidentalMunicipalities();
    expect(municipalitiesWithoutOffice(all, const []), all);
  });
}
