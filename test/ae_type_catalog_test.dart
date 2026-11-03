import 'package:atmos_trs_system/config/ae_register_schema.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dropdown keeps official types and lets hotels add extras', () {
    final options = AeTypeCatalog.dropdownOptions(
      current: 'Glamping',
      extras: const ['Farm stay', 'Hotel', 'glamping'],
    );
    expect(options, containsAll(['Hotel', 'Resort', 'Tourist Inn', 'Others']));
    expect(options, contains('Glamping'));
    expect(options, contains('Farm stay'));
    expect(options.where((t) => t.toLowerCase() == 'hotel').length, 1);
    expect(options.last, 'Others');
  });

  test('custom types map to OTH unless they match a DOT name', () {
    expect(AeTypeCatalog.codeFor('Glamping'), 'OTH');
    expect(AeTypeCatalog.codeFor('hotel'), 'HTL');
    expect(AeTypeCatalog.parseExtras(['Glamping', 'Hotel', '  ']), ['Glamping']);
  });
}
