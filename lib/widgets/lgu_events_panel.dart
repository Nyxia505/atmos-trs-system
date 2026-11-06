import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter, TileMode;

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/services/announcement_push_service.dart';
import 'package:atmos_trs_system/services/lgu_event_service.dart';
import 'package:atmos_trs_system/widgets/event_description_text.dart';
import 'package:atmos_trs_system/widgets/lgu_events_calendar.dart';
import 'package:atmos_trs_system/widgets/spot_image.dart';
import 'package:atmos_trs_system/widgets/ui_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trip_plan/catalog_publisher.dart';

/// LGU dashboard panel — create/edit/delete own posts (auto-published).
/// Province Live tab shows all LGU events across Misamis Occidental.
class LguEventsPanel extends StatefulWidget {
  const LguEventsPanel({
    super.key,
    required this.municipalityId,
    required this.municipalityName,
    this.primaryColor = const Color(0xFFEA580C),
    /// 0 = Province Live, 1 = My posts, 2 = Calendar
    this.initialTabIndex = 2,
  /// When false, parent shell already shows the page title (avoid duplicate chrome).
  this.showChrome = true,
  /// Province viewers can open the same feed and calendar without posting.
  this.readOnly = false,
});

  final String? municipalityId;
  final String? municipalityName;
  final Color primaryColor;
  final int initialTabIndex;
  final bool showChrome;
  final bool readOnly;

  @override
  State<LguEventsPanel> createState() => _LguEventsPanelState();
}

