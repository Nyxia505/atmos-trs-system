import 'package:flutter_test/flutter_test.dart';
import 'package:atmos_trs_system/utils/party_count_complements.dart';

void main() {
  group('PartyCountComplements', () {
    test('complement balances to party size', () {
      expect(PartyCountComplements.complement(10, 6), 4);
      expect(PartyCountComplements.complement(10, 10), 0);
      expect(PartyCountComplements.complement(10, 12), 0);
      expect(PartyCountComplements.clampKnown(10, 12), 10);
    });

    test('sumsToTotal', () {
      expect(PartyCountComplements.sumsToTotal(10, 6, 4), isTrue);
      expect(PartyCountComplements.sumsToTotal(10, 6, 5), isFalse);
    });

    test('sexPairFromLabel', () {
      expect(
        PartyCountComplements.sexPairFromLabel('Female'),
        (male: 0, female: 1),
      );
      expect(
        PartyCountComplements.sexPairFromLabel('Male', partySize: 1),
        (male: 1, female: 0),
      );
    });

    test('residencyPair from Philippines', () {
      final r = PartyCountComplements.residencyPair(
        country: 'Philippines',
        nationality: 'Filipino',
      );
      expect(r.filipino, 1);
      expect(r.foreign, 0);
    });
  });
}
