// Stricter signup checks for PH mobile and address fields (reduce junk data).

/// Philippine mobile: `09XXXXXXXXX` (11 digits) or `639XXXXXXXXX` (12 digits, no +).
String? validatePhilippineMobile(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return 'Required';
  }
  final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.length == 11 && digits.startsWith('09')) {
    return null;
  }
  if (digits.length == 12 && digits.startsWith('639')) {
    return null;
  }
  return 'Use a real PH mobile: 09XXXXXXXXX (11 digits, e.g. 09171234567).';
}

/// Barangay: required, letters, not placeholder junk.
String? validatePhilippineBarangay(String? v) {
  if (v == null || v.trim().isEmpty) {
    return 'Barangay is required.';
  }
  final s = v.trim();
  if (s.length < 3) {
    return 'Enter your complete barangay (at least 3 characters).';
  }
  if (s.length > 80) {
    return 'Barangay name is too long.';
  }
  if (!RegExp(r'[a-zA-Z\u00C0-\u024FñÑ]').hasMatch(s)) {
    return 'Use letters for the barangay name.';
  }
  final lower = s.toLowerCase();
  const blocked = <String>{
    'n/a',
    'na',
    'none',
    'null',
    'test',
    'xxx',
    'asdf',
    'qwerty',
    'barangay',
    'tbd',
    'tba',
    'unknown',
    '-',
    '.',
  };
  if (blocked.contains(lower)) {
    return 'Enter your real barangay name.';
  }
  final compact = lower.replaceAll(RegExp(r'\s'), '');
  if (compact.length >= 3 && RegExp(r'^(.)\1{2,}$').hasMatch(compact)) {
    return 'Enter your real barangay name.';
  }
  return null;
}

/// Street / house details: required, minimum detail, not placeholder junk.
String? validatePhilippineStreet(String? v) {
  if (v == null || v.trim().isEmpty) {
    return 'Street / house number is required.';
  }
  final s = v.trim();
  if (s.length < 5) {
    return 'Enter a complete address (e.g. house no. + street or purok).';
  }
  if (s.length > 120) {
    return 'Address is too long.';
  }
  if (!RegExp(r'[a-zA-Z\u00C0-\u024FñÑ0-9]').hasMatch(s)) {
    return 'Use letters and numbers for your street address.';
  }
  final lower = s.toLowerCase();
  const blocked = <String>{
    'n/a',
    'none',
    'null',
    'test',
    'xxx',
    'asdf',
    'qwerty',
    'tbd',
    'tba',
    'unknown',
    'address',
    'street',
    'here',
    'somewhere',
  };
  if (blocked.contains(lower)) {
    return 'Enter your real street or house address.';
  }
  final letters = RegExp(r'[a-zA-Z\u00C0-\u024FñÑ]').allMatches(s).length;
  if (letters < 2) {
    return 'Add more detail (street name, purok, or sitio).';
  }
  return null;
}
