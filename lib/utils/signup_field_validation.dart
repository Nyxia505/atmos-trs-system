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
  if (digits.length == 10 && digits.startsWith('9')) {
    return null;
  }
  if (digits.length == 12 && digits.startsWith('639')) {
    return null;
  }
  return 'Use a real PH mobile: 09XXXXXXXXX (11 digits, e.g. 09171234567).';
}

/// Tourist signup contact number for a selected dial code (local digits only).
///
/// For `+63`, local part must be `9XXXXXXXXX` (10 digits) — no leading `0`
/// because the country code is already chosen in the dial selector.
String? validateMobileForDialCode(String? raw, String dialCode) {
  if (raw == null || raw.trim().isEmpty) {
    return 'Required';
  }
  final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
  final code = dialCode.trim();
  if (code == '+63') {
    if (digits.startsWith('0')) {
      return 'Skip the 0 — start with 9 (e.g. 9171234567).';
    }
    if (digits.length == 10 && digits.startsWith('9')) {
      return null;
    }
    return 'Enter 10 digits starting with 9 (e.g. 9171234567).';
  }
  if (code == '+1') {
    if (digits.length == 10) return null;
    return 'Enter a 10-digit US/Canada number.';
  }
  if (digits.length < 7 || digits.length > 15) {
    return 'Enter a valid phone number (7–15 digits).';
  }
  return null;
}

/// Default dial code from residence country name.
String dialCodeForCountry(String? country) {
  final c = (country ?? '').trim();
  if (c.isEmpty) return '+63';
  const map = <String, String>{
    'Philippines': '+63',
    'United States': '+1',
    'Canada': '+1',
    'United Kingdom': '+44',
    'Australia': '+61',
    'China': '+86',
    'Japan': '+81',
    'South Korea': '+82',
    'Singapore': '+65',
    'Malaysia': '+60',
    'Indonesia': '+62',
    'Thailand': '+66',
    'Vietnam': '+84',
    'India': '+91',
    'France': '+33',
    'Germany': '+49',
    'Italy': '+39',
    'Spain': '+34',
    'United Arab Emirates': '+971',
    'Saudi Arabia': '+966',
    'New Zealand': '+64',
    'Hong Kong': '+852',
    'Taiwan': '+886',
  };
  return map[c] ?? '+63';
}

/// Common dial codes shown in signup mobile selectors (all roles).
const List<String> kSignupDialCodes = <String>[
  '+63',
  '+1',
  '+44',
  '+61',
  '+81',
  '+82',
  '+65',
  '+60',
  '+62',
  '+66',
  '+84',
  '+86',
  '+91',
  '+33',
  '+49',
  '+39',
  '+34',
  '+64',
  '+852',
  '+886',
  '+971',
  '+966',
];

/// Alias kept for existing tourist signup references.
const List<String> kTouristSignupDialCodes = kSignupDialCodes;

/// Dial options list including [current] if it is not already in [kSignupDialCodes].
List<String> dialCodeOptionsFor(String current) {
  final code = current.trim().isEmpty ? '+63' : current.trim();
  if (kSignupDialCodes.contains(code)) return List<String>.from(kSignupDialCodes);
  return <String>[code, ...kSignupDialCodes];
}

/// Local digits + dial code → E.164-style value for save / SMS helpers.
String composeE164Mobile(String dialCode, String localRaw) {
  var digits = localRaw.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty) return '';
  final code = dialCode.trim().isEmpty ? '+63' : dialCode.trim();
  if (code == '+63') {
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (digits.startsWith('63') && digits.length >= 12) {
      return '+$digits';
    }
    return '+63$digits';
  }
  return '$code$digits';
}

/// Split a stored E.164 / local mobile into dial code + local digits.
({String dialCode, String localDigits}) parseStoredMobile(String saved) {
  final raw = saved.trim();
  if (raw.isEmpty) {
    return (dialCode: '+63', localDigits: '');
  }
  var digits = raw.replaceAll(RegExp(r'[^\d]'), '');
  var dialCode = '+63';
  if (raw.startsWith('+') && digits.length > 1) {
    String? matched;
    for (final code in kSignupDialCodes) {
      final codeDigits = code.replaceAll('+', '');
      if (digits.startsWith(codeDigits) &&
          (matched == null || codeDigits.length > matched.length)) {
        matched = codeDigits;
      }
    }
    if (matched != null) {
      dialCode = '+$matched';
      digits = digits.substring(matched.length);
    }
  } else if (digits.startsWith('63') && digits.length >= 12) {
    dialCode = '+63';
    digits = digits.substring(2);
  }
  if (dialCode == '+63' && digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  return (dialCode: dialCode, localDigits: digits);
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

/// City for non-PH residence (foreign nationals or Filipinos living abroad).
String? validateInternationalCity(String? v) {
  if (v == null || v.trim().isEmpty) {
    return 'City is required.';
  }
  final s = v.trim();
  if (s.length < 2) {
    return 'Enter your city (at least 2 characters).';
  }
  if (s.length > 80) {
    return 'City name is too long.';
  }
  if (!RegExp(r'[a-zA-Z\u00C0-\u024FñÑ]').hasMatch(s)) {
    return 'Use letters for the city name.';
  }
  return null;
}

/// Staff / reset flows: 8+ chars with upper, lower, and a digit.
bool isPasswordStrongEnough(String pw) {
  if (pw.length < 8) return false;
  return RegExp(r'[A-Z]').hasMatch(pw) &&
      RegExp(r'[a-z]').hasMatch(pw) &&
      RegExp(r'[0-9]').hasMatch(pw);
}

String? validateStrongPassword(String? value) {
  if (value == null || value.isEmpty) {
    return 'Please enter a password';
  }
  if (value.length < 8) {
    return 'Password must be at least 8 characters';
  }
  if (!isPasswordStrongEnough(value)) {
    return 'Use at least 8 characters including uppercase, lowercase, and a number';
  }
  return null;
}

/// Tourist signup only: length ≥ 8; no upper/lower/digit/special rules.
String? validateTouristSignupPassword(String? value) {
  if (value == null || value.isEmpty) {
    return 'Please enter a password';
  }
  if (value.length < 8) {
    return 'Password must be at least 8 characters';
  }
  return null;
}

/// State / province / region outside the Philippines.
String? validateInternationalRegion(String? v) {
  if (v == null || v.trim().isEmpty) {
    return 'State / province / region is required.';
  }
  final s = v.trim();
  if (s.length < 2) {
    return 'Enter at least 2 characters.';
  }
  if (s.length > 80) {
    return 'Name is too long.';
  }
  return null;
}
