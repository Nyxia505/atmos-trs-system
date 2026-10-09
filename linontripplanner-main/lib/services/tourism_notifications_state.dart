import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data.dart';

/// Unread tracking for in-app notifications (Firestore announcements + events).
///
/// Push alerts on devices still come from FCM (`tourism_events` topic); this
/// state powers the Notifications tab and the home nav badge.
class TourismNotificationsState extends ChangeNotifier {
  TourismNotificationsState._();

  static final TourismNotificationsState instance =
      TourismNotificationsState._();

  static const _readIdsPrefsKey = 'tourism_notification_read_ids_v1';

  final Set<String> _readIds = {};
  bool _loadedPrefs = false;

  /// Stable id for a feed item (announcement or event).
  static String idForFeedItem(TourismNewsFeedItem item) {
    return switch (item) {
      TourismNewsFeedAnnouncement(:final announcement) =>
        'announcement:${announcement.id}',
      TourismNewsFeedEvent(:final event) => 'event:${event.id}',
    };
  }

  Future<void> ensureLoaded() async {
    if (_loadedPrefs) return;
    final sp = await SharedPreferences.getInstance();
    _readIds
      ..clear()
      ..addAll(sp.getStringList(_readIdsPrefsKey) ?? const []);
    _loadedPrefs = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_readIdsPrefsKey, _readIds.toList(growable: false));
  }

  /// Current receivable notifications: public announcements + events, newest first.
  List<TourismNewsFeedItem> get feed => buildNewsFeedItemsSorted();

  int get unreadCount {
    var n = 0;
    for (final item in feed) {
      if (!_readIds.contains(idForFeedItem(item))) n++;
    }
    return n;
  }

  bool isUnread(TourismNewsFeedItem item) =>
      !_readIds.contains(idForFeedItem(item));

  Future<void> markRead(TourismNewsFeedItem item) async {
    final id = idForFeedItem(item);
    if (_readIds.contains(id)) return;
    _readIds.add(id);
    notifyListeners();
    await _persist();
  }

  Future<void> markAllRead() async {
    final before = _readIds.length;
    for (final item in feed) {
      _readIds.add(idForFeedItem(item));
    }
    if (_readIds.length == before) return;
    notifyListeners();
    await _persist();
  }

  /// Call after Firestore announcements/events finish loading.
  void refreshFromCatalog() => notifyListeners();
}

/// Bottom nav / app bar bell with unread count badge.
class TourismNotificationNavIcon extends StatelessWidget {
  const TourismNotificationNavIcon({
    super.key,
    required this.count,
    this.active = false,
    this.iconSize = 24,
  });

  final int count;
  final bool active;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      active ? Icons.notifications_rounded : Icons.notifications_outlined,
      size: iconSize,
    );
    if (count <= 0) return icon;

    final label = count > 99 ? '99+' : '$count';
    return Badge(
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
      backgroundColor: AppColors.primary,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      offset: const Offset(6, -4),
      child: icon,
    );
  }
}
