import 'package:atmos_trs_system/utils/php_currency_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PhpCurrencyInput.formatWhileTyping', () {
    test('inserts commas while typing whole amounts', () {
      expect(PhpCurrencyInput.formatWhileTyping('100'), '100');
      expect(PhpCurrencyInput.formatWhileTyping('1000'), '1,000');
      expect(PhpCurrencyInput.formatWhileTyping('1500'), '1,500');
      expect(PhpCurrencyInput.formatWhileTyping('10000'), '10,000');
      expect(PhpCurrencyInput.formatWhileTyping('150000'), '150,000');
      expect(PhpCurrencyInput.formatWhileTyping('1000000'), '1,000,000');
    });

    test('keeps two decimal places without forcing trailing zeros', () {
      expect(PhpCurrencyInput.formatWhileTyping('1250.5'), '1,250.5');
      expect(PhpCurrencyInput.formatWhileTyping('1250.50'), '1,250.50');
      expect(PhpCurrencyInput.formatWhileTyping('1250.'), '1,250.');
    });

    test('strips currency glyph and reformats', () {
      expect(PhpCurrencyInput.formatWhileTyping('₱1500'), '1,500');
      expect(PhpCurrencyInput.formatWhileTyping('1,500'), '1,500');
    });
  });

  group('PhpCurrencyInput parse/store', () {
    test('tryParse ignores commas and peso sign', () {
      expect(PhpCurrencyInput.tryParse('1,500'), 1500);
      expect(PhpCurrencyInput.tryParse('₱1,250.50'), 1250.50);
      expect(PhpCurrencyInput.tryParse('10,000.00'), 10000);
    });

    test('formatPlain is round-trippable with tryParse', () {
      final shown = PhpCurrencyInput.formatPlain(1500);
      expect(shown, '1,500.00');
      expect(PhpCurrencyInput.tryParse(shown), 1500);
    });
  });

  group('PhpCurrencyTextInputFormatter', () {
    const formatter = PhpCurrencyTextInputFormatter();

    TextEditingValue apply(String oldText, String newText, {int caret = -1}) {
      final old = TextEditingValue(
        text: oldText,
        selection: TextSelection.collapsed(offset: oldText.length),
      );
      final neu = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: caret < 0 ? newText.length : caret,
        ),
      );
      return formatter.formatEditUpdate(old, neu);
    }

    test('formats 1000 to 1,000 as the user types', () {
      final v = apply('100', '1000');
      expect(v.text, '1,000');
      expect(v.selection.isCollapsed, isTrue);
      expect(v.selection.baseOffset, v.text.length);
    });

    test('keeps caret after the edited digit when commas appear', () {
      // User had "1,000" and inserts 5 before the first 0 → raw "15000"
      // Significant digits before caret after typing at end of "15000": 5
      final v = apply('1,000', '15000');
      expect(v.text, '15,000');
      expect(v.selection.baseOffset, v.text.length);
    });

    test('allows decimal entry', () {
      final v = apply('1,250', '1,250.5');
      expect(v.text, '1,250.5');
    });
  });
}
