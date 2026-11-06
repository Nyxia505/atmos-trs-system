/// Shared Active / published checks for `tourist_spots` documents.
///
/// LGU stores visibility as [status] (`Active` / `Inactive`). Legacy docs with
/// a missing status are treated as Active so existing catalogs keep working.
bool isTouristSpotActiveStatus(String? status) {
  final s = (status ?? '').trim().toLowerCase();
  if (s.isEmpty) return true;
  if (s == 'active' || s == 'published') return true;
  return false;
}

bool isTouristSpotActiveMap(Map<String, dynamic>? data) {
  if (data == null) return false;
  final raw = data['status'] ?? data['Status'];
  return isTouristSpotActiveStatus(raw?.toString());
}
