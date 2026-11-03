import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'data.dart';
import 'event_schedule.dart';
import 'firestore_loader.dart';
import 'services/storage_image_upload.dart';
import 'widgets/event_date_schedule_picker.dart';
import 'widgets/event_location_multi_select.dart';
import 'widgets/municipality_image.dart';

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
  late Set<String> _selectedLocations;
  late DateTime _rangeStart;
  late DateTime _rangeEnd;
  bool _uploadingImage = false;
  Uint8List? _previewBytes;
  late final String _docId;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final existingId = widget.existing?.id.trim() ?? '';
    _docId = existingId.isNotEmpty ? existingId : newTourismEventDocId();
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
    _dateTime = widget.existing?.dateTime ?? DateTime.now();
    final existing = widget.existing?.eventType ?? '';
    _eventType = kEventTypeOptions.contains(existing)
        ? existing
        : kEventTypeOptions.first;
    _selectedLocations = {
      for (final name in widget.existing?.locationNames ?? const <String>[])
        if (name.trim().isNotEmpty) name.trim(),
    };
    if (_selectedLocations.isEmpty) {
      _selectedLocations = {
        for (final name in splitEventLocationNames(
          widget.existing?.municipality ?? '',
        ))
          name,
      };
    }
    final existingDays = widget.existing == null
        ? <DateTime>[eventCalendarDay(_dateTime)]
        : eventExpandedCalendarDays(widget.existing!);
    _rangeStart = existingDays.isEmpty
        ? eventCalendarDay(_dateTime)
        : eventCalendarDay(existingDays.first);
    _rangeEnd = existingDays.isEmpty
        ? eventCalendarDay(_dateTime)
        : eventCalendarDay(existingDays.last);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _venueController.dispose();
    _descriptionController.dispose();
    _imageController.dispose();
    super.dispose();
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
          const SnackBar(
            content: Text('Image uploaded to Supabase Storage.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingImage = false);
        final network = e.toString().contains('network-request-failed') ||
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
    if (_saving) return;
    if (!_formKey.currentState!.validate()) {
      setState(() {
        _saveError = 'Please fill required fields (title and municipality).';
      });
      return;
    }
    if (_selectedLocations.isEmpty) {
      setState(() {
        _saveError = 'Please fill required fields (title and municipality).';
      });
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });

    try {
      // Retry pending image upload before writing Firestore (URL may still be empty).
      if (_imageController.text.trim().isEmpty &&
          _previewBytes != null &&
          _previewBytes!.isNotEmpty) {
        if (mounted) setState(() => _uploadingImage = true);
        try {
          final slug = _folderSlug(
            _titleController.text.trim().isEmpty
                ? 'event'
                : _titleController.text.trim(),
          );
          final url =
              await uploadTourismCatalogImage(_previewBytes!, 'events/$slug');
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

      final locationNames = _selectedLocations.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      var rangeStart = eventCalendarDay(_rangeStart);
      var rangeEnd = eventCalendarDay(_rangeEnd);
      if (rangeEnd.isBefore(rangeStart)) {
        final swap = rangeStart;
        rangeStart = rangeEnd;
        rangeEnd = swap;
      }
      final oneDay = rangeStart == rangeEnd;
      final ev = TourismEvent(
        id: _docId,
        title: _titleController.text.trim(),
        imagePath: _imageController.text.trim(),
        venue: _venueController.text.trim(),
        municipality: locationNames.join(', '),
        municipalities: locationNames,
        dateTime: combineEventDateAndTime(rangeStart, _dateTime),
        dateMode: oneDay
            ? TourismEventDateMode.single
            : TourismEventDateMode.range,
        eventDates: const [],
        rangeStart: oneDay ? null : rangeStart,
        rangeEnd: oneDay ? null : rangeEnd,
        eventType: _eventType,
        description: _descriptionController.text.trim(),
      );
      await upsertTourismEventToFirestore(ev);
      try {
        await loadEventsFromFirestore();
      } catch (_) {}
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = 'Save failed: $e';
        });
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
        title: Text(widget.existing != null ? 'Edit event' : 'Add event'),
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
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _eventType,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  hintText: 'Select a type',
                ),
                hint: const Text('Select a type'),
                isExpanded: true,
                items: kEventTypeOptions
                    .map(
                      (option) => DropdownMenuItem(
                        value: option,
                        child: Text(option),
                      ),
                    )
                    .toList(),
                onChanged: (v) =>
                    setState(() => _eventType = v ?? kEventTypeOptions.first),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Please select a type' : null,
              ),
              const SizedBox(height: 16),
              FormField<Set<String>>(
                validator: (_) => _selectedLocations.isEmpty
                    ? 'Please select a municipality'
                    : null,
                builder: (state) => EventLocationMultiSelect(
                  selectedNames: _selectedLocations,
                  errorText: state.errorText,
                  onChanged: (next) {
                    setState(() => _selectedLocations = next);
                    state.didChange(next);
                  },
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _venueController,
                decoration: const InputDecoration(
                  labelText: 'Venue',
                  hintText: 'e.g. plaza, gym, church',
                ),
                validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              EventDateSchedulePicker(
                timeSource: _dateTime,
                rangeStart: _rangeStart,
                rangeEnd: _rangeEnd,
                onTimeChanged: (t) => setState(() {
                  _dateTime = DateTime(
                    _dateTime.year,
                    _dateTime.month,
                    _dateTime.day,
                    t.hour,
                    t.minute,
                  );
                }),
                onRangeChanged: (start, end) => setState(() {
                  _rangeStart = start;
                  _rangeEnd = end;
                }),
              ),
              const SizedBox(height: 16),
              const Text(
                'Profile picture',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
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
                          child: Image.memory(
                            _previewBytes!,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
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
              Text(
                'Tap to pick image from device',
                style: TextStyle(fontSize: 12, color: AppColors.textGrey),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _imageController,
                decoration: const InputDecoration(
                  labelText: 'Image URL (optional, or use picker above)',
                  hintText: 'Firebase Storage URL or any image URL',
                ),
              ),
              if (_saveError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _saveError!,
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor:
                      AppColors.primary.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save',
                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> openAdminEventForm(
  BuildContext context, {
  TourismEvent? existing,
}) async {
  final size = MediaQuery.sizeOf(context);
  final saved = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: size.width < 640 ? size.width : 560,
        height: size.height * 0.9,
        child: AdminEventFormPage(existing: existing),
      ),
    ),
  );
  if (saved == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Event saved successfully!')),
    );
  }
  return saved == true;
}
