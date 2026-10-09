import 'package:shared_preferences/shared_preferences.dart';

/// How long a scanned-but-unfinished QR check-in stays pending.
const Duration kPendingQrScanTtl = Duration(hours: 24);

Future<void> markPendingQrSaved(SharedPreferences prefs, String key) =>
    prefs.setInt(key, DateTime.now().millisecondsSinceEpoch);

/// True when the pending scan stamped at [key] is older than [kPendingQrScanTtl].
/// Scans saved before timestamps existed start their clock now.
Future<bool> isPendingQrExpired(SharedPreferences prefs, String key) async {
  final savedAt = prefs.getInt(key);
  if (savedAt == null) {
    await markPendingQrSaved(prefs, key);
    return false;
  }
  final age = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(savedAt),
  );
  return age > kPendingQrScanTtl;
}
