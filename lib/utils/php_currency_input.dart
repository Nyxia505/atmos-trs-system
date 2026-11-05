/// Philippine Peso display helpers for AE register rate / charges fields.
///
/// UI shows values like `₱1,500.00`; storage stays a [double].
class PhpCurrencyInput {
  PhpCurrencyInput._();

  /// Formats a non-negative amount for display (always two decimal places).
  static String format(num amount) {
    final negative = amount < 0;
    final abs = amount.abs().toDouble();
    final fixed = abs.toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = _withCommas(parts[0]);
    final cents = parts.length > 1 ? parts[1] : '00';
    return '${negative ? '-' : ''}₱$whole.$cents';
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
      // Allow intermediate "1500." while typing via [tryParseLenient].
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
    var t = raw.trim().replaceAll('₱', '').replaceAll(',', '').replaceAll(' ', '');
    if (t.isEmpty) return 0;
    if (t.endsWith('.')) t = '${t}0';
    final v = double.tryParse(t);
    if (v == null || v.isNaN || v.isInfinite || v < 0) return null;
    return v;
  }

  static bool isValidNonNegative(String raw) => tryParse(raw) != null;

  static String _withCommas(String digits) {
    if (digits.isEmpty) return '0';
    final buf = StringBuffer();
    final chars = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final s = chars.isEmpty ? '0' : chars;
    for (var i = 0; i < s.length; i++) {
      final fromEnd = s.length - i;
      buf.write(s[i]);
      if (fromEnd > 1 && fromEnd % 3 == 1) buf.write(',');
    }
    return buf.toString();
  }
}
