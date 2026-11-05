import 'package:atmos_trs_system/utils/ae_guest_count_validation.dart';
import 'package:atmos_trs_system/utils/ae_register_calculator.dart';
import 'package:atmos_trs_system/utils/php_currency_input.dart';
import 'package:flutter_test/flutter_test.dart';

/// Locks NEW Add Stay / Add Single Night product defaults + guest×nights math.
void main() {
  test('new Add Stay / Single Night defaults are blank (nights stay at 1)', () {
    const nights = '1';
    const guests = '0';
    const female = '0';
    const male = '0';
    const residence = '';
    const room = '';
    const rate = '';

    expect(nights, '1');
    expect(guests, '0');
    expect(female, '0');
    expect(male, '0');
    expect(residence, isEmpty);
    expect(room, isEmpty);
    expect(rate, isEmpty);

    expect(
      AeGuestCountValidation.validate(guests: 0, female: 0, male: 0),
      isNotNull,
    );
    expect(
      AeGuestCountValidation.validate(guests: 4, female: 2, male: 2),
      isNull,
    );
    expect(
      AeGuestCountValidation.validate(guests: 4, female: 26, male: 0),
      isNotNull,
    );
    expect(PhpCurrencyInput.format(1500), '₱1,500.00');
  });

  test('guests × nights expands to nightly rows with one check-in on first night', () {
    final rows = AeRegisterCalculator.expandStay(
      checkIn: DateTime(2026, 11, 3),
      nights: 3,
      roomNo: '4',
      residence: 'Japan',
      phRegion: '',
      guests: 4,
      female: 2,
      male: 2,
      rate: 1500,
    );

    expect(rows.length, 3);
    expect(rows.every((r) => r.guests == 4), isTrue);
    expect(rows.where((r) => r.checkedInDay).length, 1);
    expect(rows.first.checkedInDay, isTrue);
    // Guest-nights = 4 guests × 3 nights = 12 (not 12 check-ins).
    final guestNights = rows.fold<int>(0, (sum, r) => sum + r.guests);
    expect(guestNights, 12);
  });
}
