import 'package:atmos_trs_system/config/user_profile_storage.dart';
import 'package:atmos_trs_system/services/notification_badge_notifier.dart';
import 'package:atmos_trs_system/services/notification_firestore_service.dart';
import 'package:atmos_trs_system/services/user_activity_service.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

/// Ensures new tourists receive a one-time welcome notification (local + Firestore).
class WelcomeNotificationService {
  WelcomeNotificationService._();

  static String localWelcomeId(String uid) => 'welcome_$uid';

  static String _prefsKey(String uid) => 'welcome_notif_created_$uid';

  static String displayFirstName(String? firstName) {
    final name = firstName?.trim();
    if (name != null &&
        name.isNotEmpty &&
        name.toLowerCase() != 'guest' &&
        name.toLowerCase() != 'n/a') {
      return name;
    }
    return 'explorer';
  }

  static ({String title, String message}) welcomeCopy(String? firstName) {
    final name = displayFirstName(firstName);
    return (
      title: 'Welcome, $name! 👋',
      message:
          'Salamat sa pag-register sa ATMOS-TRS! Explore destinations sa '
          'Misamis Occidental, gamita ang imong QR code para mag-check in, '
          'ug i-enjoy ang imong digital tourist ID. Happy travels!',
    );
  }

  /// Creates the welcome notification once per account (idempotent).
  static Future<void> ensureForUser({
    required String uid,
    String? firstName,
  }) async {
    if (uid.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefsKey(uid)) == true) return;

    final resolvedName =
        firstName?.trim().isNotEmpty == true
            ? firstName
            : UserProfileStorage.cachedProfile?.firstName;
    final copy = welcomeCopy(resolvedName);
    final stableId = localWelcomeId(uid);

    final existing = await UserActivityService.getNotifications();
    if (existing.any((n) => n.id == stableId)) {
      await prefs.setBool(_prefsKey(uid), true);
      return;
    }

    await UserActivityService.addNotificationIfAbsent(
      id: stableId,
      title: copy.title,
      message: copy.message,
      type: NotificationType.welcome,
    );

    try {
      await NotificationFirestoreService.createWelcomeNotification(
        uid,
        firstName: resolvedName,
      );
    } catch (e) {
      debugPrint('[WelcomeNotificationService] Firestore welcome (non-fatal): $e');
    }

    await prefs.setBool(_prefsKey(uid), true);
    await NotificationBadgeNotifier.instance.refresh(userId: uid);
  }
}
