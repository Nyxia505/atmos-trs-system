/// Visitor headcount stored on a QR check-in document.
///
/// [partySize] / [visitorCount] = companions + 1 (the scanning tourist).
/// Missing or invalid values count as 1 so older check-ins stay compatible.
int checkInVisitorCount(Map<String, dynamic> checkIn) {
  final raw = checkIn['visitorCount'] ??
      checkIn['partySize'] ??
      checkIn['visitor_count'] ??
      checkIn['party_size'];
  if (raw is int) return raw > 0 ? raw : 1;
  if (raw is num) {
    final n = raw.round();
    return n > 0 ? n : 1;
  }
  if (raw is String) {
    final n = int.tryParse(raw.trim());
    if (n != null && n > 0) return n;
  }
  return 1;
}

/// Total visitors across a list of check-in maps (sums party sizes).
int sumCheckInVisitors(Iterable<Map<String, dynamic>> checkIns) {
  var total = 0;
  for (final c in checkIns) {
    total += checkInVisitorCount(c);
  }
  return total;
}
