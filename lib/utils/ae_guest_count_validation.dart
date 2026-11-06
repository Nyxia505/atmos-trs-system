/// Guest headcount rules for AE DOT Daily Register (Add Stay / Add Single Night).
///
/// Female + Male must equal Total Guests. Counts are whole numbers only.
/// Prefer [complement] so the opposite gender is derived while typing.
class AeGuestCountValidation {
  AeGuestCountValidation._();

  static const femaleExceeds = 'Female guests cannot exceed total guests.';
  static const maleExceeds = 'Male guests cannot exceed total guests.';
  static const sumMismatch =
      'Female and male guests must equal the total number of guests.';
  static const guestsPositive = 'Total guests must be a positive whole number.';
  static const femaleNonNegative =
      'Female guests must be a non-negative whole number.';
  static const maleNonNegative =
      'Male guests must be a non-negative whole number.';

  /// Which gender the user last edited — drives Total Guests recalculation.
  static const focusNone = 'none';
  static const focusFemale = 'female';
  static const focusMale = 'male';

  /// Remaining guests of the other gender, or null when [known] exceeds [total].
  /// Never returns a negative value.
  static int? complement({required int total, required int known}) {
    if (total < 0 || known < 0) return null;
    if (known > total) return null;
    return total - known;
  }

  /// Result of validating guests / female / male fields.
  static AeGuestCountErrors? validate({
    required int? guests,
    required int? female,
    required int? male,
    bool requireParsed = true,
  }) {
    if (guests == null) {
      return requireParsed
          ? const AeGuestCountErrors(guests: guestsPositive)
          : null;
    }
    if (female == null) {
      return requireParsed
          ? const AeGuestCountErrors(female: femaleNonNegative)
          : null;
    }
    if (male == null) {
      return requireParsed
          ? const AeGuestCountErrors(male: maleNonNegative)
          : null;
    }
    if (guests < 1) {
      return const AeGuestCountErrors(guests: guestsPositive);
    }
    if (female < 0) {
      return const AeGuestCountErrors(female: femaleNonNegative);
    }
    if (male < 0) {
      return const AeGuestCountErrors(male: maleNonNegative);
    }
    if (female > guests) {
      return const AeGuestCountErrors(female: femaleExceeds);
    }
    if (male > guests) {
      return const AeGuestCountErrors(male: maleExceeds);
    }
    if (female + male != guests) {
      return const AeGuestCountErrors(summaryOnly: sumMismatch);
    }
    return null;
  }

  /// Parses a digit-only field; empty / non-integer → null.
  static int? parseWhole(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    if (!RegExp(r'^\d+$').hasMatch(t)) return null;
    return int.tryParse(t);
  }
}

class AeGuestCountErrors {
  const AeGuestCountErrors({
    this.guests,
    this.female,
    this.male,
    this.summaryOnly,
  });

  final String? guests;
  final String? female;
  final String? male;

  /// Prefer a single section banner (avoids duplicating the same text under both genders).
  final String? summaryOnly;

  bool get hasError =>
      (guests != null && guests!.isNotEmpty) ||
      (female != null && female!.isNotEmpty) ||
      (male != null && male!.isNotEmpty) ||
      (summaryOnly != null && summaryOnly!.isNotEmpty);

  /// One concise line for the Guest Count section / StateError.
  String get summary =>
      summaryOnly ??
      guests ??
      female ??
      male ??
      AeGuestCountValidation.sumMismatch;
}
