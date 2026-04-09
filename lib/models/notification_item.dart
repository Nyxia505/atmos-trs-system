/// Unified notification item for the Notification page.
/// Can represent a user-specific notification (from Firestore `notifications`)
/// or a general announcement (from Firestore `announcements`).
class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.createdAt,
    this.isRead = false,
    this.userId,
    this.isAnnouncement = false,
  });

  final String id;
  final String title;
  final String message;
  final String type;
  final DateTime createdAt;
  final bool isRead;
  final String? userId;
  final bool isAnnouncement;

  bool get isUnread => !isRead && !isAnnouncement;

  NotificationItem copyWith({bool? isRead}) {
    return NotificationItem(
      id: id,
      title: title,
      message: message,
      type: type,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
      userId: userId,
      isAnnouncement: isAnnouncement,
    );
  }
}
