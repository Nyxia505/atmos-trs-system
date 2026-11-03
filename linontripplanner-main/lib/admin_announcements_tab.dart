import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'admin_event_form_page.dart';
import 'catalog_publisher.dart';
import 'catalog_targeting.dart';
import 'data.dart';
import 'event_datetime_format.dart';
import 'firestore_loader.dart';
import 'services/auth_roles.dart';
import 'services/storage_image_upload.dart';
import 'widgets/catalog_image_preview.dart';

String _announcementImageFolderSlug(String title) {
  return title
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .replaceAll(RegExp(r'\s+'), '_');
}

void _confirmAnnouncementDelete(
  BuildContext context,
  String title,
  VoidCallback onConfirm,
) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete'),
      content: Text('Remove announcement "$title"?'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            onConfirm();
          },
          child: Text('Delete', style: TextStyle(color: Colors.red.shade400)),
        ),
      ],
    ),
  );
}

const _kOrange = Color(0xFFFF6B00);

enum GovernorFeedPhase { upcoming, ongoing, expired }

GovernorFeedPhase governorFeedPhase(DateTime when, DateTime now) {
  return switch (governorBoardPhase(when, now)) {
    GovernorBoardPhase.upcoming => GovernorFeedPhase.upcoming,
    GovernorBoardPhase.ongoing => GovernorFeedPhase.ongoing,
    GovernorBoardPhase.expired => GovernorFeedPhase.expired,
  };
}

/// Upcoming first (soonest), then ongoing, then expired (most recently ended).
List<TourismNewsFeedItem> sortGovernorEventsFeed(
  List<TourismNewsFeedItem> items,
  DateTime now,
) {
  final copy = List<TourismNewsFeedItem>.from(items);
  copy.sort((a, b) {
    final phaseA = governorFeedPhase(a.sortDate, now);
    final phaseB = governorFeedPhase(b.sortDate, now);
    if (phaseA != phaseB) return phaseA.index.compareTo(phaseB.index);
    if (phaseA == GovernorFeedPhase.expired) {
      return b.sortDate.compareTo(a.sortDate);
    }
    return a.sortDate.compareTo(b.sortDate);
  });
  return copy;
}

void _confirmEventDelete(
  BuildContext context,
  String title,
  VoidCallback onConfirm,
) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete'),
      content: Text('Remove event "$title"?'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            onConfirm();
          },
          child: Text('Delete', style: TextStyle(color: Colors.red.shade400)),
        ),
      ],
    ),
  );
}

/// Governor portal: Firestore `announcements` plus `events` (same feed as user notifications).
class AdminAnnouncementsTab extends StatefulWidget {
  final VoidCallback onChanged;
  final bool manageOwnedOnly;

  const AdminAnnouncementsTab({
    super.key,
    required this.onChanged,
    this.manageOwnedOnly = false,
  });

  @override
  State<AdminAnnouncementsTab> createState() => _AdminAnnouncementsTabState();
}

