import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'admin_event_form_page.dart';
import 'data.dart';
import 'event_datetime_format.dart';
import 'firestore_loader.dart';
import 'services/storage_image_upload.dart';
import 'event_schedule.dart';
import 'services/tourism_session.dart';
import 'widgets/admin_bulk_selection_bar.dart';
import 'widgets/municipality_image.dart';
import 'widgets/optaca_portal_ui.dart';
import 'widgets/tourism_plan_ui.dart';

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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            onConfirm();
          },
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade500,
            foregroundColor: Colors.white,
          ),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(ctx);
            onConfirm();
          },
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red.shade500,
            foregroundColor: Colors.white,
          ),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
}

/// Governor portal: Firestore `announcements` plus `events` (same feed as user notifications).
class AdminAnnouncementsTab extends StatefulWidget {
  final VoidCallback onChanged;

  const AdminAnnouncementsTab({super.key, required this.onChanged});

  @override
  State<AdminAnnouncementsTab> createState() => _AdminAnnouncementsTabState();
}

class _AdminAnnouncementsTabState extends State<AdminAnnouncementsTab> {
  bool _loading = true;
  Object? _error;
  final Set<String> _selectedIds = {};
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _loading = buildNewsFeedItemsSorted().isEmpty;
    _load(silent: !_loading);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      await loadAdminGovernorCatalogsFromFirestore().timeout(
        const Duration(seconds: 30),
      );
      if (mounted) _error = null;
    } catch (e, st) {
      debugPrint('Announcements feed load: $e\n$st');
      if (mounted) _error = e;
    } finally {
      if (mounted) {
        final visible = {for (final a in tourismAnnouncements) a.id};
        _selectedIds.removeWhere((id) => !visible.contains(id));
        setState(() => _loading = false);
      }
    }
  }

  void _toggleAnnouncement(String id) {
    if (_deleting) return;
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  void _selectAllAnnouncements() {
    if (_deleting) return;
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(tourismAnnouncements.map((a) => a.id));
    });
  }

  Future<void> _deleteSelectedAnnouncements() async {
    if (_deleting || _selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final confirmed = await confirmAdminBulkDelete(
      context,
      count: count,
      nounSingular: 'announcement',
      nounPlural: 'announcements',
    );
    if (!confirmed || !mounted) return;
    final ids = Set<String>.from(_selectedIds);
    setState(() => _deleting = true);
    try {
      final result = await deleteTourismAnnouncementsByIds(ids);
      if (!mounted) return;
      setState(() {
        _selectedIds.removeAll(result.deletedIds);
        _deleting = false;
      });
      widget.onChanged();
      final deletedCount = result.deletedIds.length;
      final message = result.hasFailures
          ? '$deletedCount announcements deleted. ${result.failedIds.length} could not be deleted.'
          : '$deletedCount announcements deleted successfully.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete announcements: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && buildNewsFeedItemsSorted().isEmpty) {
      return OptacaLoadError(
        title: 'Announcements could not be loaded',
        message: '$_error',
        onRetry: _load,
      );
    }
    final feed = buildNewsFeedItemsSorted();
    final announcementCount = tourismAnnouncements.length;
    final selectedCount = _selectedIds.length;
    final allSelected =
        announcementCount > 0 && selectedCount == announcementCount;
    final selectAllTristate = selectedCount == 0
        ? false
        : allSelected
            ? true
            : null;
    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: TourismPlanUi.sectionTitleBar(
                      title: 'All announcements',
                    ),
                  ),
                  Flexible(
                    child: AdminBulkSelectionBar(
                      selectedCount: selectedCount,
                      totalVisible: announcementCount,
                      nounPlural: 'announcements',
                      onSelectAllVisible: _selectAllAnnouncements,
                      onClear: () => setState(_selectedIds.clear),
                      onDelete: _deleteSelectedAnnouncements,
                      deleting: _deleting,
                      selectAllChecked: allSelected,
                      selectAllTristate: selectAllTristate,
                      alignEnd: true,
                      compact: true,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: feed.isEmpty
                  ? const Center(
                      child: Text(
                        'No announcements or events yet.\n'
                        'Tap + for news or the calendar button for an event.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textGrey,
                          fontSize: 15,
                        ),
                      ),
                    )
                  : ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
            itemCount: feed.length,
            itemBuilder: (context, index) {
              final item = feed[index];
              switch (item) {
                case TourismNewsFeedAnnouncement(:final announcement):
                  final a = announcement;
                  final selected = _selectedIds.contains(a.id);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.06)
                        : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: selected,
                          onChanged: (_) => _toggleAnnouncement(a.id),
                        ),
                        Expanded(
                          child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: a.imagePath.isNotEmpty
                              ? buildMunicipalityImage(
                                  a.imagePath,
                                  fallback: Container(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.15),
                                    child: const Icon(
                                      Icons.campaign_outlined,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                )
                              : Container(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.15),
                                  child: const Icon(
                                    Icons.campaign_outlined,
                                    color: AppColors.primary,
                                  ),
                                ),
                        ),
                      ),
                      title: Text(
                        a.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textDark,
                        ),
                      ),
                      subtitle: Text(
                        [
                          formatEventDateTimeDisplay(a.publishedAt),
                          if (a.body.isNotEmpty)
                            a.body.length > 120
                                ? '${a.body.substring(0, 120)}…'
                                : a.body,
                        ].join('\n'),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textGrey,
                        ),
                      ),
                      isThreeLine: true,
                      trailing: SizedBox(
                        width: 88,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 22),
                              onPressed: () async {
                                await openAdminAnnouncementForm(
                                  context,
                                  existing: a,
                                );
                                await _load();
                                widget.onChanged();
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                size: 22,
                                color: Colors.red.shade400,
                              ),
                              onPressed: () {
                                _confirmAnnouncementDelete(
                                    context, a.title, () async {
                                  await deleteTourismAnnouncementFromFirestore(
                                      a.id);
                                  await _load();
                                  widget.onChanged();
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                        ),
                      ],
                    ),
                  );
                case TourismNewsFeedEvent(:final event):
                  final e = event;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: e.imagePath.isNotEmpty
                              ? buildMunicipalityImage(
                                  e.imagePath,
                                  fallback: Container(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.15),
                                    child: const Icon(
                                      Icons.event,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                )
                              : Container(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.15),
                                  child: const Icon(
                                    Icons.event,
                                    color: AppColors.primary,
                                  ),
                                ),
                        ),
                      ),
                      title: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              e.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textDark,
                              ),
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Event',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Text(
                        [
                          e.eventType,
                          formatEventScheduleSubtitle(e),
                          if (formatEventListLocationLine(e).isNotEmpty)
                            formatEventListLocationLine(e),
                          e.venue,
                          if (e.description.isNotEmpty)
                            e.description.length > 100
                                ? '${e.description.substring(0, 100)}…'
                                : e.description,
                        ].join('\n'),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textGrey,
                        ),
                      ),
                      isThreeLine: true,
                      trailing: SizedBox(
                        width: 88,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 22),
                              onPressed: () async {
                                await openAdminEventForm(context, existing: e);
                                await _load();
                                widget.onChanged();
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                size: 22,
                                color: Colors.red.shade400,
                              ),
                              onPressed: () {
                                _confirmEventDelete(context, e.title, () async {
                                  await deleteTourismEventFromFirestore(e.id);
                                  await _load();
                                  widget.onChanged();
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
              }
            },
          ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FloatingActionButton.small(
                heroTag: 'adminAnnouncementsAddEventFab',
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                tooltip: 'Add event',
                onPressed: () async {
                  await openAdminEventForm(context);
                  await _load();
                  widget.onChanged();
                },
                child: const Icon(Icons.event, size: 22),
              ),
              const SizedBox(height: 12),
              FloatingActionButton(
                heroTag: 'announcementsFab',
                backgroundColor: AppColors.primary,
                onPressed: () async {
                  await openAdminAnnouncementForm(context);
                  await _load();
                  widget.onChanged();
                },
                child: const Icon(Icons.add, color: Colors.white),
              ),
            ],
          ),
        ),
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
  Uint8List? _previewBytes;
  late final String _docId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existingId = widget.existing?.id.trim() ?? '';
    _docId = existingId.isNotEmpty ? existingId : newTourismAnnouncementDocId();
    _titleController = TextEditingController(
      text: widget.existing?.title ?? '',
    );
    _bodyController = TextEditingController(
      text: widget.existing?.body ?? '',
    );
    _imageController = TextEditingController(
      text: widget.existing?.imagePath ?? '',
    );
    _publishedAt = widget.existing?.publishedAt ?? DateTime.now();
  }

  @override
  void dispose() {
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
          const SnackBar(
            content: Text('Image uploaded to Supabase Storage.'),
          ),
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
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    _saving = true;
    if (mounted) setState(() {});
    final ann = TourismAnnouncement(
      id: _docId,
      title: _titleController.text.trim(),
      body: _bodyController.text.trim(),
      imagePath: _imageController.text.trim(),
      publishedAt: _publishedAt,
    );
    try {
      await upsertTourismAnnouncementToFirestore(ann);
      await loadAnnouncementsFromFirestore();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }
    if (mounted) Navigator.pop(context, true);
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _bodyController,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  alignLabelWithHint: true,
                ),
                minLines: 4,
                maxLines: 10,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickPublishedDate,
                      icon: const Icon(Icons.calendar_today_outlined, size: 18),
                      label: Text(formatEventDateWords(_publishedAt)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickPublishedTime,
                      icon: const Icon(Icons.schedule, size: 18),
                      label: Text(formatEventTime12(_publishedAt)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Published: ${formatEventDateTimeDisplay(_publishedAt)}',
                style: TextStyle(fontSize: 13, color: AppColors.textGrey),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _uploadingImage ? null : _pickImage,
                child: Container(
                  height: 160,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: _uploadingImage
                      ? const Center(child: CircularProgressIndicator())
                      : _previewBytes != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            height: 160,
                            width: double.infinity,
                            child: Image.memory(
                              _previewBytes!,
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      : _imageController.text.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: buildMunicipalityImage(
                            _imageController.text,
                            fallback: _buildImagePlaceholder(),
                          ),
                        )
                      : _buildImagePlaceholder(),
                ),
              ),
              const SizedBox(height: 8),
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
                child: _saving
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text('Saving...'),
                        ],
                      )
                    : const Text('Save announcement'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> openAdminAnnouncementForm(
  BuildContext context, {
  TourismAnnouncement? existing,
}) async {
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => AdminAnnouncementFormPage(existing: existing),
    ),
  );
  if (saved == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Announcement saved successfully!')),
    );
  }
  return saved == true;
}
