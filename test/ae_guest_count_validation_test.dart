import 'package:atmos_trs_system/utils/ae_guest_count_validation.dart';
import 'package:atmos_trs_system/utils/php_currency_input.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AeGuestCountValidation', () {
    test('valid combinations', () {
      expect(
        AeGuestCountValidation.validate(guests: 4, female: 2, male: 2),
        isNull,
      );
      expect(
        AeGuestCountValidation.validate(guests: 4, female: 4, male: 0),
        isNull,
      );
      expect(
        AeGuestCountValidation.validate(guests: 4, female: 0, male: 4),
        isNull,
      );
    });

    test('female exceeds total', () {
      final err =
          AeGuestCountValidation.validate(guests: 4, female: 26, male: 0)!;
      expect(err.female, AeGuestCountValidation.femaleExceeds);
      expect(err.summary, AeGuestCountValidation.femaleExceeds);
    });

    test('sum mismatch uses a single section message', () {
      final err =
          AeGuestCountValidation.validate(guests: 4, female: 3, male: 2)!;
      expect(err.summaryOnly, AeGuestCountValidation.sumMismatch);
      expect(err.summary, AeGuestCountValidation.sumMismatch);
      expect(err.female, isNull);
      expect(err.male, isNull);
    });

    test('total zero invalid', () {
      final err =
          AeGuestCountValidation.validate(guests: 0, female: 0, male: 0)!;
      expect(err.guests, AeGuestCountValidation.guestsPositive);
    });

    test('parseWhole rejects decimals and negatives', () {
      expect(AeGuestCountValidation.parseWhole('4'), 4);
      expect(AeGuestCountValidation.parseWhole('4.5'), isNull);
      expect(AeGuestCountValidation.parseWhole('-1'), isNull);
      expect(AeGuestCountValidation.parseWhole(''), isNull);
    });

    test('complement fills the opposite gender', () {
      expect(
        AeGuestCountValidation.complement(total: 6, known: 2),
        4,
      );
      expect(
        AeGuestCountValidation.complement(total: 6, known: 1),
        5,
      );
      expect(
        AeGuestCountValidation.complement(total: 4, known: 4),
        0,
      );
      expect(
        AeGuestCountValidation.complement(total: 4, known: 6),
        isNull,
      );
    });
  });

  group('PhpCurrencyInput', () {
    test('formats with thousands separators and two decimals', () {
      expect(PhpCurrencyInput.format(500), '₱500.00');
      expect(PhpCurrencyInput.format(1000), '₱1,000.00');
      expect(PhpCurrencyInput.format(1500), '₱1,500.00');
      expect(PhpCurrencyInput.format(10000), '₱10,000.00');
      expect(PhpCurrencyInput.format(15000.50), '₱15,000.50');
      expect(PhpCurrencyInput.format(100000), '₱100,000.00');
    });

    test('parses formatted and raw amounts', () {
      expect(PhpCurrencyInput.tryParse('₱1,500.00'), 1500);
      expect(PhpCurrencyInput.tryParse('1500'), 1500);
      expect(PhpCurrencyInput.tryParse('15,000.50'), 15000.50);
      expect(PhpCurrencyInput.tryParse(''), 0);
      expect(PhpCurrencyInput.tryParse('-5'), isNull);
    });
  });
}