class _AdminAnnouncementsTabState extends State<AdminAnnouncementsTab> {
  bool _loading = true;
  bool _refreshing = false;
  bool _calendarView = false;
  late DateTime _month;
  DateTime? _selectedDay;
  final _listController = ScrollController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _loading = _board().isEmpty;
    _refreshing = !_loading;
    Future<void>.microtask(_fetchBoard);
  }

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  CatalogActor get _actor {
    final user = FirebaseAuth.instance.currentUser;
    final kind = AuthRoles.isGovernorPortalUser()
        ? CatalogPublisherKind.governor
        : AuthRoles.isOptacaDestinationViewer()
        ? CatalogPublisherKind.optaca
        : publisherKindFromRole(
            role: findAppUserByFirebaseUid(user?.uid)?.role ?? '',
            email: user?.email ?? '',
          );
    return CatalogActor(uid: user?.uid ?? '', kind: kind);
  }

  List<GovernorBoardItem> _board() {
    return sortGovernorBoard(
      buildGovernorBoard(
        announcements: tourismAnnouncements,
        events: tourismEvents,
        actor: _actor,
        manageOwnedOnly: widget.manageOwnedOnly,
      ),
      DateTime.now(),
    );
  }

  Future<void> _fetchBoard() async {
    try {
      await Future.wait<void>([
        loadEventsFromFirestore(),
        loadAnnouncementsFromFirestore(),
      ]).timeout(const Duration(seconds: 30));
      final suspected = suspectedDuplicateCatalogTitles(_board());
      if (suspected.isNotEmpty) {
        debugPrint(
          'Governor catalog possible duplicate titles (not deleted): $suspected',
        );
      }
    } catch (e, st) {
      debugPrint('Announcements feed load: $e\n$st');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<void> _refreshBoard({bool blocking = false}) async {
    if (!mounted) return;
    setState(() {
      if (blocking) {
        _loading = true;
      } else {
        _refreshing = true;
      }
    });
    await _fetchBoard();
  }

  Future<void> _openForm(String kind, {GovernorBoardItem? existing}) async {
    if (existing != null && !existing.canManage) return;
    bool? saved;
    if (kind == 'event') {
      final event = existing?.item is TourismNewsFeedEvent
          ? (existing!.item as TourismNewsFeedEvent).event
          : null;
      saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => AdminEventFormPage(existing: event),
        ),
      );
    } else {
      final announcement = existing?.item is TourismNewsFeedAnnouncement
          ? (existing!.item as TourismNewsFeedAnnouncement).announcement
          : null;
      saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute<bool>(
          builder: (_) => AdminAnnouncementFormPage(existing: announcement),
        ),
      );
    }
    if (!mounted) return;
    if (saved == true) {
      await _refreshBoard();
      widget.onChanged();
    }
  }

  Future<void> _chooseCreate(BuildContext anchor) async {
    final box = anchor.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = box.localToGlobal(
      box.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: const [
        PopupMenuItem(
          value: 'event',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.event_rounded, color: _kOrange),
            title: Text('Add Event'),
          ),
        ),
        PopupMenuItem(
          value: 'announcement',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.campaign_outlined, color: _kOrange),
            title: Text('Add Announcement'),
          ),
        ),
      ],
    );
    if (!mounted || choice == null) return;
    await _openForm(choice);
  }

  void _deleteItem(GovernorBoardItem item) {
    if (!item.canManage) return;
    final title = switch (item.item) {
      TourismNewsFeedEvent(:final event) => event.title,
      TourismNewsFeedAnnouncement(:final announcement) => announcement.title,
    };
    if (item.mutateCollection == 'announcements') {
      _confirmAnnouncementDelete(context, title, () async {
        await deleteTourismAnnouncementFromFirestore(item.mutateId);
        await _refreshBoard();
        widget.onChanged();
      });
      return;
    }
    _confirmEventDelete(context, title, () async {
      await deleteTourismEventFromFirestore(item.mutateId);
      await _refreshBoard();
      widget.onChanged();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kOrange));
    }
    final feed = _board();
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        return ListView(
          controller: _listController,
          padding: EdgeInsets.fromLTRB(wide ? 20 : 12, 16, wide ? 20 : 12, 28),
          children: [
            if (_refreshing)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  color: _kOrange,
                  backgroundColor: Color(0xFFFFE4CC),
                ),
              ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                const Text(
                  'Events & Announcements',
                  style: TextStyle(
                    color: Color(0xFF1F2937),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _ViewSwitch(
                      calendar: _calendarView,
                      onChanged: (calendar) =>
                          setState(() => _calendarView = calendar),
                    ),
                    Builder(
                      builder: (buttonContext) => FilledButton.icon(
                        onPressed: () => _chooseCreate(buttonContext),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Create'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _kOrange,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(44, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (feed.isEmpty)
              const _EmptyBoard()
            else if (_calendarView)
              _GovernorMonthCalendar(
                month: _month,
                selectedDay: _selectedDay,
                feed: feed,
                onMonth: (month) => setState(() {
                  _month = DateTime(month.year, month.month);
                  final day = _selectedDay;
                  if (day == null ||
                      day.year != month.year ||
                      day.month != month.month) {
                    _selectedDay = null;
                  }
                }),
                onSelect: (day) => setState(() => _selectedDay = day),
                cardBuilder: _feedCard,
              )
            else
              _FeedBoard(feed: feed, cardBuilder: _feedCard),
          ],
        );
      },
    );
  }

  Widget _feedCard(GovernorBoardItem item) {
    return _GovernorFeedCard(
      item: item,
      onEdit: item.canManage
          ? () => _openForm(
              item.isEvent && item.mutateCollection == 'events'
                  ? 'event'
                  : 'announcement',
              existing: item,
            )
          : null,
      onDelete: item.canManage ? () => _deleteItem(item) : null,
    );
  }
}

