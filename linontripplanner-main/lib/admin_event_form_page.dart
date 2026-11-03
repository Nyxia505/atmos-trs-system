import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'catalog_targeting.dart';
import 'data.dart';
import 'event_datetime_format.dart';
import 'firestore_loader.dart';
import 'services/auth_roles.dart';
import 'services/governor_event_types_store.dart';
import 'services/storage_image_upload.dart';
import 'widgets/catalog_image_preview.dart';

String _folderSlug(String name) {
  return name
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
      .replaceAll(RegExp(r'\s+'), '_');
}

class AdminEventFormPage extends StatefulWidget {
  final TourismEvent? existing;

  const AdminEventFormPage({super.key, this.existing});

  @override
  State<AdminEventFormPage> createState() => _AdminEventFormPageState();
}

class _AdminEventFormPageState extends State<AdminEventFormPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _venueController;
  late TextEditingController _descriptionController;
  late TextEditingController _imageController;
  late DateTime _dateTime;
  late String _eventType;
  String? _municipality;
  bool _uploadingImage = false;
  bool _saving = false;
  Uint8List? _previewBytes;
  late String _docId;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.existing?.title ?? '',
    );
    _venueController = TextEditingController(
      text: widget.existing?.venue ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.existing?.description ?? '',
    );
    _imageController = TextEditingController(
      text: widget.existing?.imagePath ?? '',
    );
    _imageController.addListener(_refreshImagePreview);
    _dateTime = widget.existing?.dateTime ?? DateTime.now();
    final existing = normalizeCatalogEventType(
      widget.existing?.eventType ?? '',
    );
    _eventType = existing.isNotEmpty ? existing : kEventTypeOptions.first;
    _municipality = catalogSelectionFromRecord(
      municipality: widget.existing?.municipality ?? '',
      audienceScope: widget.existing?.audienceScope ?? '',
      municipalityId: widget.existing?.municipalityId ?? '',
    );
    _docId = widget.existing?.id ?? '';
    _loadCustomEventTypes();
  }

  Future<void> _loadCustomEventTypes() async {
    await loadGovernorEventTypesFromFirestore();
    if (!mounted) return;
    setState(() {});
  }

  void _refreshImagePreview() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _imageController.removeListener(_refreshImagePreview);
    _titleController.dispose();
    _venueController.dispose();
    _descriptionController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _dateTime,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) {
      setState(() {
        _dateTime = DateTime(
          d.year,
          d.month,
          d.day,
          _dateTime.hour,
          _dateTime.minute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (t != null) {
      setState(() {
        _dateTime = DateTime(
          _dateTime.year,
          _dateTime.month,
          _dateTime.day,
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
      final slug = _folderSlug(
        _titleController.text.trim().isEmpty
            ? 'event'
            : _titleController.text.trim(),
      );
      // File bytes → Supabase Storage (`tourist-images/events/...`).
      // Firestore only stores the returned public URL on save.
      final url = await uploadTourismCatalogImage(bytes, 'events/$slug');
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
        final network =
            e.toString().contains('network-request-failed') ||
            e.toString().contains('SocketException') ||
            e.toString().contains('ClientException');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              network
                  ? 'Image upload timed out. Check your connection, then tap the image to retry — or Save without an image.'
                  : 'Image upload failed: $e',
            ),
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
          .collection(kEventsCollection)
          .doc()
          .id;
    }

    // Retry pending image upload before writing Firestore (URL may still be empty).
    if (_imageController.text.trim().isEmpty &&
        _previewBytes != null &&
        _previewBytes!.isNotEmpty) {
      setState(() => _uploadingImage = true);
      try {
        final slug = _folderSlug(
          _titleController.text.trim().isEmpty
              ? 'event'
              : _titleController.text.trim(),
        );
        final url = await uploadTourismCatalogImage(
          _previewBytes!,
          'events/$slug',
        );
        if (mounted) _imageController.text = url;
      } catch (e) {
        if (mounted) {
          setState(() => _uploadingImage = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Could not upload image ($e). Saving event without image.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _uploadingImage = false);
      }
    }

    final ev = TourismEvent(
      id: _docId,
      title: _titleController.text.trim(),
      imagePath: _imageController.text.trim(),
      venue: _venueController.text.trim(),
      municipality: catalogMunicipalityForSelection(_municipality),
      dateTime: _dateTime,
      eventType: _eventType,
      description: _descriptionController.text.trim(),
      audienceScope: catalogAudienceScopeForSelection(_municipality),
    );
    try {
      await upsertTourismEventToFirestore(ev);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save event: $e'),
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

  bool get _canAddEventTypes => AuthRoles.isGovernorPortalUser();

  List<String> get _eventTypeChoices =>
      governorEventTypeChoices(selected: _eventType);

  Widget _section(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: Color(0xFF1F2937),
        ),
      ),
    );
  }

  Future<void> _onEventTypeChanged(String? value) async {
    if (value == kAddEventTypeValue) {
      final created = await _promptNewEventType();
      if (!mounted) return;
      if (created != null) setState(() => _eventType = created);
      return;
    }
    if (value == null || value.isEmpty) return;
    setState(() => _eventType = value);
  }

  Future<String?> _promptNewEventType() async {
    final controller = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        String? error;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add event type'),
              content: TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Event type',
                  hintText: 'e.g. Cultural Festival, Sports Event',
                  errorText: error,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (value) {
                  final label = normalizeCatalogEventType(value);
                  if (label.isEmpty) {
                    setDialogState(() => error = 'Enter an event type');
                    return;
                  }
                  if (eventTypeAlreadyExists(label, _eventTypeChoices)) {
                    setDialogState(
                      () => error = 'That event type already exists',
                    );
                    return;
                  }
                  Navigator.pop(dialogContext, label);
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final label = normalizeCatalogEventType(controller.text);
                    if (label.isEmpty) {
                      setDialogState(() => error = 'Enter an event type');
                      return;
                    }
                    if (eventTypeAlreadyExists(label, _eventTypeChoices)) {
                      setDialogState(
                        () => error = 'That event type already exists',
                      );
                      return;
                    }
                    Navigator.pop(dialogContext, label);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: kCatalogOrange,
                  ),
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    final label = normalizeCatalogEventType(entered ?? '');
    if (label.isEmpty) return null;
    try {
      return await addGovernorCustomEventType(label);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ArgumentError
                  ? e.message.toString()
                  : 'Could not add type: $e',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return null;
    }
  }

  Widget _scheduleButtons() {
    final date = OutlinedButton.icon(
      onPressed: _pickDate,
      icon: const Icon(Icons.calendar_today, size: 18),
      label: Text(
        formatEventDateWords(_dateTime),
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
    );
    final time = OutlinedButton.icon(
      onPressed: _pickTime,
      icon: const Icon(Icons.schedule, size: 18),
      label: Text(
        formatEventTime12(_dateTime),
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
            const SizedBox(width: 12),
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
        _section('Event Poster'),
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
    final typeItems = [
      for (final type in _eventTypeChoices)
        DropdownMenuItem<String>(value: type, child: Text(type)),
      if (_canAddEventTypes)
        const DropdownMenuItem<String>(
          value: kAddEventTypeValue,
          child: Text('+ Add New Event Type'),
        ),
    ];
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(widget.existing != null ? 'Edit event' : 'Add event'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _section('Event Details'),
                  TextFormField(
                    controller: _titleController,
                    decoration: catalogFieldDecoration(label: 'Event title *'),
                    validator: (v) => v?.trim().isEmpty ?? true
                        ? 'Enter an event title'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: _eventTypeChoices.contains(_eventType)
                        ? _eventType
                        : _eventTypeChoices.first,
                    decoration: catalogFieldDecoration(
                      label: 'Event type *',
                      hint: 'What kind of event is this?',
                    ),
                    isExpanded: true,
                    items: typeItems,
                    onChanged: _onEventTypeChanged,
                    validator: (v) =>
                        v == null || v.isEmpty || v == kAddEventTypeValue
                        ? 'Select a category'
                        : null,
                  ),
                  const SizedBox(height: 22),
                  _section('Schedule'),
                  _scheduleButtons(),
                  const SizedBox(height: 8),
                  Text(
                    'Selected: ${formatEventDateTimeDisplay(_dateTime)}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textGrey,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _section('Location'),
                  DropdownButtonFormField<String?>(
                    value: _municipality,
                    decoration: catalogFieldDecoration(
                      label: 'Municipality *',
                      hint: 'One LGU or the whole province',
                    ),
                    hint: const Text('Select municipality or province-wide'),
                    isExpanded: true,
                    items: catalogAudienceItems(extraValue: _municipality),
                    onChanged: municipalities.isEmpty
                        ? null
                        : (v) => setState(() => _municipality = v),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Select a municipality'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _venueController,
                    decoration: catalogFieldDecoration(
                      label: 'Venue *',
                      hint: 'Specific place (e.g. plaza, gym, church)',
                    ),
                    validator: (v) =>
                        v?.trim().isEmpty ?? true ? 'Enter a venue' : null,
                  ),
                  const SizedBox(height: 22),
                  _section('Description'),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: catalogFieldDecoration(
                      label: 'Description',
                      hint: 'What visitors can expect',
                      optional: true,
                    ),
                    minLines: 3,
                    maxLines: 8,
                  ),
                  const SizedBox(height: 22),
                  _posterPicker(),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _imageController,
                    decoration: catalogFieldDecoration(
                      label: 'Image URL',
                      hint: 'Or paste a public image URL',
                      optional: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
      bottomNavigationBar: Material(
        elevation: 8,
        color: Colors.white,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: kCatalogOrange,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(_saving ? 'Saving…' : 'Save'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
