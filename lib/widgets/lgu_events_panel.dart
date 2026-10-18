import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/data/misamis_occidental_municipalities.dart';
import 'package:atmos_trs_system/services/lgu_event_service.dart';
import 'package:atmos_trs_system/widgets/lgu_events_calendar.dart';
import 'package:atmos_trs_system/widgets/spot_image.dart';
import 'package:atmos_trs_system/widgets/ui_skeleton.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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
  });

  final String? municipalityId;
  final String? municipalityName;
  final Color primaryColor;
  final int initialTabIndex;
  final bool showChrome;

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
  final Set<String> _expandedPosts = {};
  final Map<String, int> _photoIndex = {};
  final Set<String> _publishingIds = {};
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
  }

  @override
  void didUpdateWidget(covariant LguEventsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_municipalityId != _idFrom(oldWidget) ||
        oldWidget.municipalityName != widget.municipalityName) {
      _didLoadOnce = false;
      _hydrateFromCacheThenLoad();
      _listen();
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
          [...cached.mine, ...cached.province],
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
    return LguEventService.matchesMunicipality(event, mun);
  }

  bool _isAnnouncement(Map<String, dynamic> event) {
    switch (LguEventService.normalizeType(event['type']?.toString())) {
      case LguEventService.typePromo:
      case LguEventService.typeAlert:
      case LguEventService.typeGeneral:
        return true;
      default:
        return false;
    }
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
    return _applyLiveFilter(
      _allEvents.where(LguEventService.isVisibleToTourists),
    );
  }

  /// Calendar includes scheduled posts, not only posts that are live today.
  List<Map<String, dynamic>> _filteredCalendarPosts() {
    return _applyLiveFilter(
      _allEvents.where(
        (event) => LguEventService.statusOf(event) != 'rejected',
      ),
    );
  }

  int _countForTab(int index) {
    if (index == 2) return _calendarCount();
    if (index == 1) return _myPosts().length;
    return _filteredProvince().length;
  }

  List<Map<String, dynamic>> _myPosts() {
    return _allEvents.where((event) {
      if (LguEventService.statusOf(event) == 'rejected') return false;
      return _isOwnEvent(event);
    }).toList();
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
          [...both.mine, ...both.province],
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
  List<Map<String, dynamic>> _mergeWithLocal(
    List<Map<String, dynamic>> fetched,
    List<Map<String, dynamic>> local,
  ) {
    final localById = {
      for (final e in local)
        if ((e['id']?.toString() ?? '').isNotEmpty) e['id'].toString(): e,
    };
    final fetchedIds = <String>{};
    final merged = <Map<String, dynamic>>[];
    for (final e in fetched) {
      final id = e['id']?.toString() ?? '';
      fetchedIds.add(id);
      final prev = localById[id];
      if (prev != null && prev[_kPendingKey] == true) {
        merged.add(prev);
      } else if (prev != null && prev[_kLocalImageKey] is Uint8List) {
        merged.add({...e, _kLocalImageKey: prev[_kLocalImageKey]});
      } else {
        merged.add(e);
      }
    }
    final pendingNew = local.where(
      (e) =>
          e[_kPendingKey] == true &&
          !fetchedIds.contains(e['id']?.toString() ?? ''),
    );
    return [...pendingNew, ...merged];
  }

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
    final id = event['id']?.toString() ?? '';
    List<Map<String, dynamic>> apply(List<Map<String, dynamic>> list) {
      final next = List<Map<String, dynamic>>.from(list);
      final i = next.indexWhere((e) => e['id']?.toString() == id);
      if (i >= 0) {
        next[i] = event;
      } else {
        next.insert(0, event);
      }
      return next;
    }

    _allEvents = apply(_allEvents);
    _splitEvents();
  }

  void _removeLocal(String id) {
    _allEvents = _allEvents.where((e) => e['id']?.toString() != id).toList();
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
          imageBytes: draft.preparedImage == null ? draft.imageBytes : null,
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
          imageBytes: draft.preparedImage == null ? draft.imageBytes : null,
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
      LguEventService.invalidateEventsCache();
      if (mounted) {
        setState(() => _upsertLocal({...optimistic, _kPendingKey: false}));
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            draft.isNew
                ? (draft.liveNow
                    ? 'Published (${draft.type}). Tourists, LGUs, and Governor are notified.'
                    : 'Scheduled (${draft.type}). It goes live automatically at the start time (Asia/Manila).')
                : 'Updated (${draft.type}).',
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
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not save "${draft.title}": $e'),
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

  Future<void> _showEventDialog({Map<String, dynamic>? existing}) async {
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
    var dialogOpen = true;
    bool removeImage = false;
    final existingImage = LguEventService.resolveDisplayImage(existing);
    const builtInTypes = {
      LguEventService.typeEvent,
      LguEventService.typePromo,
      LguEventService.typeAlert,
      LguEventService.typeGeneral,
    };
    final rawType = existing?['type']?.toString().trim() ?? '';
    var selectedType = builtInTypes.contains(rawType)
        ? rawType
        : (rawType.isEmpty ? LguEventService.typeEvent : LguEventService.typeOther);
    final customTypeController = TextEditingController(
      text: selectedType == LguEventService.typeOther ? rawType : '',
    );
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

    final draft = await showDialog<_PostDraft>(
      context: context,
      builder: (dialogContext) {
        final maxW = MediaQuery.sizeOf(dialogContext).width;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(existing == null ? 'New Post' : 'Edit Post'),
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
                      children: LguEventService.postTypes.map((type) {
                        final selected = selectedType == type;
                        return ChoiceChip(
                          label: Text(type),
                          selected: selected,
                          onSelected: (_) =>
                              setDialogState(() => selectedType = type),
                          selectedColor: widget.primaryColor,
                          labelStyle: TextStyle(
                            color: selected ? Colors.white : AppTheme.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          checkmarkColor: Colors.white,
                        );
                      }).toList(),
                    ),
                    if (selectedType == LguEventService.typeOther) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: customTypeController,
                        decoration: const InputDecoration(
                          labelText: 'Event type',
                          hintText: 'e.g. Festival, Sports, Trade fair',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
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
                            final upload = _service.prepareImageFields(
                              eventId: eventId,
                              municipalityId: municipalityId,
                              bytes: bytes,
                              contentType: ct,
                            )..ignore();
                            upload.then(
                              (_) {
                                if (dialogOpen && preparedImage == upload) {
                                  setDialogState(
                                    () => photoUpload = _PhotoUploadState.ready,
                                  );
                                }
                              },
                              onError: (Object _) {
                                if (dialogOpen && preparedImage == upload) {
                                  setDialogState(
                                    () =>
                                        photoUpload = _PhotoUploadState.failed,
                                  );
                                }
                              },
                            );
                            setDialogState(() {
                              pickedBytes = bytes;
                              pickedContentType = ct;
                              preparedImage = upload;
                              photoUpload = _PhotoUploadState.uploading;
                              removeImage = false;
                            });
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
                            onPressed: () => setDialogState(() {
                              pickedBytes = null;
                              preparedImage = null;
                              photoUpload = _PhotoUploadState.none;
                              removeImage = true;
                            }),
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
                ),
              ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () {
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
                  final customType = customTypeController.text.trim();
                  final resolvedType = selectedType == LguEventService.typeOther
                      ? (customType.isEmpty
                          ? LguEventService.typeEvent
                          : customType)
                      : selectedType;
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
                icon: Icon(
                  existing == null ? Icons.send_rounded : Icons.check_rounded,
                  size: 18,
                ),
                label: Text(existing == null ? 'Publish' : 'Save'),
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
      customTypeController.dispose();
    });

    if (draft != null && mounted) {
      unawaited(_submitDraft(draft, original: existing));
    }
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
    try {
      await _service.deleteEvent(
        id,
        municipalityId: _municipalityId,
      );
      LguEventService.invalidateEventsCache();
      await _load(silent: false);
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
      for (var i = 0; i < events.length; i++) ...[
        if (i > 0) const SizedBox(height: 12),
        _buildPreviewCard(events[i]),
      ],
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
      return _postList(mine);
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
        : posts
            .where((event) => LguEventService.occursOnDay(event, selected))
            .toList();
    final calendar = LguEventsCalendar(
      month: _calendarMonth,
      events: posts,
      accent: widget.primaryColor,
      selectedDay: selected,
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
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1040;
        final body = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: calendar),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: _calendarDayDetail(selected, hits)),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  calendar,
                  const SizedBox(height: 16),
                  _calendarDayDetail(selected, hits),
                ],
              );
        return _scrollBody([body, const SizedBox(height: 24)]);
      },
    );
  }

  Widget _calendarDayDetail(
    DateTime? selected,
    List<Map<String, dynamic>> hits,
  ) {
    if (selected == null) {
      return _softPanel(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 12),
          child: Column(
            children: [
              Icon(Icons.touch_app_rounded, color: widget.primaryColor, size: 28),
              const SizedBox(height: 10),
              Text(
                'Select a date',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Events and announcements for that day show here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.unselectedMuted, height: 1.35),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _selectedDayHeader(selected, hits.length),
        const SizedBox(height: 12),
        if (hits.isEmpty)
          _softPanel(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 12),
              child: Text(
                'Nothing scheduled on this date.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.unselectedMuted),
              ),
            ),
          )
        else
          for (var i = 0; i < hits.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _buildPreviewCard(hits[i]),
          ],
      ],
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
    photos.addAll(LguEventService.imageUrlsOf(event));
    return photos;
  }

  Widget _buildPreviewCard(Map<String, dynamic> event) {
    final id = event['id']?.toString() ?? '';
    final status = LguEventService.displayStatus(event);
    final statusColor = _statusColor(status);
    final type = LguEventService.normalizeType(event['type']?.toString());
    final typeColor = _typeColor(type);
    final title = event['title']?.toString().trim();
    final content = event['content']?.toString().trim() ?? '';
    final isOwn = _isOwnEvent(event);
    final pending = event[_kPendingKey] == true;
    final place = event['location']?.toString().trim().isNotEmpty == true
        ? event['location'].toString().trim()
        : LguEventService.sourceMunicipalityLabel(event);
    final expanded = _expandedPosts.contains(id);
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
          _heroBanner(
            event,
            photos: photos,
            chips: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _metaChip(type, typeColor, onDark: photos.isNotEmpty),
                _metaChip(isOwn ? 'From your LGU' : 'From $place', widget.primaryColor, onDark: photos.isNotEmpty),
                _metaChip(
                  pending ? 'Publishing…' : status,
                  pending ? widget.primaryColor : statusColor,
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
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    height: 1.2,
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
                  Text(
                    content,
                    maxLines: expanded ? null : 3,
                    overflow: expanded ? TextOverflow.visible : TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                  if (long)
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
                if (isOwn) ...[
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

  Widget _memoryPhoto(Uint8List bytes) {
    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      cacheWidth: 480,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
    );
  }

  Widget _photoImage(Object source) {
    if (source is Uint8List) return _memoryPhoto(source);
    final url = source.toString();
    if (url.startsWith('data:image')) {
      final cached = _decodedPhotoCache[url];
      if (cached != null) return _memoryPhoto(cached);
      final comma = url.indexOf(',');
      if (comma >= 0) {
        try {
          final bytes = base64Decode(url.substring(comma + 1));
          _decodedPhotoCache[url] = bytes;
          return _memoryPhoto(bytes);
        } catch (_) {}
      }
    }
    return SpotImage(
      imageUrl: url,
      fit: BoxFit.cover,
      width: 168,
      height: 118,
    );
  }

  Widget _previewActions(Map<String, dynamic> event, bool pending) {
    return Row(
      children: [
        Expanded(
          child: _dayAction(
            icon: Icons.edit_outlined,
            label: 'Edit',
            onPressed: pending ? null : () => _showEventDialog(existing: event),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _dayAction(
            icon: Icons.event_repeat_outlined,
            label: 'Reschedule',
            onPressed: pending ? null : () => _showEventDialog(existing: event),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _dayAction(
            icon: Icons.delete_outline,
            label: 'Delete',
            danger: true,
            onPressed: pending ? null : () => _deleteEvent(event),
          ),
        ),
      ],
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
  const _PhotoUploadStatus({required this.state, required this.color});

  final _PhotoUploadState state;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final (Widget icon, String label, Color tone) = switch (state) {
      _PhotoUploadState.uploading => (
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
          'Uploading photo while you type…',
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
          'Upload interrupted — it will retry when you publish',
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