class _ViewSwitch extends StatelessWidget {
  const _ViewSwitch({required this.calendar, required this.onChanged});

  final bool calendar;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _chip('Events', !calendar, () => onChanged(false)),
          _chip('Calendar', calendar, () => onChanged(true)),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return Material(
      color: selected ? _kOrange : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : const Color(0xFF374151),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kOrange, width: 1.75),
      ),
      child: const Text(
        'No events or announcements yet.\nUse Create to add one.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textGrey, height: 1.4),
      ),
    );
  }
}

class _FeedBoard extends StatelessWidget {
  const _FeedBoard({required this.feed, required this.cardBuilder});

  final List<GovernorBoardItem> feed;
  final Widget Function(GovernorBoardItem item) cardBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980 ? 2 : 1;
        if (columns == 1) {
          return Column(
            children: [
              for (var i = 0; i < feed.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                cardBuilder(feed[i]),
              ],
            ],
          );
        }
        const gap = 12.0;
        final width = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in feed)
              SizedBox(width: width, child: cardBuilder(item)),
          ],
        );
      },
    );
  }
}

class _GovernorFeedCard extends StatelessWidget {
  const _GovernorFeedCard({required this.item, this.onEdit, this.onDelete});

  final GovernorBoardItem item;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final event = switch (item.item) {
      TourismNewsFeedEvent(:final event) => event,
      TourismNewsFeedAnnouncement() => null,
    };
    final announcement = switch (item.item) {
      TourismNewsFeedAnnouncement(:final announcement) => announcement,
      TourismNewsFeedEvent() => null,
    };
    final title = event?.title ?? announcement?.title ?? 'Untitled';
    final body = event?.description ?? announcement?.body ?? '';
    final image = event?.imagePath ?? announcement?.imagePath ?? '';
    final when = event?.dateTime ?? announcement?.publishedAt ?? DateTime.now();
    final municipality = catalogLocationLabel(
      municipality: event?.municipality ?? announcement?.municipality ?? '',
      audienceScope: event?.audienceScope ?? announcement?.audienceScope ?? '',
      municipalityId:
          event?.municipalityId ?? announcement?.municipalityId ?? '',
    );
    final venue = event?.venue ?? announcement?.venue ?? '';
    final category = event?.eventType.trim().isNotEmpty == true
        ? event!.eventType
        : (announcement?.type.trim() ?? '');
    final phase = governorFeedPhase(when, DateTime.now());
    final kind = item.isEvent ? 'Event' : 'Announcement';
    final phaseLabel = switch (phase) {
      GovernorFeedPhase.upcoming => 'Upcoming',
      GovernorFeedPhase.ongoing => 'Ongoing',
      GovernorFeedPhase.expired => 'Expired',
    };
    final publisherColor = switch (item.publisher.kind) {
      CatalogPublisherKind.governor => _kOrange,
      CatalogPublisherKind.lgu => const Color(0xFF2563EB),
      CatalogPublisherKind.optaca => const Color(0xFF15803D),
      CatalogPublisherKind.unknown => const Color(0xFF6B7280),
    };

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kOrange, width: 1.75),
        boxShadow: [
          BoxShadow(
            color: _kOrange.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 460;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _chip(
                    kind,
                    item.isEvent ? _kOrange : const Color(0xFF2563EB),
                  ),
                  _chip(
                    phaseLabel,
                    phase == GovernorFeedPhase.expired
                        ? const Color(0xFF6B7280)
                        : const Color(0xFF16A34A),
                  ),
                  _chip(item.publisher.label, publisherColor),
                  if (item.isEvent &&
                      category.isNotEmpty &&
                      category.toLowerCase() != 'event' &&
                      category.toLowerCase() != 'announcement')
                    _chip(category, const Color(0xFF7C3AED)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF1F2937),
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              _meta(
                Icons.calendar_today_rounded,
                formatEventDateTimeDisplay(when),
              ),
              if (municipality.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                _meta(Icons.location_city_rounded, municipality),
              ],
              if (venue.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                _meta(Icons.place_rounded, venue),
              ],
              if (body.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  body.trim(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF374151),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          );
          final actions = item.canManage && onEdit != null && onDelete != null
              ? _ActionRow(onEdit: onEdit!, onDelete: onDelete!)
              : null;
          final poster = CatalogImagePreview(
            imagePath: image,
            width: stacked ? double.infinity : 168,
            height: stacked ? 160 : 124,
          );
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                poster,
                const SizedBox(height: 12),
                details,
                if (actions != null) ...[const SizedBox(height: 12), actions],
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  poster,
                  const SizedBox(width: 12),
                  Expanded(child: details),
                ],
              ),
              if (actions != null) ...[const SizedBox(height: 12), actions],
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textGrey),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textGrey,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.onEdit, required this.onDelete});

  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    Widget button({
      required String label,
      required IconData icon,
      required Color color,
      required VoidCallback onPressed,
    }) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label, overflow: TextOverflow.ellipsis),
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: color.withValues(alpha: 0.1),
          foregroundColor: color,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: button(
            label: 'Edit',
            icon: Icons.edit_outlined,
            color: _kOrange,
            onPressed: onEdit,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: button(
            label: 'Delete',
            icon: Icons.delete_outline,
            color: const Color(0xFFDC2626),
            onPressed: onDelete,
          ),
        ),
      ],
    );
  }
}

