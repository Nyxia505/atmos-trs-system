import 'package:flutter/foundation.dart';
import 'package:atmos_trs_system/services/announcement_notification_sync.dart';

/// Global unread notification count for bottom nav / sidebar badges (Facebook-style).
class NotificationBadgeNotifier extends ChangeNotifier {
  NotificationBadgeNotifier._();

  static final NotificationBadgeNotifier instance =
      NotificationBadgeNotifier._();

  int _count = 0;
  int get count => _count;

  Future<void> refresh({String? userId}) async {
    final next = await AnnouncementNotificationSync.unreadCount(userId: userId);
    if (_count != next) {
      _count = next;
      notifyListeners();
    }
  }
}