class _LguEventsPanelState extends State<LguEventsPanel>
    with SingleTickerProviderStateMixin {
  final _service = LguEventService();
  final _picker = ImagePicker();

  List<Map<String, dynamic>> _allEvents = [];
  bool _loading = true;
  bool _didLoadOnce = false;
  String? _loadError;
  DateTime _calendarMonth = DateTime(
    LguEventService.manilaNow().year,
    LguEventService.manilaNow().month,
  );
  DateTime? _selectedCalendarDay = () {
    final now = LguEventService.manilaNow();
    return DateTime(now.year, now.month, now.day);
  }();
  String _liveFilter = 'all';
  String _calendarViewMode = 'month';
  final Set<String> _expandedPosts = {};
  final Map<String, int> _photoIndex = {};
  final Set<String> _publishingIds = {};
  final List<String> _customEventTypes = [];
  StreamSubscription<List<Map<String, dynamic>>>? _eventsSub;
  late final TabController _tabController;

  static const _tabs = ['Province Live', 'My posts', 'Calendar'];

  String get _municipalityId => _idFrom(widget);

  String _idFrom(LguEventsPanel panel) {
    final raw = panel.municipalityId?.trim() ?? '';
    if (raw.isNotEmpty) return raw;
    final name = (panel.municipalityName ?? '').trim().toLowerCase();
    if (name.isEmpty || name == 'lgu') return '';
    for (final m in getMisamisOccidentalMunicipalities()) {
      final label = m.name.toLowerCase();
      if (label == name || name.contains(label) || label.contains(name)) {
        return m.id;
      }
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, _tabs.length - 1),
    );
    _tabController.addListener(_onTabChanged);
    _hydrateFromCacheThenLoad();
    _listen();
    unawaited(_loadCustomEventTypes());
    unawaited(AnnouncementPushService.backfillOnce());
  }

  @override
  void didUpdateWidget(covariant LguEventsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_municipalityId != _idFrom(oldWidget) ||
        oldWidget.municipalityName != widget.municipalityName) {
      _didLoadOnce = false;
      _customEventTypes.clear();
      _hydrateFromCacheThenLoad();
      _listen();
      unawaited(_loadCustomEventTypes());
    } else if (oldWidget.initialTabIndex != widget.initialTabIndex) {
      final next = widget.initialTabIndex.clamp(0, _tabs.length - 1);
      if (_tabController.index != next) {
        _tabController.animateTo(next);
      }
    }
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _listen() {
    _eventsSub?.cancel();
    final municipalityId = _municipalityId;
    if (municipalityId.isEmpty) return;
    _eventsSub = _service.watchAnnouncements().listen(
      (docs) {
        if (!mounted) return;
        final next = _mergeWithLocal(docs, _allEvents);
        if (_sameEvents(_allEvents, next) && !_loading && _loadError == null) {
          return;
        }
        setState(() {
          _allEvents = next;
          _splitEvents();
          _loading = false;
          _didLoadOnce = true;
          _loadError = null;
        });
      },
      onError: (Object e) {
        debugPrint('[LguEventsPanel] watch: $e');
        if (!mounted) return;
        setState(() {
          _loading = false;
          _loadError = 'Could not load events. Check your connection and retry.';
        });
      },
    );
  }

  void _splitEvents() {}

  void _hydrateFromCacheThenLoad() {
    final municipalityId = _municipalityId;
    if (municipalityId.isEmpty) {
      setState(() {
        _allEvents = [];
        _loading = false;
      });
      return;
    }
    final cached = LguEventService.peekEventsCache(municipalityId);
    if (cached != null) {
      setState(() {
        _allEvents = _mergeWithLocal(
          _combineMineAndProvince(cached.mine, cached.province),
          _allEvents,
        );
        _splitEvents();
        _loading = false;
        _didLoadOnce = true;
      });
      // Refresh quietly in background so data stays fresh.
      unawaited(_load(silent: true));
      return;
    }
    unawaited(_load(silent: false));
  }

  bool _isOwnEvent(Map<String, dynamic> event) {
    final mun = _municipalityId;
    if (mun.isEmpty) return false;
    if (LguEventService.isGovernorOwned(event) ||
        LguEventService.isOptacaOwned(event)) {
      return false;
    }
    return LguEventService.matchesMunicipality(event, mun);
  }

  /// This LGU may edit, reschedule, and delete its own posts and catalog events.
  bool _canManageEvent(Map<String, dynamic> event) {
    if (widget.readOnly) return false;
    return LguEventService.lguMayManage(event, _municipalityId);
  }

  CatalogPublisher _publisherOf(Map<String, dynamic> event) {
    return resolveCatalogPublisher(
      publisherOffice: event['publisherOffice']?.toString() ?? '',
      createdBy: event['createdBy']?.toString() ?? '',
      createdByUid: event['createdByUid']?.toString() ?? '',
      municipalityId: event['municipalityId']?.toString() ?? '',
      municipalityName: (event['municipalityName'] ?? event['municipality'])
              ?.toString() ??
          '',
    );
  }

  String _postBody(Map<String, dynamic> event) {
    final content = event['content']?.toString().trim() ?? '';
    if (content.isNotEmpty) return content;
    return (event['body'] ?? event['description'] ?? '').toString().trim();
  }

  List<Widget> _feedChips(
    Map<String, dynamic> event, {
    required String type,
    required Color typeColor,
    required String status,
    required Color statusColor,
    required bool pending,
    bool onDark = false,
  }) {
    final publisher = _publisherOf(event);
    return [
      _metaChip(type, typeColor, onDark: onDark),
      if (publisher.kind != CatalogPublisherKind.unknown)
        _metaChip(publisher.label, widget.primaryColor, onDark: onDark),
      _metaChip(
        pending ? 'Publishing…' : status,
        pending ? widget.primaryColor : statusColor,
        onDark: onDark,
      ),
    ];
  }

  String get _eventTypePrefsKey =>
      'lgu_event_categories_${_municipalityId.trim().toLowerCase()}';

  List<String> _eventTypeChoices() {
    final seen = <String>{};
    final choices = <String>[];
    void add(String? raw) {
      final name = LguEventService.normalizeType(raw);
      if (name.isEmpty ||
          name.toLowerCase() == LguEventService.typeOther.toLowerCase()) {
        return;
      }
      if (!seen.add(name.toLowerCase())) return;
      choices.add(name);
    }

    for (final type in LguEventService.postTypes) {
      add(type);
    }
    for (final type in _customEventTypes) {
      add(type);
    }
    for (final event in _allEvents) {
      if (!_isOwnEvent(event)) continue;
      add(event['type']?.toString());
    }
    return choices;
  }

  Future<void> _loadCustomEventTypes() async {
    final municipalityId = _municipalityId.trim();
    if (municipalityId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_eventTypePrefsKey) ?? const [];
    if (!mounted || municipalityId != _municipalityId.trim()) return;
    setState(() {
      _customEventTypes
        ..clear()
        ..addAll(saved.where((type) => type.trim().isNotEmpty));
    });
  }

  Future<void> _rememberEventType(String raw) async {
    final name = LguEventService.normalizeType(raw);
    if (name.isEmpty ||
        name.toLowerCase() == LguEventService.typeOther.toLowerCase()) {
      return;
    }
    final builtIn = LguEventService.postTypes.any(
      (type) =>
          type != LguEventService.typeOther &&
          type.toLowerCase() == name.toLowerCase(),
    );
    if (builtIn) return;
    final exists = _customEventTypes.any(
      (type) => type.toLowerCase() == name.toLowerCase(),
    );
    if (!exists) {
      _customEventTypes.add(name);
      if (mounted) setState(() {});
    }
    final municipalityId = _municipalityId.trim();
    if (municipalityId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_eventTypePrefsKey, _customEventTypes);
  }

  Future<String?> _promptNewEventType(List<String> existing) async {
    final controller = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New category'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Category name',
            hintText: 'e.g. Festival, Sports, Concert',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: widget.primaryColor),
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    if (!mounted || entered == null) return null;
    if (entered.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a category name.')),
      );
      return null;
    }
    final name = LguEventService.normalizeType(entered);
    for (final type in existing) {
      if (type.toLowerCase() == name.toLowerCase()) return type;
    }
    await _rememberEventType(name);
    return name;
  }

  String _sourceCollection(Map<String, dynamic>? event) {
    return event?['catalogSource']?.toString() == LguEventService.eventsCollection
        ? LguEventService.eventsCollection
        : LguEventService.collection;
  }

  bool _isAnnouncement(Map<String, dynamic> event) {
    return LguEventService.isAnnouncementType(event);
  }

  List<Map<String, dynamic>> _applyLiveFilter(
    Iterable<Map<String, dynamic>> source,
  ) {
    switch (_liveFilter) {
      case 'mine':
        return source.where(_isOwnEvent).toList();
      case 'events':
        return source.where((event) => !_isAnnouncement(event)).toList();
      case 'announcements':
        return source.where(_isAnnouncement).toList();
      default:
        return source.toList();
    }
  }

  List<Map<String, dynamic>> _filteredProvince() {
    return _sorted(
      _applyLiveFilter(
        _allEvents.where(
          (event) => LguEventService.isEligibleForProvinceLive(
            event,
            municipalityId: _municipalityId,
            municipalityName: widget.municipalityName ?? '',
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _sorted(List<Map<String, dynamic>> events) {
    final list = List<Map<String, dynamic>>.of(events);
    list.sort(LguEventService.compareBySchedule);
    return list;
  }

  /// Calendar includes scheduled posts, not only posts that are live today.
  List<Map<String, dynamic>> _filteredCalendarPosts() {
    return _applyLiveFilter(
      _allEvents.where((event) {
        if (LguEventService.statusOf(event) == 'rejected') return false;
        return LguEventService.isTargetedAtLguFeed(
          event,
          municipalityId: _municipalityId,
          municipalityName: widget.municipalityName ?? '',
        );
      }),
    );
  }

  int _countForTab(int index) {
    if (index == 2) return _calendarCount();
    if (index == 1) return _myPosts().length;
    return _filteredProvince().length;
  }

  List<Map<String, dynamic>> _myPosts() {
    return _sorted(
      _allEvents.where((event) {
        if (LguEventService.statusOf(event) == 'rejected') return false;
        return _isOwnEvent(event);
      }).toList(),
    );
  }

  Future<void> _load({bool silent = false}) async {
    final municipalityId = _municipalityId;
    if (municipalityId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _allEvents = [];
        _loading = false;
        _loadError = null;
      });
      return;
    }
    if (!silent || !_didLoadOnce) {
      if (mounted) setState(() => _loading = !_didLoadOnce);
    }
    try {
      final both = await _service.loadMineAndProvince(municipalityId);
      if (!mounted) return;
      setState(() {
        _allEvents = _mergeWithLocal(
          _combineMineAndProvince(both.mine, both.province),
          _allEvents,
        );
        _splitEvents();
        _loading = false;
        _didLoadOnce = true;
        _loadError = null;
      });
    } catch (e) {
      debugPrint('[LguEventsPanel] load: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load events. Check your connection and retry.';
      });
    }
  }

  /// Keeps optimistic (still publishing) posts and their local photo bytes
  /// when a Firestore reload lands, so cards never flicker or vanish.
  ///
  /// Always returns at most one row per [LguEventService.canonicalKey] so
  /// concatenating mine + province feeds cannot render the same doc twice.
  List<Map<String, dynamic>> _mergeWithLocal(
    List<Map<String, dynamic>> fetched,
    List<Map<String, dynamic>> local,
  ) {
    final localByKey = {
      for (final e in local) LguEventService.canonicalKey(e): e,
    };
    final fetchedKeys = <String>{};
    final merged = <Map<String, dynamic>>[];
    for (final e in LguEventService.mergeUnique(fetched)) {
      final key = LguEventService.canonicalKey(e);
      if (!fetchedKeys.add(key)) continue;
      final prev = localByKey[key];
      if (prev != null && prev[_kPendingKey] == true) {
        merged.add(prev);
      } else if (prev != null && prev[_kLocalImageKey] is Uint8List) {
        merged.add({...e, _kLocalImageKey: prev[_kLocalImageKey]});
      } else {
        merged.add(e);
      }
    }
    final pendingNew = local.where((e) {
      if (e[_kPendingKey] != true) return false;
      return !fetchedKeys.contains(LguEventService.canonicalKey(e));
    });
    return LguEventService.mergeUnique([...pendingNew, ...merged]);
  }

  List<Map<String, dynamic>> _combineMineAndProvince(
    List<Map<String, dynamic>> mine,
    List<Map<String, dynamic>> province,
  ) =>
      LguEventService.mergeUnique([...mine, ...province]);

  bool _sameEvents(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i]['id'] != b[i]['id']) return false;
      if (a[i]['title'] != b[i]['title']) return false;
      if (a[i]['content'] != b[i]['content']) return false;
      if (a[i]['published'] != b[i]['published']) return false;
      if (a[i]['updatedAt']?.toString() != b[i]['updatedAt']?.toString()) {
        return false;
      }
      if (a[i]['startsAt']?.toString() != b[i]['startsAt']?.toString()) {
        return false;
      }
    }
    return true;
  }

  void _upsertLocal(Map<String, dynamic> event) {
    final key = LguEventService.canonicalKey(event);
    List<Map<String, dynamic>> apply(List<Map<String, dynamic>> list) {
      final next = <Map<String, dynamic>>[];
      var replaced = false;
      for (final e in list) {
        if (LguEventService.canonicalKey(e) == key) {
          if (!replaced) {
            next.add(event);
            replaced = true;
          }
          // Drop any prior duplicate rows for the same canonical key.
          continue;
        }
        next.add(e);
      }
      if (!replaced) next.insert(0, event);
      return next;
    }

    _allEvents = apply(_allEvents);
    _splitEvents();
  }

  void _removeLocal(String id, {String sourceCollection = ''}) {
    final source = sourceCollection.trim().isNotEmpty
        ? sourceCollection.trim()
        : LguEventService.collection;
    final key = id.trim().isEmpty ? '' : '$source:$id';
    _allEvents = _allEvents.where((e) {
      if (key.isNotEmpty) {
        return LguEventService.canonicalKey(e) != key &&
            e['id']?.toString() != id;
      }
      return e['id']?.toString() != id;
    }).toList();
    // Keep list unique after delete (belt-and-suspenders for stale dupes).
    _allEvents = LguEventService.mergeUnique(_allEvents);
    _splitEvents();
  }

  /// Saves in the background after the dialog has already closed. The card
  /// shows "Publishing…" immediately and flips to Live when Firestore confirms.
  Future<void> _submitDraft(
    _PostDraft draft, {
    Map<String, dynamic>? original,
  }) async {
    if (!_publishingIds.add(draft.eventId)) return;
    final messenger = ScaffoldMessenger.of(context);
    final municipalityId = _municipalityId;
    final munName = (widget.municipalityName?.trim().isNotEmpty ?? false)
        ? widget.municipalityName!.trim()
        : municipalityId;

    final optimistic = <String, dynamic>{
      ...?original,
      'id': draft.eventId,
      'title': draft.title,
      'content': draft.content,
      'type': draft.type,
      'status': 'approved',
      'municipalityId': original?['municipalityId'] ?? municipalityId,
      'municipalityName': original?['municipalityName'] ?? munName,
      'date': draft.dateLabel,
      'startsAt': draft.startInstant.toIso8601String(),
      'endsAt': draft.endInstant.toIso8601String(),
      'allDay': draft.allDay,
      'scheduleState': draft.liveNow ? 'live' : 'scheduled',
      'published': draft.liveNow,
      'durationDays': draft.durationDays,
      _kPendingKey: true,
    };
    if (draft.imageBytes != null) {
      optimistic[_kLocalImageKey] = draft.imageBytes;
    } else if (draft.removeImage) {
      optimistic
        ..remove('imageUrl')
        ..remove('imageBase64')
        ..remove(_kLocalImageKey);
    }
    if (mounted) setState(() => _upsertLocal(optimistic));

    try {
      if (draft.isNew) {
        final id = await _service.createEvent(
          eventId: draft.eventId,
          municipalityId: municipalityId,
          municipalityName: munName,
          title: draft.title,
          content: draft.content,
          type: draft.type,
          imageBytes: draft.imageBytes,
          imageContentType: draft.imageContentType,
          preparedImageFields: draft.preparedImage,
          startsAt: draft.startsAt,
          endsAt: draft.endsAt,
          allDay: draft.allDay,
          durationDays: draft.durationDays,
          galleryBytes: draft.galleryBytes,
        );
        if (id == null) throw StateError('Could not save post.');
      } else {
        await _service.updateEvent(
          eventId: draft.eventId,
          municipalityId: municipalityId,
          title: draft.title,
          content: draft.content,
          type: draft.type,
          sourceCollection: _sourceCollection(original),
          imageBytes: draft.imageBytes,
          imageContentType: draft.imageContentType,
          preparedImageFields: draft.preparedImage,
          removeImage: draft.removeImage,
          startsAt: draft.startsAt,
          endsAt: draft.endsAt,
          allDay: draft.allDay,
          durationDays: draft.durationDays,
          galleryBytes: draft.galleryBytes,
        );
      }
      unawaited(_rememberEventType(draft.type));
      LguEventService.invalidateEventsCache();
      if (mounted) {
        setState(() => _upsertLocal({...optimistic, _kPendingKey: false}));
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            draft.isNew
                ? 'Event published successfully.'
                : (draft.imageBytes != null
                    ? 'Photo saved.'
                    : draft.removeImage
                        ? 'Photo removed.'
                        : 'Updated (${draft.type}).'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (mounted) unawaited(_load(silent: true));
    } catch (e) {
      if (mounted) {
        setState(() {
          if (original == null) {
            _removeLocal(draft.eventId);
          } else {
            _upsertLocal(original);
          }
        });
      }
      final rawError = e is StateError ? e.message : e.toString();
      final photoFailed = rawError.contains('Photo upload failed');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            photoFailed
                ? 'Photo upload failed. Please retry.'
                : 'Could not save "${draft.title}": $rawError',
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: () {
              if (!mounted) return;
              unawaited(
                _submitDraft(draft.withoutPreparedImage(), original: original),
              );
            },
          ),
        ),
      );
    } finally {
      _publishingIds.remove(draft.eventId);
    }
  }

  Future<void> _showEventDialog({
    Map<String, dynamic>? existing,
    bool scheduleOnly = false,
  }) async {
    final municipalityId = _municipalityId;
    final titleController = TextEditingController(
      text: existing?['title']?.toString() ?? '',
    );
    final contentController = TextEditingController(
      text: existing?['content']?.toString() ?? '',
    );
    final existingId = existing?['id']?.toString() ?? '';
    final eventId = existingId.isNotEmpty ? existingId : _service.newEventId();
    Uint8List? pickedBytes;
    String? pickedContentType;
    Future<Map<String, dynamic>>? preparedImage;
    var photoUpload = _PhotoUploadState.none;
    var photoMessage = '';
    var dialogOpen = true;
    bool removeImage = false;
    final existingImage = LguEventService.resolveDisplayImage(existing);
    final typeChoices = _eventTypeChoices();
    final rawType = LguEventService.normalizeType(existing?['type']?.toString());
    var selectedType = LguEventService.typeEvent;
    for (final type in typeChoices) {
      if (type.toLowerCase() == rawType.toLowerCase()) {
        selectedType = type;
        break;
      }
    }
    if (rawType.isNotEmpty &&
        !typeChoices.any((type) => type.toLowerCase() == rawType.toLowerCase())) {
      typeChoices.add(rawType);
      selectedType = rawType;
    }
    final existingStart = existing == null
        ? LguEventService.manilaNow()
        : (LguEventService.eventStart(existing) ?? LguEventService.manilaNow());
    final existingDays = existing == null
        ? 1
        : LguEventService.eventDurationDays(existing);
    var allDay = existing == null ||
        existing['allDay'] == true ||
        existing['endsAt'] == null;
    var startDate = DateTime(existingStart.year, existingStart.month, existingStart.day);
    var endDate = DateTime(startDate.year, startDate.month, startDate.day)
        .add(Duration(days: existingDays - 1));
    if (existing != null && existing['endsAt'] != null && !allDay) {
      final endWall = LguEventService.eventEnd(existing);
      if (endWall != null) {
        endDate = DateTime(endWall.year, endWall.month, endWall.day);
      }
    } else if (existing != null && existing['allDay'] == true) {
      final endWall = LguEventService.eventEnd(existing);
      if (endWall != null) {
        final last = endWall.subtract(const Duration(days: 1));
        endDate = DateTime(last.year, last.month, last.day);
      }
    }
    var startTime = TimeOfDay(hour: existingStart.hour, minute: existingStart.minute);
    var endTime = const TimeOfDay(hour: 17, minute: 0);
    if (existing != null && existing['endsAt'] != null && !allDay) {
      final endWall = LguEventService.eventEnd(existing);
      if (endWall != null) {
        endTime = TimeOfDay(hour: endWall.hour, minute: endWall.minute);
      }
    }
    final extraImages = <Uint8List>[];
    var submitting = false;

    final draft = await showDialog<_PostDraft>(
      context: context,
      builder: (dialogContext) {
        final maxW = MediaQuery.sizeOf(dialogContext).width;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(
              existing == null
                  ? 'New Post'
                  : (scheduleOnly ? 'Reschedule' : 'Edit Post'),
            ),
            content: SizedBox(
              width: maxW < 560 ? maxW - 48 : 460,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.62,
                ),
                child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (scheduleOnly) ...[
                      Text(
                        'Pick a new date and time. The title, details, and photo stay the same.',
                        style: TextStyle(
                          color: AppTheme.unselectedMuted,
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (!scheduleOnly) ...[
                      TextField(
                        controller: titleController,
                        autofocus: existing == null,
                        textInputAction: TextInputAction.next,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Category / Type',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final type in typeChoices)
                            ChoiceChip(
                              label: Text(type),
                              selected: selectedType.toLowerCase() ==
                                  type.toLowerCase(),
                              onSelected: (_) =>
                                  setDialogState(() => selectedType = type),
                              selectedColor: widget.primaryColor,
                              labelStyle: TextStyle(
                                color: selectedType.toLowerCase() ==
                                        type.toLowerCase()
                                    ? Colors.white
                                    : AppTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                              checkmarkColor: Colors.white,
                            ),
                          ActionChip(
                            avatar: Icon(
                              Icons.add_rounded,
                              size: 16,
                              color: widget.primaryColor,
                            ),
                            label: const Text('Add category'),
                            onPressed: () async {
                              final name = await _promptNewEventType(typeChoices);
                              if (name == null || !dialogOpen) return;
                              setDialogState(() {
                                final known = typeChoices.any(
                                  (type) =>
                                      type.toLowerCase() == name.toLowerCase(),
                                );
                                if (!known) typeChoices.add(name);
                                selectedType = typeChoices.firstWhere(
                                  (type) =>
                                      type.toLowerCase() == name.toLowerCase(),
                                );
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'All day',
                        style: TextStyle(color: AppTheme.textPrimary),
                      ),
                      subtitle: Text(
                        'Times use Asia/Manila.',
                        style: TextStyle(
                          color: AppTheme.unselectedMuted,
                          fontSize: 12,
                        ),
                      ),
                      value: allDay,
                      activeThumbColor: Colors.white,
                      activeTrackColor: widget.primaryColor,
                      onChanged: (value) => setDialogState(() => allDay = value),
                    ),
                    const SizedBox(height: 4),
                    _schedulePickers(
                      context: context,
                      allDay: allDay,
                      startDate: startDate,
                      endDate: endDate,
                      startTime: startTime,
                      endTime: endTime,
                      onStartDate: (value) => setDialogState(() {
                        startDate = value;
                        if (endDate.isBefore(startDate)) endDate = startDate;
                      }),
                      onEndDate: (value) => setDialogState(() => endDate = value),
                      onStartTime: (value) => setDialogState(() => startTime = value),
                      onEndTime: (value) => setDialogState(() => endTime = value),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _scheduleHint(
                        allDay: allDay,
                        startDate: startDate,
                        endDate: endDate,
                        startTime: startTime,
                        endTime: endTime,
                      ),
                      style: TextStyle(
                        color: AppTheme.unselectedMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                    if (!scheduleOnly) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: contentController,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Details',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (!removeImage &&
                        pickedBytes == null &&
                        existingImage != null &&
                        existingImage.isNotEmpty)
                      _EventPhotoFrame(
                        child: SpotImage(
                          imageUrl: existingImage,
                          fit: BoxFit.contain,
                        ),
                      ),
                    if (pickedBytes != null) ...[
                      _EventPhotoFrame(
                        child: Image.memory(
                          pickedBytes!,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _PhotoUploadStatus(
                        state: photoUpload,
                        color: widget.primaryColor,
                        failedMessage: photoMessage,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final file = await _picker.pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 82,
                              maxWidth: 1600,
                            );
                            if (file == null) return;
                            final bytes = await file.readAsBytes();
                            final ct = (file.mimeType?.trim().isNotEmpty ??
                                    false)
                                ? file.mimeType!.trim()
                                : 'image/jpeg';
                            if (!dialogOpen) return;
                            final previousUpload = preparedImage;
                            final upload = _service.prepareImageFields(
                              eventId: eventId,
                              municipalityId: municipalityId,
                              bytes: bytes,
                              contentType: ct,
                            )..ignore();
                            upload.then(
                              (_) {
                                if (dialogOpen && preparedImage == upload) {
                                  setDialogState(() {
                                    photoUpload = _PhotoUploadState.ready;
                                    photoMessage = '';
                                  });
                                }
                              },
                              onError: (Object error) {
                                debugPrint(
                                  '[LguEvents] photo pre-upload failed: $error',
                                );
                                if (dialogOpen && preparedImage == upload) {
                                  setDialogState(() {
                                    photoUpload = _PhotoUploadState.failed;
                                    photoMessage = _photoFailureMessage(error);
                                  });
                                }
                              },
                            );
                            setDialogState(() {
                              pickedBytes = bytes;
                              pickedContentType = ct;
                              preparedImage = upload;
                              photoUpload = _PhotoUploadState.uploading;
                              photoMessage = '';
                              removeImage = false;
                            });
                            if (previousUpload != null) {
                              unawaited(
                                _service.discardPreparedUpload(
                                  eventId: eventId,
                                  prepared: previousUpload,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.photo_library_outlined, size: 18),
                          label: Text(
                            pickedBytes != null ||
                                    (!removeImage &&
                                        (existingImage?.isNotEmpty ?? false))
                                ? 'Change photo'
                                : 'Add photo',
                          ),
                        ),
                        if ((!removeImage &&
                                (existingImage?.isNotEmpty ?? false)) ||
                            pickedBytes != null)
                          TextButton(
                            onPressed: () {
                              final pending = preparedImage;
                              setDialogState(() {
                                pickedBytes = null;
                                preparedImage = null;
                                photoUpload = _PhotoUploadState.none;
                                photoMessage = '';
                                removeImage = true;
                              });
                              unawaited(
                                _service.discardPreparedUpload(
                                  eventId: eventId,
                                  prepared: pending,
                                ),
                              );
                            },
                            child: const Text('Remove photo'),
                          ),
                        OutlinedButton.icon(
                          onPressed: extraImages.length >=
                                  LguEventService.maxGalleryImages
                              ? null
                              : () async {
                                  final file = await _picker.pickImage(
                                    source: ImageSource.gallery,
                                    imageQuality: 82,
                                    maxWidth: 1600,
                                  );
                                  if (file == null || !dialogOpen) return;
                                  final bytes = await file.readAsBytes();
                                  if (bytes.isEmpty || !dialogOpen) return;
                                  setDialogState(() => extraImages.add(bytes));
                                },
                          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                          label: Text(
                            'More photos (${extraImages.length}/${LguEventService.maxGalleryImages})',
                          ),
                        ),
                      ],
                    ),
                    if (extraImages.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '${extraImages.length} extra photo${extraImages.length == 1 ? '' : 's'} will be saved with this event. The first photo stays the cover.',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: submitting
                    ? null
                    : () {
                  if (municipalityId.isEmpty) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Your LGU municipality is still loading. Try again in a moment.',
                        ),
                      ),
                    );
                    return;
                  }
                  final title = titleController.text.trim();
                  if (title.isEmpty) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      const SnackBar(content: Text('Please enter a title.')),
                    );
                    return;
                  }
                  final resolvedType = LguEventService.normalizeType(selectedType);
                  final scheduleError = LguEventService.validateSchedule(
                    startDate: startDate,
                    endDate: endDate,
                    allDay: allDay,
                    startHour: startTime.hour,
                    startMinute: startTime.minute,
                    endHour: endTime.hour,
                    endMinute: endTime.minute,
                  );
                  if (scheduleError != null) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(content: Text(scheduleError)),
                    );
                    return;
                  }
                  final startWall = DateTime(
                    startDate.year,
                    startDate.month,
                    startDate.day,
                    allDay ? 0 : startTime.hour,
                    allDay ? 0 : startTime.minute,
                  );
                  final endWall = DateTime(
                    endDate.year,
                    endDate.month,
                    endDate.day,
                    allDay ? 0 : endTime.hour,
                    allDay ? 0 : endTime.minute,
                  );
                  setDialogState(() => submitting = true);
                  Navigator.pop(
                    dialogContext,
                    _PostDraft(
                      eventId: eventId,
                      isNew: existing == null,
                      title: title,
                      content: contentController.text.trim(),
                      type: resolvedType,
                      startsAt: startWall,
                      endsAt: endWall,
                      allDay: allDay,
                      galleryBytes: List<Uint8List>.from(extraImages),
                      imageBytes: pickedBytes,
                      imageContentType: pickedContentType,
                      // A failed pre-upload is retried from the bytes.
                      preparedImage: photoUpload == _PhotoUploadState.failed
                          ? null
                          : preparedImage,
                      removeImage: removeImage && pickedBytes == null,
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: widget.primaryColor,
                ),
                icon: submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        existing == null
                            ? Icons.send_rounded
                            : Icons.check_rounded,
                        size: 18,
                      ),
                label: Text(
                  submitting
                      ? 'Saving…'
                      : existing == null
                          ? 'Publish'
                          : (scheduleOnly ? 'Save schedule' : 'Save'),
                ),
              ),
            ],
          ),
        );
      },
    );
    dialogOpen = false;

    // The route keeps building during its exit transition; dispose after it.
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      titleController.dispose();
      contentController.dispose();
    });

    if (draft != null && mounted) {
      unawaited(_submitDraft(draft, original: existing));
    } else {
      unawaited(
        _service.discardPreparedUpload(
          eventId: eventId,
          prepared: preparedImage,
        ),
      );
    }
  }

  String _photoFailureMessage(Object error) {
    final raw = error is StateError ? error.message : error.toString();
    final message = raw.replaceFirst('Bad state: ', '').trim();
    if (message.startsWith('Photo must be') ||
        message.startsWith('Use a JPG') ||
        message.startsWith('That image file')) {
      return message;
    }
    return 'Photo upload failed. Please retry.';
  }

  String _scheduleHint({
    required bool allDay,
    required DateTime startDate,
    required DateTime endDate,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
  }) {
    final error = LguEventService.validateSchedule(
      startDate: startDate,
      endDate: endDate,
      allDay: allDay,
      startHour: startTime.hour,
      startMinute: startTime.minute,
      endHour: endTime.hour,
      endMinute: endTime.minute,
    );
    if (error != null) return error;
    final days = LguEventService.durationDaysForRange(
      startDate: startDate,
      endDate: endDate,
    );
    final when = allDay ? 'all day' : '${_hhmm(startTime)}–${_hhmm(endTime)}';
    return 'Duration: $days day${days == 1 ? '' : 's'} · $when · Asia/Manila. '
        'It goes live at the start and expires at the end.';
  }

  String _hhmm(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  Widget _schedulePickers({
    required BuildContext context,
    required bool allDay,
    required DateTime startDate,
    required DateTime endDate,
    required TimeOfDay startTime,
    required TimeOfDay endTime,
    required ValueChanged<DateTime> onStartDate,
    required ValueChanged<DateTime> onEndDate,
    required ValueChanged<TimeOfDay> onStartTime,
    required ValueChanged<TimeOfDay> onEndTime,
  }) {
    final first = DateTime.now().subtract(const Duration(days: 365));
    final last = DateTime.now().add(const Duration(days: 730));
    Future<void> pickDate({
      required DateTime current,
      required ValueChanged<DateTime> onPicked,
    }) async {
      final picked = await showDatePicker(
        context: context,
        initialDate: current,
        firstDate: first,
        lastDate: last,
      );
      if (picked != null) onPicked(picked);
    }

    Future<void> pickTime({
      required TimeOfDay current,
      required ValueChanged<TimeOfDay> onPicked,
    }) async {
      final picked = await showTimePicker(context: context, initialTime: current);
      if (picked != null) onPicked(picked);
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _scheduleTile(
                label: 'Start date',
                value: _ymd(startDate),
                icon: Icons.calendar_month_rounded,
                onTap: () => pickDate(current: startDate, onPicked: onStartDate),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _scheduleTile(
                label: 'End date',
                value: _ymd(endDate),
                icon: Icons.event_rounded,
                onTap: () => pickDate(current: endDate, onPicked: onEndDate),
              ),
            ),
          ],
        ),
        if (!allDay) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _scheduleTile(
                  label: 'Start time',
                  value: _hhmm(startTime),
                  icon: Icons.schedule_rounded,
                  onTap: () => pickTime(current: startTime, onPicked: onStartTime),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _scheduleTile(
                  label: 'End time',
                  value: _hhmm(endTime),
                  icon: Icons.schedule_rounded,
                  onTap: () => pickTime(current: endTime, onPicked: onEndTime),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _ymd(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  Widget _scheduleTile({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppTheme.cardBackground,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: widget.primaryColor),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: AppTheme.unselectedMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteEvent(Map<String, dynamic> event) async {
    final id = event['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final isLive = LguEventService.isVisibleToTourists(event);
    final title = event['title']?.toString().trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete event?'),
        content: Text(
          isLive
              ? '“${title?.isNotEmpty == true ? title : 'This event'}” is live. '
                  'Deleting removes it for tourists and other LGUs. '
                  'This cannot be undone.'
              : 'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final source = _sourceCollection(event);
    try {
      await _service.deleteEvent(
        id,
        municipalityId: _municipalityId,
        sourceCollection: source,
      );
      LguEventService.invalidateEventsCache();
      if (mounted) {
        setState(() => _removeLocal(id, sourceCollection: source));
      }
      unawaited(_load(silent: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Event deleted.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete: $e')),
      );
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'Ongoing':
      case 'approved':
        return const Color(0xFF16A34A);
      case 'Upcoming':
        return const Color(0xFF2563EB);
      case 'Scheduled':
        return const Color(0xFFD97706);
      case 'Expired':
        return AppTheme.unselectedMuted;
      case 'rejected':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFFD97706);
    }
  }

  @override
  Widget build(BuildContext context) {
    final municipalityId = _municipalityId;
    if (municipalityId.isEmpty) {
      return const Center(
        child: Text(
          'Loading your LGU…',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showChrome)
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Events & Posts',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    Text(
                      '${widget.municipalityName ?? municipalityId} — live province feed (auto-published)',
                      style: TextStyle(color: AppTheme.unselectedMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          )
        else
          const SizedBox.shrink(),
        if (widget.showChrome) const SizedBox(height: 14),
        if (_loadError != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _loadError!,
                    style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _loadError = null;
                    });
                    _listen();
                    unawaited(_load(silent: false));
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 720;
            final tabs = _segmentedTabs();
            if (widget.readOnly) return tabs;
            final create = FilledButton.icon(
              onPressed: () => _showEventDialog(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New post'),
              style: FilledButton.styleFrom(
                backgroundColor: widget.primaryColor,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            );
            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tabs,
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerRight, child: create),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: tabs),
                const SizedBox(width: 12),
                create,
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        Expanded(child: _buildTabBody(_tabController.index)),
      ],
    );
  }

  Color _tabCountColor(int index) {
    switch (index) {
      case 1:
        return widget.primaryColor;
      case 2:
        return const Color(0xFF2563EB);
      default:
        return const Color(0xFF16A34A);
    }
  }

  static const _tabIcons = [
    Icons.public_rounded,
    Icons.article_outlined,
    Icons.calendar_month_rounded,
  ];

  Widget _segmentedTabs() {
    final index = _tabController.index;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Material(
                  color: index == i ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  elevation: index == i ? 1 : 0,
                  shadowColor: Colors.black26,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _tabController.animateTo(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _tabIcons[i],
                            size: 16,
                            color: index == i ? widget.primaryColor : AppTheme.unselectedMuted,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _tabs[i],
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: index == i ? AppTheme.textPrimary : AppTheme.unselectedMuted,
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _tabCountColor(i).withValues(alpha: index == i ? 0.14 : 0.08),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${_countForTab(i)}',
                              style: TextStyle(
                                color: _tabCountColor(i),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  int _calendarCount() {
    final days = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0).day;
    return _filteredCalendarPosts().where((event) {
      for (var day = 1; day <= days; day++) {
        if (LguEventService.occursOnDay(
          event,
          DateTime(_calendarMonth.year, _calendarMonth.month, day),
        )) {
          return true;
        }
      }
      return false;
    }).length;
  }

  Widget _scrollBody(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 960.0;
        return SingleChildScrollView(
          child: SizedBox(
            width: width,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        );
      },
    );
  }

  Widget _postList(List<Map<String, dynamic>> events, {Widget? header}) {
    return _scrollBody([
      if (header != null) ...[
        header,
        const SizedBox(height: 12),
      ],
      _eventCardGrid(events),
      const SizedBox(height: 24),
    ]);
  }

  Widget _buildTabBody(int index) {
    if (_loading && _allEvents.isEmpty) {
      return const ShimmerScope(child: SkeletonListTiles(count: 3));
    }
    if (index == 2) return _buildCalendar();
    if (index == 1) {
      final mine = _myPosts();
      if (mine.isEmpty) {
        return _scrollBody([
          _emptyFeed('No posts from your LGU yet.', index),
        ]);
      }
      return _scrollBody([
        _eventCardGrid(mine),
        const SizedBox(height: 24),
      ]);
    }
    final filtered = _filteredProvince();
    if (filtered.isEmpty) {
      return _scrollBody([
        _liveFilters(),
        const SizedBox(height: 12),
        _emptyFeed('No live province posts for this filter yet.', index),
      ]);
    }
    return _postList(filtered, header: _liveFilters());
  }

  Widget _liveFilters() {
    const filters = <(String, String)>[
      ('all', 'All'),
      ('mine', 'My LGU'),
      ('events', 'Events'),
      ('announcements', 'Announcements'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final filter in filters)
          ChoiceChip(
            label: Text(filter.$2),
            selected: _liveFilter == filter.$1,
            selectedColor: widget.primaryColor.withValues(alpha: 0.12),
            backgroundColor: const Color(0xFFF8FAFC),
            showCheckmark: false,
            labelStyle: TextStyle(
              color: _liveFilter == filter.$1 ? widget.primaryColor : AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
            side: BorderSide(
              color: _liveFilter == filter.$1 ? widget.primaryColor : AppTheme.border,
            ),
            onSelected: (_) => setState(() => _liveFilter = filter.$1),
          ),
      ],
    );
  }

  Widget _emptyFeed(String emptyMessage, int index) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          children: [
            Icon(
              index == 1
                  ? Icons.check_circle_outline_rounded
                  : index == 2
                      ? Icons.cancel_outlined
                      : Icons.hourglass_empty_rounded,
              size: 36,
              color: _tabCountColor(index).withValues(alpha: 0.7),
            ),
            const SizedBox(height: 10),
            Text(
              emptyMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.unselectedMuted, height: 1.35),
            ),
          ],
        ),
      );
  }

  Color _typeColor(String type) {
    switch (LguEventService.normalizeType(type)) {
      case LguEventService.typePromo:
        return const Color(0xFF7C3AED);
      case LguEventService.typeAlert:
        return const Color(0xFFDC2626);
      case LguEventService.typeGeneral:
        return const Color(0xFF2563EB);
      default:
        return widget.primaryColor;
    }
  }

  Widget _buildCalendar() {
    final selected = _selectedCalendarDay;
    final posts = _filteredCalendarPosts();
    final hits = selected == null
        ? const <Map<String, dynamic>>[]
        : _sorted(
            posts
                .where((event) => LguEventService.occursOnDay(event, selected))
                .toList(),
          );

    final calendar = LguEventsCalendar(
      month: _calendarMonth,
      events: posts,
      accent: widget.primaryColor,
      selectedDay: selected,
      viewMode: _calendarViewMode,
      onViewModeChanged: (mode) => setState(() => _calendarViewMode = mode),
      onMonthChanged: (month) => setState(() {
        _calendarMonth = DateTime(month.year, month.month);
        final day = _selectedCalendarDay;
        if (day == null ||
            day.year != month.year ||
            day.month != month.month) {
          _selectedCalendarDay = null;
        }
      }),
      onDaySelected: (day) => setState(() => _selectedCalendarDay = day),
      onEventTap: _openEventDetails,
    );

    // ── Events & Announcements header ─────────────────────────────────────
    final sectionHeader = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Events & Announcements',
                style: TextStyle(
                  color: Color(0xFF1F2937),
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                  letterSpacing: -0.2,
                ),
              ),
              if (selected != null) ...[
                const SizedBox(height: 2),
                Text(
                  '${_weekdayName(selected)}, ${_longDate(selected)}'
                  ' · ${hits.length} event${hits.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: widget.primaryColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: () => _tabController.animateTo(0),
          icon: const Icon(Icons.arrow_forward_rounded, size: 14),
          label: const Text('View all events'),
          style: OutlinedButton.styleFrom(
            foregroundColor: widget.primaryColor,
            side: BorderSide(color: widget.primaryColor.withValues(alpha: 0.5)),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );

    return _scrollBody([
      calendar,
      const SizedBox(height: 24),
      sectionHeader,
      const SizedBox(height: 14),
      if (selected == null)
        _softPanel(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
            child: Text(
              'Select a date to see its events and announcements.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.unselectedMuted, height: 1.35),
            ),
          ),
        )
      else if (hits.isEmpty)
        _softPanel(
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
            child: Text(
              'Nothing scheduled on this date.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.unselectedMuted),
            ),
          ),
        )
      else
        _calendarAnnouncementCards(hits),
      const SizedBox(height: 24),
    ]);
  }

  /// Selected-day cards. Width stays compact so the photo is not a thin strip
  /// beside a long empty row. Order is the list already sorted by schedule.
  Widget _calendarAnnouncementCards(List<Map<String, dynamic>> hits) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 720.0;
        final columns = width >= 960 && hits.length > 1 ? 2 : 1;
        const gap = 12.0;
        if (columns == 1) {
          final cardWidth = width > 680 ? 680.0 : width;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < hits.length; i++) ...[
                if (i > 0) const SizedBox(height: gap),
                SizedBox(
                  width: cardWidth,
                  child: _buildCalendarAnnouncementCard(hits[i]),
                ),
              ],
            ],
          );
        }
        final cardWidth = (width - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final event in hits)
              SizedBox(
                width: cardWidth,
                child: _buildCalendarAnnouncementCard(event),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCalendarAnnouncementCard(Map<String, dynamic> event) {
    final photos = _photoSources(event);
    final status = LguEventService.displayStatus(event);
    final statusColor = _statusColor(status);
    final type = LguEventService.normalizeType(event['type']?.toString());
    final typeColor = _typeColor(type);
    final title = event['title']?.toString().trim();
    final content = _postBody(event);
    final pending = event[_kPendingKey] == true;
    final place = event['location']?.toString().trim().isNotEmpty == true
        ? event['location']!.toString().trim()
        : LguEventService.sourceMunicipalityLabel(event);
    final canManage = _canManageEvent(event);
    final startDt = LguEventService.eventStart(event);
    final isAllDay = LguEventService.isAllDay(event);

    Widget photo({
      required double height,
      double? width,
      BorderRadius? radius,
    }) {
      if (photos.isEmpty) {
        return SizedBox(
          width: width,
          height: height,
          child: const ColoredBox(
            color: Color(0xFFFFF7ED),
            child: Icon(Icons.image_outlined, color: Color(0xFFFF6B00)),
          ),
        );
      }
      final cover = _gridPhoto(
        photos.first,
        maxHeight: height,
        borderRadius: radius,
      );
      if (width == null) return cover;
      return SizedBox(width: width, child: cover);
    }

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _feedChips(
            event,
            type: type,
            typeColor: typeColor,
            status: status,
            statusColor: statusColor,
            pending: pending,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          (title == null || title.isEmpty) ? 'Untitled' : title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF1F2937),
            fontWeight: FontWeight.w700,
            fontSize: 16,
            height: 1.25,
            letterSpacing: -0.2,
          ),
        ),
        if (startDt != null) ...[
          const SizedBox(height: 8),
          _infoRow(Icons.calendar_today_rounded, _longDate(startDt), expand: true),
          if (!isAllDay) ...[
            const SizedBox(height: 4),
            _infoRow(Icons.schedule_rounded, _timeLabel(event), expand: true),
          ],
        ],
        if (place.isNotEmpty) ...[
          const SizedBox(height: 4),
          _infoRow(Icons.place_rounded, place, expand: true),
        ],
        if (content.isNotEmpty) ...[
          const SizedBox(height: 10),
          EventDescriptionText(
            text: content,
            maxLines: 4,
            style: const TextStyle(
              color: Color(0xFF374151),
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ],
    );

    return _MyPostCardFrame(
      onTap: () => _openEventDetails(event),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final sideBySide = constraints.maxWidth >= 420;
          final imageWidth = constraints.maxWidth >= 560 ? 228.0 : 200.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (sideBySide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    photo(
                      width: imageWidth,
                      height: 210,
                      radius: const BorderRadius.only(
                        topLeft: Radius.circular(11),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                        child: details,
                      ),
                    ),
                  ],
                )
              else ...[
                photo(height: 200),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                  child: details,
                ),
              ],
              if (canManage)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                  child: _previewActions(event, pending, rowAt: 280),
                )
              else
                const SizedBox(height: 12),
            ],
          );
        },
      ),
    );
  }

  Widget _infoRow(IconData icon, String text, {bool expand = false}) {
    final label = Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          color: AppTheme.unselectedMuted,
          fontSize: 12.5,
          fontWeight: FontWeight.w600),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AppTheme.unselectedMuted),
        const SizedBox(width: 5),
        expand ? Expanded(child: label) : Flexible(child: label),
      ],
    );
  }

  static const _eventPhotoBg = Color(0xFFF3F4F6);

  Widget _containedPhoto(Widget image) {
    return ColoredBox(color: _eventPhotoBg, child: image);
  }

  String _timeLabel(Map<String, dynamic> event) {
    if (LguEventService.isAllDay(event)) return 'All day';
    final start = LguEventService.eventStart(event);
    final end = LguEventService.eventEnd(event);
    if (start == null) return '';
    String fmt(DateTime dt) {
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final ap = dt.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m $ap';
    }
    return end == null ? fmt(start) : '${fmt(start)} - ${fmt(end)}';
  }

  String _weekdayName(DateTime day) {
    const names = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    return names[day.weekday - 1];
  }

  Widget _eventCardGrid(List<Map<String, dynamic>> hits) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 960.0;
        const gap = 16.0;
        const maxCardWidth = 450.0;
        final columns = width >= (400 * 3 + gap * 2)
            ? 3
            : width >= (360 * 2 + gap)
                ? 2
                : 1;
        final slot = (width - gap * (columns - 1)) / columns;
        final cardWidth = slot > maxCardWidth ? maxCardWidth : slot;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          alignment: WrapAlignment.start,
          children: [
            for (final event in LguEventService.mergeUnique(hits))
              SizedBox(
                key: ValueKey(LguEventService.canonicalKey(event)),
                width: cardWidth,
                child: _buildGridCard(event),
              ),
          ],
        );
      },
    );
  }

  void _openEventDetails(Map<String, dynamic> event) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              child: _buildPreviewCard(event, forceExpanded: true),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGridCard(Map<String, dynamic> event) {
    final status = LguEventService.displayStatus(event);
    final statusColor = _statusColor(status);
    final type = LguEventService.normalizeType(event['type']?.toString());
    final typeColor = _typeColor(type);
    final title = event['title']?.toString().trim();
    final content = _postBody(event);
    final pending = event[_kPendingKey] == true;
    final place = event['location']?.toString().trim().isNotEmpty == true
        ? event['location'].toString().trim()
        : LguEventService.sourceMunicipalityLabel(event);
    final photos = _photoSources(event);
    final canManage = _canManageEvent(event);

    return _MyPostCardFrame(
      onTap: () => _openEventDetails(event),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (photos.isNotEmpty)
            _gridPhoto(photos.first, maxHeight: 220),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _feedChips(
                    event,
                    type: type,
                    typeColor: typeColor,
                    status: status,
                    statusColor: statusColor,
                    pending: pending,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  (title == null || title.isEmpty) ? 'Untitled' : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    height: 1.25,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_scheduleLine(event)} · $place',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.unselectedMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                if (content.isNotEmpty)
                  EventDescriptionText(
                    text: content,
                    maxLines: 3,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                if (canManage) ...[
                  const SizedBox(height: 10),
                  _previewActions(event, pending),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _softPanel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: widget.primaryColor.withValues(alpha: 0.16)),
      ),
      child: child,
    );
  }

  String _dayCountLabel(int events, int announcements) {
    if (events == 0 && announcements == 0) return 'None';
    final parts = <String>[];
    if (events > 0) {
      parts.add(events == 1 ? '1 event' : '$events events');
    }
    if (announcements > 0) {
      parts.add(
        announcements == 1 ? '1 announcement' : '$announcements announcements',
      );
    }
    return parts.join(' · ');
  }

  // ignore: unused_element
  Widget _selectedDayHeader(DateTime day, int count) {
    final events = count == 0
        ? 0
        : _filteredCalendarPosts()
            .where(
              (event) =>
                  LguEventService.occursOnDay(event, day) &&
                  !_isAnnouncement(event),
            )
            .length;
    final announcements = count - events;
    final label = _dayCountLabel(events, announcements);
    const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                weekdays[day.weekday - 1].toUpperCase(),
                style: TextStyle(
                  color: widget.primaryColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _longDate(day),
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: widget.primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: widget.primaryColor,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  List<Object> _photoSources(Map<String, dynamic> event) {
    final photos = <Object>[];
    final local = event[_kLocalImageKey];
    if (local is Uint8List && local.isNotEmpty) photos.add(local);
    final embedded = _embeddedPhotoBytes(event);
    if (embedded != null &&
        !photos.any((item) => item is Uint8List && item == embedded)) {
      photos.add(embedded);
    }
    for (final url in LguEventService.imageUrlsOf(event)) {
      if (url.startsWith('data:image')) continue;
      if (!photos.contains(url)) photos.add(url);
    }
    return photos;
  }

  Uint8List? _embeddedPhotoBytes(Map<String, dynamic> event) {
    final raw = event['imageBase64'] ?? event['image_base64'];
    if (raw is Uint8List && raw.isNotEmpty) return raw;
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    try {
      final payload = text.startsWith('data:image')
          ? text.substring(text.indexOf(',') + 1)
          : text;
      final bytes = base64Decode(payload);
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  Widget _buildPreviewCard(
    Map<String, dynamic> event, {
    bool forceExpanded = false,
  }) {
    final id = event['id']?.toString() ?? '';
    final status = LguEventService.displayStatus(event);
    final statusColor = _statusColor(status);
    final type = LguEventService.normalizeType(event['type']?.toString());
    final typeColor = _typeColor(type);
    final title = event['title']?.toString().trim();
    final content = _postBody(event);
    final pending = event[_kPendingKey] == true;
    final place = event['location']?.toString().trim().isNotEmpty == true
        ? event['location'].toString().trim()
        : LguEventService.sourceMunicipalityLabel(event);
    final expanded = forceExpanded || _expandedPosts.contains(id);
    final long = content.length > 180;

    final photos = _photoSources(event);
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardBackground,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (forceExpanded && photos.isNotEmpty)
            _gridPhoto(photos.first, maxHeight: 480)
          else
            _heroBanner(
            event,
            photos: photos,
            chips: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ..._feedChips(
                  event,
                  type: type,
                  typeColor: typeColor,
                  status: status,
                  statusColor: statusColor,
                  pending: pending,
                  onDark: photos.isNotEmpty,
                ),
                _metaChip(
                  _isOwnEvent(event)
                      ? 'From your LGU'
                      : 'From $place',
                  widget.primaryColor,
                  onDark: photos.isNotEmpty,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (title == null || title.isEmpty) ? 'Untitled' : title,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    height: 1.25,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.schedule_rounded, size: 14, color: AppTheme.unselectedMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${_scheduleLine(event)} · $place',
                        style: TextStyle(
                          color: AppTheme.unselectedMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (content.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  EventDescriptionText(
                    text: content,
                    maxLines: expanded ? null : 3,
                    overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                    selectable: expanded,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13.5,
                      height: 1.45,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (long && !forceExpanded)
                    TextButton(
                      onPressed: () => setState(() {
                        if (expanded) {
                          _expandedPosts.remove(id);
                        } else {
                          _expandedPosts.add(id);
                        }
                      }),
                      style: TextButton.styleFrom(
                        foregroundColor: widget.primaryColor,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(expanded ? 'Show less' : 'Read more'),
                    ),
                ],
                if (_canManageEvent(event)) ...[
                  const SizedBox(height: 12),
                  _previewActions(event, pending),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroBanner(
    Map<String, dynamic> event, {
    required List<Object> photos,
    required Widget chips,
  }) {
    final id = event['id']?.toString() ?? '';
    final index = photos.isEmpty ? 0 : (_photoIndex[id] ?? 0) % photos.length;
    final frame = SizedBox(
      height: photos.isEmpty ? 92 : 220,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photos.isEmpty)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    widget.primaryColor.withValues(alpha: 0.16),
                    const Color(0xFFFFF7ED),
                  ],
                ),
              ),
            )
          else
            _photoImage(photos[index]),
          if (photos.isNotEmpty)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0x99000000)],
                  stops: [0.45, 1],
                ),
              ),
            ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: chips,
          ),
          if (photos.length > 1)
            Positioned(
              right: 12,
              top: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${index + 1}/${photos.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
    if (photos.length < 2) return frame;
    return GestureDetector(
      onTap: () => setState(() {
        _photoIndex[id] = (index + 1) % photos.length;
      }),
      child: frame,
    );
  }

  final Map<String, Uint8List> _decodedPhotoCache = {};

  Widget _gridPhoto(
    Object source, {
    double? maxHeight,
    BorderRadius? borderRadius,
  }) {
    return _MyPostCover(
      maxHeight: maxHeight,
      borderRadius: borderRadius,
      imageBuilder: (fit, width, height) => _eventPhoto(
        source,
        fit: fit,
        width: width,
        height: height,
      ),
    );
  }

  Widget _photoImage(Object source) {
    return _containedPhoto(
      _eventPhoto(source, width: double.infinity, height: double.infinity),
    );
  }

  Widget _eventPhoto(
    Object source, {
    BoxFit fit = BoxFit.contain,
    double? width,
    double? height,
  }) {
    if (source is Uint8List) {
      return Image.memory(
        source,
        fit: fit,
        alignment: Alignment.center,
        width: width,
        height: height,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    }
    final url = source.toString();
    if (url.startsWith('data:image')) {
      final cached = _decodedPhotoCache[url];
      if (cached != null) {
        return Image.memory(
          cached,
          fit: fit,
          alignment: Alignment.center,
          width: width,
          height: height,
          gaplessPlayback: true,
        );
      }
      final comma = url.indexOf(',');
      if (comma >= 0) {
        try {
          final bytes = base64Decode(url.substring(comma + 1));
          _decodedPhotoCache[url] = bytes;
          return Image.memory(
            bytes,
            fit: fit,
            alignment: Alignment.center,
            width: width,
            height: height,
            gaplessPlayback: true,
          );
        } catch (_) {}
      }
    }
    return SpotImage(
      imageUrl: url,
      fit: fit,
      width: width,
      height: height,
    );
  }

  Widget _previewActions(
    Map<String, dynamic> event,
    bool pending, {
    double rowAt = 460,
  }) {
    Widget button({
      required IconData icon,
      required String label,
      bool danger = false,
      required VoidCallback? onPressed,
    }) {
      return _dayAction(
        icon: icon,
        label: label,
        danger: danger,
        onPressed: onPressed,
      );
    }

    final edit = button(
      icon: Icons.edit_outlined,
      label: 'Edit',
      onPressed: pending ? null : () => _showEventDialog(existing: event),
    );
    final reschedule = button(
      icon: Icons.event_repeat_outlined,
      label: 'Reschedule',
      onPressed: pending
          ? null
          : () => _showEventDialog(existing: event, scheduleOnly: true),
    );
    final delete = button(
      icon: Icons.delete_outline,
      label: 'Delete',
      danger: true,
      onPressed: pending ? null : () => _deleteEvent(event),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < rowAt) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              edit,
              const SizedBox(height: 8),
              reschedule,
              const SizedBox(height: 8),
              delete,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: edit),
            const SizedBox(width: 8),
            Expanded(child: reschedule),
            const SizedBox(width: 8),
            Expanded(child: delete),
          ],
        );
      },
    );
  }

  Widget _metaChip(String label, Color color, {bool onDark = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: onDark ? Colors.white.withValues(alpha: 0.92) : color.withValues(alpha: 0.1),
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

  String _scheduleLine(Map<String, dynamic> event) {
    final start = LguEventService.eventStart(event);
    if (start == null) return 'Schedule not set';
    final days = LguEventService.eventDurationDays(event);
    if (LguEventService.isAllDay(event)) {
      return '${_longDate(start)} · All day ($days day${days == 1 ? '' : 's'})';
    }
    final end = LguEventService.eventEnd(event);
    final endText = end == null ? '' : ' – ${_hm(end)}';
    return '${_longDate(start)} · ${_hm(start)}$endText';
  }

  String _longDate(DateTime day) {
    const months = [
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
    return '${months[day.month - 1]} ${day.day}, ${day.year}';
  }

  String _hm(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

  Widget _dayAction({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool danger = false,
  }) {
    final color = danger ? const Color(0xFFDC2626) : widget.primaryColor;
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: FilledButton.styleFrom(
        elevation: 0,
        backgroundColor: color.withValues(alpha: 0.1),
        foregroundColor: color,
        disabledBackgroundColor: AppTheme.surfaceMuted,
        visualDensity: VisualDensity.compact,
        minimumSize: const Size(0, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

/// Local-only keys on optimistic event maps (never written to Firestore).
const _kPendingKey = '_pending';
const _kLocalImageKey = '_localImageBytes';

enum _PhotoUploadState { none, uploading, ready, failed }

class _PostDraft {
  const _PostDraft({
    required this.eventId,
    required this.isNew,
    required this.title,
    required this.content,
    required this.type,
    required this.startsAt,
    required this.endsAt,
    this.allDay = true,
    this.imageBytes,
    this.imageContentType,
    this.preparedImage,
    this.galleryBytes = const [],
    this.removeImage = false,
  });

  final String eventId;
  final bool isNew;
  final String title;
  final String content;
  final String type;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool allDay;
  final Uint8List? imageBytes;
  final String? imageContentType;
  final Future<Map<String, dynamic>>? preparedImage;
  final List<Uint8List> galleryBytes;
  final bool removeImage;

  int get durationDays {
    return LguEventService.durationDaysForRange(
      startDate: startsAt,
      endDate: endsAt,
    );
  }

  bool get liveNow {
    final now = LguEventService.manilaNow();
    final end = allDay
        ? DateTime(endsAt.year, endsAt.month, endsAt.day)
            .add(const Duration(days: 1))
        : endsAt;
    return !now.isBefore(startsAt) && now.isBefore(end);
  }

  DateTime get startInstant =>
      LguEventService.instantFromManilaWall(startsAt);

  DateTime get endInstant {
    final end = allDay
        ? DateTime(endsAt.year, endsAt.month, endsAt.day)
            .add(const Duration(days: 1))
        : endsAt;
    return LguEventService.instantFromManilaWall(end);
  }

  String get dateLabel =>
      '${startsAt.year}-${startsAt.month.toString().padLeft(2, '0')}-${startsAt.day.toString().padLeft(2, '0')}';

  _PostDraft withoutPreparedImage() => _PostDraft(
        eventId: eventId,
        isNew: isNew,
        title: title,
        content: content,
        type: type,
        startsAt: startsAt,
        endsAt: endsAt,
        allDay: allDay,
        imageBytes: imageBytes,
        imageContentType: imageContentType,
        galleryBytes: galleryBytes,
        removeImage: removeImage,
      );
}

class _PhotoUploadStatus extends StatelessWidget {
  const _PhotoUploadStatus({
    required this.state,
    required this.color,
    this.failedMessage = '',
  });

  final _PhotoUploadState state;
  final Color color;
  final String failedMessage;

  @override
  Widget build(BuildContext context) {
    final (Widget icon, String label, Color tone) = switch (state) {
      _PhotoUploadState.uploading => (
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
          'Uploading photo...',
          color,
        ),
      _PhotoUploadState.ready => (
          const Icon(Icons.check_circle_rounded,
              size: 14, color: Color(0xFF16A34A)),
          'Photo ready — Publish is instant',
          const Color(0xFF16A34A),
        ),
      _PhotoUploadState.failed => (
          const Icon(Icons.refresh_rounded, size: 14, color: Color(0xFFD97706)),
          failedMessage.trim().isEmpty
              ? 'Photo upload failed. Please retry.'
              : failedMessage.trim(),
          const Color(0xFFD97706),
        ),
      _PhotoUploadState.none => (const SizedBox.shrink(), '', color),
    };
    if (state == _PhotoUploadState.none) return const SizedBox.shrink();
    return Row(
      children: [
        icon,
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: tone,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _EventPhotoFrame extends StatelessWidget {
  const _EventPhotoFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ColoredBox(
        color: const Color(0xFF1E2530),
        child: SizedBox(
          width: double.infinity,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: 160,
              maxHeight: 240,
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

class _MyPostCardFrame extends StatefulWidget {
  const _MyPostCardFrame({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_MyPostCardFrame> createState() => _MyPostCardFrameState();
}

class _MyPostCardFrameState extends State<_MyPostCardFrame> {
  static const _orange = Color(0xFFFF6B00);
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _hover ? const Color(0xFFE85D00) : _orange,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: _orange.withValues(alpha: _hover ? 0.22 : 0.10),
              blurRadius: _hover ? 16 : 10,
              offset: Offset(0, _hover ? 6 : 3),
            ),
          ],
        ),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Compact My Posts cover. The sharp poster stays fully visible in the center.
/// Side gaps use a blurred cover of the same image.
class _MyPostCover extends StatelessWidget {
  const _MyPostCover({
    required this.imageBuilder,
    this.maxHeight,
    this.borderRadius,
  });

  final Widget Function(BoxFit fit, double width, double height) imageBuilder;
  final double? maxHeight;
  final BorderRadius? borderRadius;

  static const double _coverHeight = 220;

  @override
  Widget build(BuildContext context) {
    final height = maxHeight ?? _coverHeight;
    return ClipRRect(
      borderRadius: borderRadius ??
          const BorderRadius.vertical(top: Radius.circular(10)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
          return SizedBox(
            width: width,
            height: height,
            child: Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: 22,
                    sigmaY: 22,
                    tileMode: TileMode.decal,
                  ),
                  child: Transform.scale(
                    scale: 1.22,
                    child: imageBuilder(BoxFit.cover, width, height),
                  ),
                ),
                const ColoredBox(color: Color(0x59FFF7ED)),
                imageBuilder(BoxFit.contain, width, height),
              ],
            ),
          );
        },
      ),
    );
  }
}
