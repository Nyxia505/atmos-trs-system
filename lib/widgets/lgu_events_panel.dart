import 'dart:async';
import 'dart:typed_data';

import 'package:atmos_trs_system/services/lgu_event_service.dart';
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
    /// 0 = Province Live, 1 = My posts
    this.initialTabIndex = 0,
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

  List<Map<String, dynamic>> _myEvents = [];
  List<Map<String, dynamic>> _provinceEvents = [];
  bool _loading = true;
  bool _didLoadOnce = false;
  late final TabController _tabController;

  static const _tabs = ['Province Live', 'My posts'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, _tabs.length - 1),
    );
    _hydrateFromCacheThenLoad();
  }

  @override
  void didUpdateWidget(covariant LguEventsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.municipalityId != widget.municipalityId) {
      _didLoadOnce = false;
      _hydrateFromCacheThenLoad();
    } else if (oldWidget.initialTabIndex != widget.initialTabIndex) {
      final next = widget.initialTabIndex.clamp(0, _tabs.length - 1);
      if (_tabController.index != next) {
        _tabController.animateTo(next);
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _hydrateFromCacheThenLoad() {
    final municipalityId = widget.municipalityId?.trim() ?? '';
    if (municipalityId.isEmpty) {
      setState(() {
        _myEvents = [];
        _provinceEvents = [];
        _loading = false;
      });
      return;
    }
    final cached = LguEventService.peekEventsCache(municipalityId);
    if (cached != null) {
      setState(() {
        _myEvents = cached.mine;
        _provinceEvents = cached.province;
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
    final mun = widget.municipalityId?.trim() ?? '';
    if (mun.isEmpty) return false;
    return LguEventService.matchesMunicipality(event, mun);
  }

  List<Map<String, dynamic>> _eventsForTab(int index) {
    if (index == 1) {
      return List<Map<String, dynamic>>.from(_myEvents);
    }
    return List<Map<String, dynamic>>.from(_provinceEvents);
  }

  int _countForTab(int index) => _eventsForTab(index).length;

  Future<void> _load({bool silent = false}) async {
    final municipalityId = widget.municipalityId?.trim() ?? '';
    if (municipalityId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _myEvents = [];
        _provinceEvents = [];
        _loading = false;
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
        _myEvents = _mergeWithLocal(both.mine, _myEvents);
        _provinceEvents = _mergeWithLocal(both.province, _provinceEvents);
        _loading = false;
        _didLoadOnce = true;
      });
    } catch (e) {
      debugPrint('[LguEventsPanel] load: $e');
      if (!mounted) return;
      setState(() => _loading = false);
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

    _myEvents = apply(_myEvents);
    _provinceEvents = apply(_provinceEvents);
  }

  void _removeLocal(String id) {
    _myEvents = _myEvents.where((e) => e['id']?.toString() != id).toList();
    _provinceEvents =
        _provinceEvents.where((e) => e['id']?.toString() != id).toList();
  }

  /// Saves in the background after the dialog has already closed. The card
  /// shows "Publishing…" immediately and flips to Live when Firestore confirms.
  Future<void> _submitDraft(
    _PostDraft draft, {
    Map<String, dynamic>? original,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final municipalityId = widget.municipalityId?.trim() ?? '';
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
      'published': true,
      'municipalityId': original?['municipalityId'] ?? municipalityId,
      'municipalityName': original?['municipalityName'] ?? munName,
      'date': original?['date'] ??
          DateTime.now().toIso8601String().split('T').first,
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
                ? 'Published (${draft.type}). Tourists, LGUs, and Governor are notified.'
                : 'Updated (${draft.type}). Still live for everyone.',
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
          content: Text('Could not publish "${draft.title}": $e'),
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
    }
  }

  Future<void> _showEventDialog({Map<String, dynamic>? existing}) async {
    final municipalityId = widget.municipalityId?.trim() ?? '';
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
    var selectedType = LguEventService.normalizeType(
      existing?['type']?.toString(),
    );

    final draft = await showDialog<_PostDraft>(
      context: context,
      builder: (dialogContext) {
        final maxW = MediaQuery.sizeOf(dialogContext).width;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(existing == null ? 'New Post' : 'Edit Post'),
            content: SizedBox(
              width: maxW < 520 ? maxW - 48 : 420,
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
                            color: selected ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                          checkmarkColor: Colors.white,
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
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
                      ],
                    ),
                  ],
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
                          'Municipality is not set. Open Settings first.',
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
                  Navigator.pop(
                    dialogContext,
                    _PostDraft(
                      eventId: eventId,
                      isNew: existing == null,
                      title: title,
                      content: contentController.text.trim(),
                      type: selectedType,
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
    });

    if (draft != null && mounted) {
      unawaited(_submitDraft(draft, original: existing));
    }
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
      await _service.deleteEvent(id);
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
      case 'approved':
        return const Color(0xFF16A34A);
      case 'rejected':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFFD97706);
    }
  }

  @override
  Widget build(BuildContext context) {
    final municipalityId = widget.municipalityId?.trim() ?? '';
    if (municipalityId.isEmpty) {
      return const Center(
        child: Text('Set your municipality in Settings to manage events.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () => _showEventDialog(),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New post'),
                style: FilledButton.styleFrom(
                  backgroundColor: widget.primaryColor,
                ),
              ),
            ],
          )
        else
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _showEventDialog(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New post'),
              style: FilledButton.styleFrom(
                backgroundColor: widget.primaryColor,
              ),
            ),
          ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: TabBar(
            controller: _tabController,
            onTap: (_) => setState(() {}),
            labelColor: widget.primaryColor,
            unselectedLabelColor: const Color(0xFF6B7280),
            indicatorColor: widget.primaryColor,
            indicatorWeight: 3,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            tabs: [
              for (var i = 0; i < _tabs.length; i++)
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_tabs[i]),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _tabCountColor(i).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
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
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (_loading)
          const ShimmerScope(
            child: SkeletonListTiles(count: 3),
          )
        else
          _buildTabBody(_tabController.index),
      ],
    );
  }

  Color _tabCountColor(int index) {
    switch (index) {
      case 1:
        return widget.primaryColor;
      default:
        return const Color(0xFF16A34A);
    }
  }

  Widget _buildTabBody(int index) {
    final filtered = _eventsForTab(index);
    final emptyMessage = switch (index) {
      1 => 'No posts from your LGU yet. Tap Publish to announce an event.',
      _ =>
        'No live province events yet. When any LGU publishes, it appears here.',
    };

    if (filtered.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
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
              style: TextStyle(color: Colors.grey.shade600, height: 1.35),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _buildEventCard(filtered[i]),
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

  Widget _buildEventCard(Map<String, dynamic> event) {
    final status = LguEventService.statusOf(event);
    final statusColor = _statusColor(status);
    final imageUrl = LguEventService.resolveDisplayImage(event);
    final type = LguEventService.normalizeType(event['type']?.toString());
    final typeColor = _typeColor(type);
    final title = event['title']?.toString() ?? 'Untitled';
    final content = event['content']?.toString() ?? '';
    final fromLabel = LguEventService.sourceMunicipalityLabel(event);
    final isOwn = _isOwnEvent(event);
    final dateLabel = event['date']?.toString().trim() ?? '';
    final pending = event[_kPendingKey] == true;
    final localImage = event[_kLocalImageKey];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: status == 'rejected'
              ? const Color(0xFFFECACA)
              : status == 'approved'
                  ? const Color(0xFFBBF7D0)
                  : const Color(0xFFE5E7EB),
          width: status == 'pending' ? 1 : 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (localImage is Uint8List)
            SizedBox(
              height: 156,
              width: double.infinity,
              child: ColoredBox(
                color: const Color(0xFF1E2530),
                child: Image.memory(
                  localImage,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
            )
          else if (imageUrl != null && imageUrl.isNotEmpty)
            SizedBox(
              height: 156,
              width: double.infinity,
              child: ColoredBox(
                color: const Color(0xFF1E2530),
                child: SpotImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
          if (pending)
            LinearProgressIndicator(
              minHeight: 3,
              color: widget.primaryColor,
              backgroundColor: widget.primaryColor.withValues(alpha: 0.15),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16.5,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: (pending ? widget.primaryColor : statusColor)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        pending
                            ? 'Publishing…'
                            : LguEventService.displayStatus(event),
                        style: TextStyle(
                          color: pending ? widget.primaryColor : statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        type,
                        style: TextStyle(
                          color: typeColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: widget.primaryColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isOwn ? 'From your LGU' : 'From $fromLabel',
                        style: TextStyle(
                          color: widget.primaryColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (dateLabel.isNotEmpty)
                      Text(
                        dateLabel,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade700, height: 1.35),
                ),
                if (event['rejectedReason']?.toString().trim().isNotEmpty ??
                    false) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Reason: ${event['rejectedReason']}',
                    style: const TextStyle(
                      color: Color(0xFFDC2626),
                      fontSize: 12,
                    ),
                  ),
                ],
                if (isOwn) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: pending
                            ? null
                            : () => _showEventDialog(existing: event),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit'),
                      ),
                      OutlinedButton.icon(
                        onPressed: pending ? null : () => _deleteEvent(event),
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Delete'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
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
    this.imageBytes,
    this.imageContentType,
    this.preparedImage,
    this.removeImage = false,
  });

  final String eventId;
  final bool isNew;
  final String title;
  final String content;
  final String type;
  final Uint8List? imageBytes;
  final String? imageContentType;
  final Future<Map<String, dynamic>>? preparedImage;
  final bool removeImage;

  _PostDraft withoutPreparedImage() => _PostDraft(
        eventId: eventId,
        isNew: isNew,
        title: title,
        content: content,
        type: type,
        imageBytes: imageBytes,
        imageContentType: imageContentType,
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
