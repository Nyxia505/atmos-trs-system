import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/lgu_event_service.dart';
import 'package:atmos_trs_system/widgets/spot_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

/// Queues an event detail open when the app is launched from a push/notification tap.
class PendingEventOpen {
  static String? eventId;
  static String? title;
  static String? content;
  static String? type;

  static void set({
    required String id,
    String? eventTitle,
    String? eventContent,
    String? eventType,
  }) {
    if (id.trim().isEmpty) return;
    eventId = id.trim();
    title = eventTitle;
    content = eventContent;
    type = eventType;
  }

  static Future<void> consumeIfAny(BuildContext context) async {
    final id = eventId;
    if (id == null || id.isEmpty) return;
    eventId = null;
    final t = title;
    final c = content;
    final ty = type;
    title = null;
    content = null;
    type = null;
    if (!context.mounted) return;
    await EventDetailScreen.open(
      context,
      eventId: id,
      title: t,
      content: c,
      type: ty,
    );
  }
}

/// In-app event / announcement detail opened from tourist notifications.
class EventDetailScreen extends StatefulWidget {
  const EventDetailScreen({
    super.key,
    this.eventId,
    this.initialTitle,
    this.initialContent,
    this.initialImageUrl,
    this.initialMunicipalityName,
    this.initialType,
  });

  final String? eventId;
  final String? initialTitle;
  final String? initialContent;
  final String? initialImageUrl;
  final String? initialMunicipalityName;
  final String? initialType;

  /// Opens [EventDetailScreen] on the root navigator when possible.
  static Future<void> open(
    BuildContext context, {
    String? eventId,
    String? title,
    String? content,
    String? imageUrl,
    String? municipalityName,
    String? type,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EventDetailScreen(
          eventId: eventId,
          initialTitle: title,
          initialContent: content,
          initialImageUrl: imageUrl,
          initialMunicipalityName: municipalityName,
          initialType: type,
        ),
      ),
    );
  }

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  bool _loading = false;
  String? _title;
  String? _content;
  String? _imageUrl;
  String? _municipalityName;
  String? _type;
  String? _dateLabel;
  String? _error;

  @override
  void initState() {
    super.initState();
    _title = widget.initialTitle;
    _content = widget.initialContent;
    _imageUrl = widget.initialImageUrl;
    _municipalityName = widget.initialMunicipalityName;
    _type = widget.initialType ?? LguEventService.typeEvent;
    final id = widget.eventId?.trim() ?? '';
    if (id.isNotEmpty) {
      _loadFromFirestore(id);
    }
  }

  Future<void> _loadFromFirestore(String id) async {
    if (Firebase.apps.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await FirebaseFirestore.instance
          .collection(LguEventService.collection)
          .doc(id)
          .get();
      if (!doc.exists) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'This event is no longer available.';
          });
        }
        return;
      }
      final data = doc.data() ?? {};
      if (!LguEventService.isVisibleToTourists(data) &&
          (_title == null || _title!.isEmpty)) {
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'This event is not published yet.';
          });
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _title = data['title']?.toString() ?? _title;
        _content =
            data['content']?.toString() ?? data['message']?.toString() ?? _content;
        final img = LguEventService.resolveDisplayImage(data);
        if (img != null && img.isNotEmpty) _imageUrl = img;
        final mun = data['municipalityName']?.toString().trim();
        if (mun != null && mun.isNotEmpty) _municipalityName = mun;
        _type = data['type']?.toString() ?? _type;
        _dateLabel = data['date']?.toString();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load event details.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primary;
    final title = (_title ?? '').trim().isEmpty ? 'Event' : _title!.trim();
    final content = (_content ?? '').trim();
    final imageUrl = _imageUrl?.trim();
    final type = (_type ?? 'Event').trim();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        title: Text(
          type.toLowerCase() == 'event' ? 'Event' : type,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading && content.isEmpty && (imageUrl == null || imageUrl.isEmpty)
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.zero,
              children: [
                if (imageUrl != null && imageUrl.isNotEmpty)
                  ColoredBox(
                    color: const Color(0xFF1E2530),
                    child: AspectRatio(
                      aspectRatio: 16 / 10,
                      child: SpotImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                  )
                else
                  Container(
                    height: 160,
                    width: double.infinity,
                    color: accent.withValues(alpha: 0.12),
                    alignment: Alignment.center,
                    child: Icon(Icons.event_rounded, size: 56, color: accent),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_error != null) ...[
                        Text(
                          _error!,
                          style: const TextStyle(color: Color(0xFFDC2626)),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Chip(
                            label: Text(type),
                            backgroundColor: accent.withValues(alpha: 0.12),
                            side: BorderSide.none,
                          ),
                          if ((_municipalityName ?? '').trim().isNotEmpty)
                            Chip(
                              avatar: Icon(Icons.location_city_rounded,
                                  size: 16, color: accent),
                              label: Text(_municipalityName!.trim()),
                              backgroundColor: Colors.grey.shade100,
                              side: BorderSide.none,
                            ),
                          if ((_dateLabel ?? '').trim().isNotEmpty)
                            Chip(
                              avatar: const Icon(Icons.calendar_today_rounded,
                                  size: 14),
                              label: Text(_dateLabel!.trim()),
                              backgroundColor: Colors.grey.shade100,
                              side: BorderSide.none,
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827),
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        content.isEmpty ? 'No details provided.' : content,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.5,
                          color: Color(0xFF374151),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
