import 'package:flutter/material.dart';

import 'data.dart';
import 'event_datetime_format.dart';
import 'firestore_loader.dart';
import 'widgets/municipality_image.dart';
import 'services/tourism_notifications_state.dart';
import 'widgets/tourism_events_calendar.dart' show openTourismEventDetail;
import 'widgets/tourism_plan_ui.dart';

/// Fetches every notification a tourist can receive: Firestore announcements
/// and events (new events can also arrive as FCM push).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  final _notifState = TourismNotificationsState.instance;

  @override
  void initState() {
    super.initState();
    _notifState.addListener(_onNotifStateChanged);
    tourismEventsRevision.addListener(_onNotifStateChanged);
    _load();
  }

  @override
  void dispose() {
    _notifState.removeListener(_onNotifStateChanged);
    tourismEventsRevision.removeListener(_onNotifStateChanged);
    super.dispose();
  }

  void _onNotifStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await Future.wait([
        _notifState.ensureLoaded(),
        loadEventsFromFirestore(),
        loadAnnouncementsFromFirestore(),
      ]);
      _notifState.refreshFromCatalog();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _dateLine(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _relativeTime(DateTime at) {
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    }
    return _dateLine(at);
  }

  Future<void> _openNewsItemDetail(TourismNewsFeedItem item) async {
    await _notifState.markRead(item);
    if (!mounted) return;
    switch (item) {
      case TourismNewsFeedAnnouncement(:final announcement):
        _openAnnouncementDetail(announcement);
      case TourismNewsFeedEvent(:final event):
        openTourismEventDetail(context, event);
    }
  }

  void _openAnnouncementDetail(TourismAnnouncement a) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.35,
        maxChildSize: 0.92,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                a.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _dateLine(a.publishedAt),
                style: const TextStyle(fontSize: 14, color: AppColors.textGrey),
              ),
              const SizedBox(height: 12),
              if (a.body.isNotEmpty)
                Text(
                  a.body,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    color: AppColors.textDark,
                  ),
                ),
              if (a.imagePath.isNotEmpty) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: buildMunicipalityImage(
                      a.imagePath,
                      fallback: Container(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        child: const Center(
                          child: Icon(
                            Icons.campaign_outlined,
                            color: AppColors.primary,
                            size: 48,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feed = _notifState.feed;
    final unread = _notifState.unreadCount;

    return Scaffold(
      backgroundColor: AppColors.planPageBg,
      appBar: AppBar(
        centerTitle: false,
        title: Row(
          children: [
            const Text('Notifications'),
            if (unread > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$unread',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: unread > 0 ? _notifState.markAllRead : null,
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: TourismPlanPageBody(
        child: RefreshIndicator(
          onRefresh: _load,
          color: AppColors.primary,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: TourismPlanCard(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: TourismPlanUi.primaryGradient,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.notifications_active_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                unread > 0
                                    ? '$unread unread notification${unread == 1 ? '' : 's'}'
                                    : 'You\'re all caught up',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textDark,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                feed.isEmpty
                                    ? 'Announcements and events will appear here'
                                    : '${feed.length} notification${feed.length == 1 ? '' : 's'}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textGrey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                )
              else if (feed.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: TourismEmptyState(
                    icon: Icons.notifications_none_rounded,
                    message:
                        'No notifications yet.\nWhen admins post announcements '
                        'or events, they will show up here.',
                    topPadding: 24,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = feed[index];
                        final unreadItem = _notifState.isUnread(item);
                        switch (item) {
                          case TourismNewsFeedAnnouncement(:final announcement):
                            return _announcementCard(
                              announcement,
                              unreadItem,
                            );
                          case TourismNewsFeedEvent(:final event):
                            return _eventCard(event, unreadItem, item);
                        }
                      },
                      childCount: feed.length,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _announcementCard(TourismAnnouncement a, bool unread) {
    final item = TourismNewsFeedAnnouncement(a);
    return TourismFeedCard(
      onTap: () => _openNewsItemDetail(item),
      image: a.imagePath.isNotEmpty
          ? AspectRatio(
              aspectRatio: 16 / 9,
              child: buildMunicipalityImage(
                a.imagePath,
                fallback: Container(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  child: const Center(
                    child: Icon(
                      Icons.campaign_outlined,
                      color: AppColors.primary,
                      size: 40,
                    ),
                  ),
                ),
              ),
            )
          : null,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  a.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: unread ? FontWeight.w800 : FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              if (unread)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6, left: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              TourismPlanUi.dayBadge('Announcement'),
              const SizedBox(width: 8),
              Text(
                _relativeTime(a.publishedAt),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textGrey,
                ),
              ),
            ],
          ),
          if (a.body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              a.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppColors.textDark,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _eventCard(
    TourismEvent e,
    bool unread,
    TourismNewsFeedItem item,
  ) {
    return TourismFeedCard(
      onTap: () => _openNewsItemDetail(item),
      image: e.imagePath.isNotEmpty
          ? AspectRatio(
              aspectRatio: 16 / 9,
              child: buildMunicipalityImage(
                e.imagePath,
                fallback: Container(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  child: const Center(
                    child: Icon(
                      Icons.event_rounded,
                      color: AppColors.primary,
                      size: 40,
                    ),
                  ),
                ),
              ),
            )
          : null,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  e.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: unread ? FontWeight.w800 : FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              if (unread)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 6, left: 8),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              TourismPlanUi.dayBadge('Event'),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  formatEventDateTimeDisplay(e.dateTime),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textGrey,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (e.municipality.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              e.municipality,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
          ],
          if (e.description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              e.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: AppColors.textGrey,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