class _GovernorMonthCalendar extends StatelessWidget {
  const _GovernorMonthCalendar({
    required this.month,
    required this.selectedDay,
    required this.feed,
    required this.onMonth,
    required this.onSelect,
    required this.cardBuilder,
  });

  final DateTime month;
  final DateTime? selectedDay;
  final List<GovernorBoardItem> feed;
  final ValueChanged<DateTime> onMonth;
  final ValueChanged<DateTime> onSelect;
  final Widget Function(GovernorBoardItem item) cardBuilder;

  static const _weekdays = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  bool _same(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<GovernorBoardItem> _onDay(DateTime day) {
    return feed
        .where((item) => _same(manilaCalendarDate(item.sortDate), day))
        .toList();
  }

  Widget _calendarCell({
    required int index,
    required int leading,
    required int days,
    required DateTime today,
  }) {
    final dayNumber = index - leading + 1;
    final inMonth = dayNumber >= 1 && dayNumber <= days;
    if (!inMonth) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          color: Color(0xFFF8FAFC),
          border: Border(
            top: BorderSide(color: Color(0xFFE5E7EB)),
            right: BorderSide(color: Color(0xFFE5E7EB)),
          ),
        ),
      );
    }
    final day = DateTime(month.year, month.month, dayNumber);
    final hits = _onDay(day);
    final selected = selectedDay != null && _same(day, selectedDay!);
    final isToday = _same(day, today);
    final label = hits.length == 1
        ? switch (hits.first.item) {
            TourismNewsFeedEvent(:final event) => event.title,
            TourismNewsFeedAnnouncement(:final announcement) =>
              announcement.title,
          }
        : hits.isEmpty
        ? ''
        : '${hits.length}';
    return Material(
      color: selected ? const Color(0xFFFFF1E6) : Colors.white,
      child: InkWell(
        onTap: () => onSelect(day),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? _kOrange : const Color(0xFFE5E7EB),
              width: selected || isToday ? 1.5 : 0.8,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(5, 4, 4, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$dayNumber',
                  style: TextStyle(
                    fontWeight: isToday || selected
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: isToday ? _kOrange : const Color(0xFF1F2937),
                    fontSize: 12,
                  ),
                ),
                if (hits.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _kOrange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _kOrange,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final days = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday % 7;
    final cells = ((leading + days + 6) ~/ 7) * 7;
    final today = manilaCalendarDate(DateTime.now());
    final hits = selectedDay == null
        ? const <GovernorBoardItem>[]
        : _onDay(manilaCalendarDate(selectedDay!));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kOrange, width: 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous month',
                      onPressed: () =>
                          onMonth(DateTime(month.year, month.month - 1)),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        '${_months[month.month - 1]} ${month.year}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next month',
                      onPressed: () =>
                          onMonth(DateTime(month.year, month.month + 1)),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
              Container(
                color: _kOrange,
                height: 36,
                alignment: Alignment.center,
                child: Row(
                  children: [
                    for (final label in _weekdays)
                      Expanded(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final cellHeight = constraints.maxWidth >= 720 ? 70.0 : 62.0;
                  final rows = cells ~/ 7;
                  return Column(
                    children: [
                      for (var row = 0; row < rows; row++)
                        SizedBox(
                          height: cellHeight,
                          child: Row(
                            children: [
                              for (var col = 0; col < 7; col++)
                                Expanded(
                                  child: _calendarCell(
                                    index: row * 7 + col,
                                    leading: leading,
                                    days: days,
                                    today: today,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          selectedDay == null
              ? 'Select a date'
              : '${_months[selectedDay!.month - 1]} ${selectedDay!.day}, ${selectedDay!.year}'
                    ' · ${hits.length} item${hits.length == 1 ? '' : 's'}',
          style: const TextStyle(
            color: _kOrange,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 10),
        if (selectedDay == null)
          const Text(
            'Choose a date to see its events and announcements.',
            style: TextStyle(color: AppColors.textGrey),
          )
        else if (hits.isEmpty)
          const Text(
            'Nothing scheduled on this date.',
            style: TextStyle(color: AppColors.textGrey),
          )
        else
          _FeedBoard(feed: hits, cardBuilder: cardBuilder),
      ],
    );
  }
}

class AdminAnnouncementFormPage extends StatefulWidget {
  final TourismAnnouncement? existing;

  const AdminAnnouncementFormPage({super.key, this.existing});

  @override
  State<AdminAnnouncementFormPage> createState() =>
      _AdminAnnouncementFormPageState();
}

class _AdminAnnouncementFormPageState extends State<AdminAnnouncementFormPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _bodyController;
  late TextEditingController _imageController;
  late DateTime _publishedAt;
  bool _uploadingImage = false;
  bool _saving = false;
  Uint8List? _previewBytes;
  late String _docId;
  String? _municipality;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.existing?.title ?? '',
    );
    _bodyController = TextEditingController(text: widget.existing?.body ?? '');
    _imageController = TextEditingController(
      text: widget.existing?.imagePath ?? '',
    );
    _imageController.addListener(_refreshImagePreview);
    _publishedAt = widget.existing?.publishedAt ?? DateTime.now();
    _docId = widget.existing?.id ?? '';
    _municipality = catalogSelectionFromRecord(
      municipality: widget.existing?.municipality ?? '',
      audienceScope: widget.existing?.audienceScope ?? '',
      municipalityId: widget.existing?.municipalityId ?? '',
    );
  }

  void _refreshImagePreview() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _imageController.removeListener(_refreshImagePreview);
    _titleController.dispose();
    _bodyController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  Future<void> _pickPublishedDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _publishedAt,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        _publishedAt = DateTime(
          d.year,
          d.month,
          d.day,
          _publishedAt.hour,
          _publishedAt.minute,
        );
      });
    }
  }

  Future<void> _pickPublishedTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_publishedAt),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (t != null) {
      setState(() {
        _publishedAt = DateTime(
          _publishedAt.year,
          _publishedAt.month,
          _publishedAt.day,
          t.hour,
          t.minute,
        );
      });
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery);
    if (xFile == null) return;
    final bytes = await xFile.readAsBytes();
    if (!mounted) return;
    setState(() {
      _previewBytes = bytes;
      _uploadingImage = true;
    });
    try {
      final slug = _announcementImageFolderSlug(
        _titleController.text.trim().isEmpty
            ? 'announcement'
            : _titleController.text.trim(),
      );
      final folder = 'announcements/$slug';
      // File bytes → Supabase Storage; Firestore keeps only the public URL.
      final url = await uploadTourismCatalogImage(bytes, folder);
      if (mounted) {
        setState(() {
          _imageController.text = url;
          _uploadingImage = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image uploaded to Supabase Storage.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Supabase upload failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildImagePlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_photo_alternate,
            size: 48,
            color: AppColors.primary.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap to pick from device',
            style: TextStyle(fontSize: 13, color: AppColors.textGrey),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_saving || _uploadingImage) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    if (_docId.isEmpty) {
      _docId = FirebaseFirestore.instance
          .collection(kAnnouncementsCollection)
          .doc()
          .id;
    }
    final ann = TourismAnnouncement(
      id: _docId,
      title: _titleController.text.trim(),
      body: _bodyController.text.trim(),
      imagePath: _imageController.text.trim(),
      publishedAt: _publishedAt,
      type: widget.existing?.type.trim().isNotEmpty == true
          ? widget.existing!.type
          : 'Announcement',
      municipality: _municipality == null
          ? (widget.existing?.municipality ?? '')
          : catalogMunicipalityForSelection(_municipality),
      audienceScope: _municipality == null
          ? (widget.existing?.audienceScope ?? '')
          : catalogAudienceScopeForSelection(_municipality),
    );
    try {
      await upsertTourismAnnouncementToFirestore(ann);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (mounted) Navigator.pop(context, true);
  }

  Widget _section(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1F2937),
        ),
      ),
    );
  }

  Widget _scheduleButtons() {
    final date = OutlinedButton.icon(
      onPressed: _pickPublishedDate,
      icon: const Icon(Icons.calendar_today_outlined, size: 18),
      label: Text(
        formatEventDateWords(_publishedAt),
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
    );
    final time = OutlinedButton.icon(
      onPressed: _pickPublishedTime,
      icon: const Icon(Icons.schedule, size: 18),
      label: Text(
        formatEventTime12(_publishedAt),
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 480) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [date, const SizedBox(height: 8), time],
          );
        }
        return Row(
          children: [
            Expanded(child: date),
            const SizedBox(width: 10),
            Expanded(child: time),
          ],
        );
      },
    );
  }

  Widget _posterPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section('Poster'),
        GestureDetector(
          onTap: _uploadingImage ? null : _pickImage,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.35),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: _uploadingImage
                  ? const SizedBox(
                      height: 180,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : CatalogImagePreview(
                      bytes: _previewBytes,
                      imagePath: _imageController.text,
                      height: 180,
                      borderRadius: BorderRadius.zero,
                      fallback: _buildImagePlaceholder(),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Tap the preview to choose an image. The full poster stays visible.',
          style: TextStyle(fontSize: 12, color: AppColors.textGrey),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          widget.existing != null ? 'Edit announcement' : 'Add announcement',
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _section('Details'),
                  TextFormField(
                    controller: _titleController,
                    decoration: catalogFieldDecoration(label: 'Title *'),
                    validator: (v) =>
                        v?.trim().isEmpty ?? true ? 'Enter a title' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _bodyController,
                    decoration: catalogFieldDecoration(
                      label: 'Message',
                      optional: true,
                    ),
                    minLines: 4,
                    maxLines: 10,
                  ),
                  const SizedBox(height: 22),
                  _section('Location'),
                  DropdownButtonFormField<String?>(
                    value: _municipality,
                    decoration: catalogFieldDecoration(
                      label: widget.existing == null
                          ? 'Municipality *'
                          : 'Municipality',
                      hint: 'One LGU or the whole province',
                    ),
                    hint: const Text('Select municipality or province-wide'),
                    isExpanded: true,
                    items: catalogAudienceItems(extraValue: _municipality),
                    onChanged: (v) => setState(() => _municipality = v),
                    validator: (v) {
                      if (widget.existing != null && v == null) return null;
                      if (v == null || v.trim().isEmpty) {
                        return 'Select a municipality';
                      }
                      return null;
                    },
                  ),
                  _section('Publish date'),
                  _scheduleButtons(),
                  const SizedBox(height: 8),
                  Text(
                    'Published: ${formatEventDateTimeDisplay(_publishedAt)}',
                    style: TextStyle(fontSize: 13, color: AppColors.textGrey),
                  ),
                  _posterPicker(),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _imageController,
                    decoration: const InputDecoration(
                      labelText: 'Image URL (optional)',
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Save announcement'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
