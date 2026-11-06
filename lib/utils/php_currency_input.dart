import 'package:flutter/services.dart';

/// Philippine Peso display helpers for AE register rate / charges fields.
///
/// UI shows thousand separators (and optional `₱`); storage stays a [double].
class PhpCurrencyInput {
  PhpCurrencyInput._();

  /// Formats a non-negative amount for display (always two decimal places + ₱).
  static String format(num amount) {
    final negative = amount < 0;
    final abs = amount.abs().toDouble();
    final fixed = abs.toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = _withCommas(parts[0]);
    final cents = parts.length > 1 ? parts[1] : '00';
    return '${negative ? '-' : ''}₱$whole.$cents';
  }

  /// Same as [format] but without the ₱ glyph (field decorations often add it).
  static String formatPlain(num amount) {
    final negative = amount < 0;
    final abs = amount.abs().toDouble();
    final fixed = abs.toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = _withCommas(parts[0]);
    final cents = parts.length > 1 ? parts[1] : '00';
    return '${negative ? '-' : ''}$whole.$cents';
  }

  /// Live typing display: commas on the integer part, keep partial decimals.
  /// Does not force `.00` while the user is still typing.
  static String formatWhileTyping(String raw) {
    final cleaned = raw.trim().replaceAll('₱', '').replaceAll(' ', '');
    if (cleaned.isEmpty) return '';

    final negative = cleaned.startsWith('-');
    var body = negative ? cleaned.substring(1) : cleaned;
    body = body.replaceAll(',', '');
    if (body.isEmpty) return negative ? '-' : '';

    // Keep only digits and at most one decimal point.
    final buf = StringBuffer();
    var seenDot = false;
    var fracLen = 0;
    for (var i = 0; i < body.length; i++) {
      final ch = body[i];
      if (ch == '.') {
        if (seenDot) continue;
        seenDot = true;
        buf.write('.');
        continue;
      }
      if (ch.compareTo('0') < 0 || ch.compareTo('9') > 0) continue;
      if (seenDot) {
        if (fracLen >= 2) continue;
        fracLen++;
      }
      buf.write(ch);
    }
    body = buf.toString();
    if (body.isEmpty || body == '.') {
      return negative ? '-${body == '.' ? '0.' : ''}' : (body == '.' ? '0.' : '');
    }

    final parts = body.split('.');
    var wholeDigits = parts[0].replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (wholeDigits.isEmpty) wholeDigits = '0';
    final whole = _withCommas(wholeDigits);

    if (parts.length == 1) {
      return '${negative ? '-' : ''}$whole';
    }
    final frac = parts[1].length > 2 ? parts[1].substring(0, 2) : parts[1];
    // Preserve trailing dot while typing ("1250.").
    if (body.endsWith('.') && frac.isEmpty) {
      return '${negative ? '-' : ''}$whole.';
    }
    return '${negative ? '-' : ''}$whole.$frac';
  }

  /// Strips ₱ / commas / spaces and parses a non-negative amount.
  /// Empty → 0. Invalid → null.
  static double? tryParse(String raw) {
    var t = raw.trim();
    if (t.isEmpty) return 0;
    t = t.replaceAll('₱', '').replaceAll(',', '').replaceAll(' ', '');
    if (t.startsWith('+')) t = t.substring(1);
    if (t.isEmpty) return 0;
    if (!RegExp(r'^\d+(\.\d{0,2})?$').hasMatch(t) &&
        !RegExp(r'^\d+\.$').hasMatch(t)) {
      final v = double.tryParse(t);
      if (v == null || v.isNaN || v.isInfinite || v < 0) return null;
      return v;
    }
    final v = double.tryParse(t);
    if (v == null || v.isNaN || v.isInfinite || v < 0) return null;
    return v;
  }

  /// Lenient parse for on-change typing (allows trailing `.`).
  static double? tryParseLenient(String raw) {
    var t =
        raw.trim().replaceAll('₱', '').replaceAll(',', '').replaceAll(' ', '');
    if (t.isEmpty) return 0;
    if (t.endsWith('.')) t = '${t}0';
    final v = double.tryParse(t);
    if (v == null || v.isNaN || v.isInfinite || v < 0) return null;
    return v;
  }

  static bool isValidNonNegative(String raw) => tryParse(raw) != null;

  static String _withCommas(String digits) {
    if (digits.isEmpty) return '0';
    final chars = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final s = chars.isEmpty ? '0' : chars;
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      buf.write(s[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
    }
    return buf.toString();
  }
}

/// Inserts thousand separators while typing; keeps cursor on the edited digit.
///
/// Does not force `.00` until blur/save formatting. Decimal part max 2 digits.
class PhpCurrencyTextInputFormatter extends TextInputFormatter {
  const PhpCurrencyTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text;
    if (raw.trim().isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    // Count significant chars (digits + at most one '.') before the caret.
    final caret = newValue.selection.baseOffset.clamp(0, raw.length);
    final significantBefore = _significantCount(raw.substring(0, caret));

    final formatted = PhpCurrencyInput.formatWhileTyping(raw);
    if (formatted == newValue.text &&
        newValue.selection.isCollapsed &&
        newValue.selection.baseOffset == caret) {
      return newValue;
    }

    final newCaret = _offsetForSignificantCount(formatted, significantBefore);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newCaret),
    );
  }

  static int _significantCount(String s) {
    var n = 0;
    var seenDot = false;
    for (final ch in s.split('')) {
      if (ch == '.') {
        if (!seenDot) {
          seenDot = true;
          n++;
        }
        continue;
      }
      if (ch.compareTo('0') >= 0 && ch.compareTo('9') <= 0) n++;
    }
    return n;
  }

  static int _offsetForSignificantCount(String formatted, int target) {
    if (target <= 0) return 0;
    var n = 0;
    var seenDot = false;
    for (var i = 0; i < formatted.length; i++) {
      final ch = formatted[i];
      if (ch == '.') {
        if (!seenDot) {
          seenDot = true;
          n++;
        }
      } else if (ch.compareTo('0') >= 0 && ch.compareTo('9') <= 0) {
        n++;
      } else {
        continue;
      }
      if (n >= target) return i + 1;
    }
    return formatted.length;
  }
}
