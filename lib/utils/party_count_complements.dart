/// Party-size complements for DOT demographics (Male/Female, Filipino/Foreign).
///
/// Rule: `known + complement == total` (clamped). Used across AE confirm,
/// tourist party forms, and any future party UX.
abstract final class PartyCountComplements {
  /// `total - known`, floored at 0. If [known] &gt; [total], returns 0
  /// (caller should clamp [known] to [total] via [clampKnown]).
  static int complement(int total, int known) {
    final t = total < 0 ? 0 : total;
    final k = known < 0 ? 0 : known;
    final c = t - k;
    return c < 0 ? 0 : c;
  }

  /// Clamps [known] into `0..total`.
  static int clampKnown(int total, int known) {
    final t = total < 0 ? 0 : total;
    if (known < 0) return 0;
    if (known > t) return t;
    return known;
  }

  /// True when both sides are non-negative and sum to [total].
  static bool sumsToTotal(int total, int a, int b) {
    final t = total < 1 ? 1 : total;
    return a >= 0 && b >= 0 && a + b == t;
  }

  /// Prefill male/female from a tourist sex label for party size 1.
  static ({int male, int female}) sexPairFromLabel(String? sex, {int partySize = 1}) {
    final p = partySize < 1 ? 1 : partySize;
    final s = (sex ?? '').trim().toLowerCase();
    if (s.startsWith('m')) return (male: p, female: 0);
    if (s.startsWith('f')) return (male: 0, female: p);
    return (male: 0, female: 0);
  }

  /// Prefill Filipino/foreign from local flags / country / nationality.
  static ({int filipino, int foreign}) residencyPair({
    bool? isLocal,
    String? localOrForeign,
    String? country,
    String? nationality,
    int partySize = 1,
  }) {
    final p = partySize < 1 ? 1 : partySize;
    final lor = (localOrForeign ?? '').trim().toLowerCase();
    if (lor.contains('foreign')) return (filipino: 0, foreign: p);
    if (lor.contains('local') || lor.contains('domestic')) {
      return (filipino: p, foreign: 0);
    }
    if (isLocal == true) return (filipino: p, foreign: 0);
    if (isLocal == false) return (filipino: 0, foreign: p);

    final c = (country ?? '').trim().toLowerCase();
    final n = (nationality ?? '').trim().toLowerCase();
    final philippine = c.contains('philippine') ||
        c == 'ph' ||
        c == 'phl' ||
        n.contains('filipino') ||
        n.contains('philippine');
    if (philippine) return (filipino: p, foreign: 0);
    if (c.isNotEmpty || n.isNotEmpty) return (filipino: 0, foreign: p);
    return (filipino: 0, foreign: 0);
  }
}
