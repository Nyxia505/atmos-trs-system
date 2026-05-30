import 'package:uuid/uuid.dart';

/// Province-based tourist ID codes (e.g. Misamis Occidental → `MO-XXXXXXXX`).
class TouristIdHelper {
  TouristIdHelper._();

  static const _uuid = Uuid();

  /// First letters of province words (Misamis Occidental → MO).
  static String provincePrefix(String? province) {
    final p = (province ?? '').trim().toLowerCase();
    if (p.isEmpty) return 'MO';

    if (p.contains('misamis') &&
        (p.contains('occidental') || p == 'misocc' || p.contains('misocc'))) {
      return 'MO';
    }

    final words = p
        .split(RegExp(r'[\s,]+'))
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty && w != 'of' && w != 'city')
        .toList();
    if (words.isEmpty) return 'MO';

    final buffer = StringBuffer();
    for (final word in words) {
      buffer.write(word[0].toUpperCase());
      if (buffer.length >= 2) break;
    }
    final prefix = buffer.toString();
    if (prefix.isEmpty) return 'MO';
    return prefix.length > 3 ? prefix.substring(0, 3) : prefix;
  }

  /// New registration ID: `{provincePrefix}-{8 hex}` e.g. `MO-B1CFA9DD`.
  static String generate({required String province}) {
    final prefix = provincePrefix(province);
    return '$prefix-${_uuid.v4().substring(0, 8).toUpperCase()}';
  }

  /// `MO-…`, `ATMOS-…`, or similar formatted IDs.
  static bool isFormattedTouristId(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return false;
    return RegExp(r'^[A-Z]{1,4}-[A-Z0-9]{6,12}$').hasMatch(v);
  }

  /// Firebase Auth UID / Firestore doc id — not shown as tourist ID.
  static bool looksLikeFirebaseUid(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return false;
    if (isFormattedTouristId(v)) return false;
    return v.length >= 20;
  }

  /// Display ID for dashboards (never raw Firebase UID).
  static String displayForTourist(Map<String, dynamic> tourist) {
    final stored = tourist['touristId']?.toString().trim() ?? '';
    if (isFormattedTouristId(stored)) return stored;
    if (stored.startsWith('ATMOS-') && stored.length > 6) return stored;

    final province = tourist['province']?.toString() ?? '';
    return '${provincePrefix(province)}-PENDING';
  }
}
