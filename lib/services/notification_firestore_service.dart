import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:atmos_trs_system/models/notification_item.dart';

const String _notificationsCollection = 'notifications';
const String _announcementsCollection = 'announcements';

/// Firestore-based notifications: user-specific notifications and general announcements.
class NotificationFirestoreService {
  NotificationFirestoreService._();

  static bool get _isFirebaseInitialized {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// Creates a welcome notification for a user after sign-up.
  static Future<void> createWelcomeNotification(String userId) async {
    if (!_isFirebaseInitialized || userId.isEmpty) return;
    try {
      await _firestore.collection(_notificationsCollection).add({
        'user_id': userId,
        'title': 'Welcome to ATMOS!',
        'message': 'Thank you for signing up.',
        'type': 'welcome',
        'created_at': FieldValue.serverTimestamp(),
        'is_read': false,
      });
    } catch (e) {
      // Ignore; notification is best-effort
      assert(true, 'createWelcomeNotification: $e');
    }
  }

  /// Creates a check-in notification after successful QR check-in.
  static Future<void> createCheckInNotification(String userId, String spotName) async {
    if (!_isFirebaseInitialized || userId.isEmpty) return;
    try {
      final message = spotName.trim().isNotEmpty
          ? 'Check-in successful! You checked in at $spotName.'
          : 'Check-in successful! Your visit has been recorded.';
      await _firestore.collection(_notificationsCollection).add({
        'user_id': userId,
        'title': 'Check-in recorded',
        'message': message,
        'type': 'checkin',
        'created_at': FieldValue.serverTimestamp(),
        'is_read': false,
      });
    } catch (e) {
      assert(true, 'createCheckInNotification: $e');
    }
  }

  /// Fetches user-specific notifications for [userId], newest first.
  static Future<List<NotificationItem>> getUserNotifications(String userId) async {
    if (!_isFirebaseInitialized || userId.isEmpty) return [];
    try {
      final snapshot = await _firestore
          .collection(_notificationsCollection)
          .where('user_id', isEqualTo: userId)
          .limit(50)
          .get();
      final list = snapshot.docs.map((d) => _docToNotificationItem(d, isAnnouncement: false)).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (e) {
      return [];
    }
  }

  /// Fetches published announcements, newest first.
  static Future<List<NotificationItem>> getAnnouncements() async {
    if (!_isFirebaseInitialized) return [];
    try {
      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await _firestore
            .collection(_announcementsCollection)
            .where('published', isEqualTo: true)
            .orderBy('createdAt', descending: true)
            .limit(30)
            .get();
      } catch (_) {
        snapshot = await _firestore
            .collection(_announcementsCollection)
            .where('published', isEqualTo: true)
            .limit(30)
            .get();
      }
      final list = snapshot.docs.map(_announcementDocToItem).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (e) {
      return [];
    }
  }

  /// Merges user notifications and announcements and sorts by newest first.
  static Future<List<NotificationItem>> getMergedNotifications(String? userId) async {
    final List<NotificationItem> list = [];
    if (userId != null && userId.isNotEmpty) {
      list.addAll(await getUserNotifications(userId));
    }
    list.addAll(await getAnnouncements());
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Marks a user notification as read.
  static Future<void> markAsRead(String notificationId) async {
    if (!_isFirebaseInitialized || notificationId.isEmpty) return;
    try {
      await _firestore.collection(_notificationsCollection).doc(notificationId).update({'is_read': true});
    } catch (_) {}
  }

  static NotificationItem _docToNotificationItem(DocumentSnapshot<Map<String, dynamic>> d, {required bool isAnnouncement}) {
    final data = d.data() ?? {};
    final created = data['created_at'];
    DateTime createdAt = DateTime.now();
    if (created is Timestamp) {
      createdAt = created.toDate();
    } else if (created is DateTime) {
      createdAt = created;
    }
    return NotificationItem(
      id: d.id,
      title: data['title'] as String? ?? 'Notification',
      message: data['message'] as String? ?? '',
      type: data['type'] as String? ?? 'general',
      createdAt: createdAt,
      isRead: data['is_read'] as bool? ?? false,
      userId: data['user_id'] as String?,
      isAnnouncement: isAnnouncement,
    );
  }

  static NotificationItem _announcementDocToItem(DocumentSnapshot<Map<String, dynamic>> d) {
    final data = d.data() ?? {};
    final created = data['createdAt'] ?? data['created_at'];
    DateTime createdAt = DateTime.now();
    if (created is Timestamp) {
      createdAt = created.toDate();
    } else if (created is DateTime) {
      createdAt = created;
    }
    final message = data['content'] as String? ?? data['message'] as String? ?? '';
    return NotificationItem(
      id: d.id,
      title: data['title'] as String? ?? 'Announcement',
      message: message,
      type: data['type'] as String? ?? 'General',
      createdAt: createdAt,
      isRead: true,
      userId: null,
      isAnnouncement: true,
    );
  }
}
