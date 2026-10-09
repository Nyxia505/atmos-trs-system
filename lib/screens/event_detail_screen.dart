import 'dart:ui' show ImageFilter;

import 'package:atmos_trs_system/config/app_theme.dart';
import 'package:atmos_trs_system/services/lgu_event_service.dart';
import 'package:atmos_trs_system/widgets/spot_image.dart';
import 'package:atmos_trs_system/widgets/ui_skeleton.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

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
  static const double _heroHeight = 320;

  bool _loading = false;
  String? _title;
  String? _content;
  String? _imageUrl;
  String? _municipalityName;
  String? _type;
  String? _dateLabel;
  DateTime? _publishedAt;
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
        final ts = data['publishedAt'] ?? data['createdAt'];
        if (ts is Timestamp) _publishedAt = ts.toDate();
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

  static ({Color color, IconData icon}) _typeStyle(String type, Color accent) {
    switch (LguEventService.normalizeType(type)) {
      case LguEventService.typePromo:
        return (color: const Color(0xFF7C3AED), icon: Icons.local_offer_rounded);
      case LguEventService.typeAlert:
        return (color: const Color(0xFFDC2626), icon: Icons.warning_amber_rounded);
      case LguEventService.typeGeneral:
        return (color: const Color(0xFF2563EB), icon: Icons.campaign_rounded);
      default:
        return (color: accent, icon: Icons.event_rounded);
    }
  }

  DateTime? get _postedDate {
    if (_publishedAt != null) return _publishedAt;
    final raw = _dateLabel?.trim() ?? '';
    return raw.isEmpty ? null : DateTime.tryParse(raw);
  }

  String? _formattedDate() {
    final d = _postedDate;
    if (d == null) {
      final raw = _dateLabel?.trim() ?? '';
      return raw.isEmpty ? null : raw;
    }
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${weekdays[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String? _relativeDate() {
    final d = _postedDate;
    if (d == null) return null;
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(d.year, d.month, d.day))
        .inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return '$days days ago';
    if (days < 30) {
      final w = days ~/ 7;
      return w == 1 ? '1 week ago' : '$w weeks ago';
    }
    return null;
  }

  Future<void> _share(String title, String content, String type) async {
    final mun = _municipalityName?.trim() ?? '';
    final buffer = StringBuffer()
      ..writeln(title)
      ..writeln();
    if (content.isNotEmpty) {
      buffer
        ..writeln(content)
        ..writeln();
    }
    buffer.write(
      mun.isEmpty
          ? '$type shared via ATMOS · Misamis Occidental'
          : '$type from $mun · shared via ATMOS',
    );
    try {
      await SharePlus.instance.share(
        ShareParams(text: buffer.toString(), subject: title),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sharing is not available here.')),
      );
    }
  }

  void _openFullImage(String imageUrl) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (context, _, __) => _FullImageViewer(imageUrl: imageUrl),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppTheme.primary;
    final title = (_title ?? '').trim().isEmpty ? 'Event' : _title!.trim();
    final content = (_content ?? '').trim();
    final imageUrl = _imageUrl?.trim();
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;
    final type = LguEventService.normalizeType(_type);
    final style = _typeStyle(type, accent);
    final showSkeleton = _loading && content.isEmpty;
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            stretch: true,
            expandedHeight: hasImage ? _heroHeight : 200,
            backgroundColor: style.color,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: _CircleIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: _CircleIconButton(
                  icon: Icons.share_rounded,
                  tooltip: 'Share',
                  onTap: () => _share(title, content, type),
                ),
              ),
            ],
            flexibleSpace: LayoutBuilder(
              builder: (context, constraints) {
                final collapsed =
                    constraints.maxHeight <= kToolbarHeight + topInset + 12;
                return FlexibleSpaceBar(
                  stretchModes: const [StretchMode.zoomBackground],
                  centerTitle: true,
                  title: AnimatedOpacity(
                    opacity: collapsed ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  background: hasImage
                      ? _HeroImage(
                          imageUrl: imageUrl,
                          onTap: () => _openFullImage(imageUrl),
                        )
                      : _HeroPlaceholder(color: style.color, icon: style.icon),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -24),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
                child: showSkeleton
                    ? const _DetailSkeleton()
                    : Column(
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
                          const SizedBox(height: 18),
                          if (_error != null) ...[
                            _ErrorBanner(message: _error!),
                            const SizedBox(height: 16),
                          ],
                          Row(
                            children: [
                              _TypeBadge(
                                label: type,
                                icon: style.icon,
                                color: style.color,
                              ),
                              const Spacer(),
                              if (_relativeDate() != null)
                                Text(
                                  _relativeDate()!,
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                              height: 1.2,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _InfoCard(
                            rows: [
                              if ((_municipalityName ?? '').trim().isNotEmpty)
                                _InfoRowData(
                                  icon: Icons.account_balance_rounded,
                                  label: 'Posted by',
                                  value:
                                      '${_municipalityName!.trim()} Tourism Office',
                                ),
                              if (_formattedDate() != null)
                                _InfoRowData(
                                  icon: Icons.calendar_month_rounded,
                                  label: 'Date posted',
                                  value: _formattedDate()!,
                                ),
                            ],
                            accent: style.color,
                          ),
                          const SizedBox(height: 22),
                          Text(
                            'About this ${type.toLowerCase()}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SelectableText(
                            content.isEmpty ? 'No details provided.' : content,
                            style: TextStyle(
                              fontSize: 15.5,
                              height: 1.6,
                              color: content.isEmpty
                                  ? Colors.grey.shade500
                                  : const Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(height: 28),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: showSkeleton
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton.icon(
                onPressed: () => _share(title, content, type),
                style: FilledButton.styleFrom(
                  backgroundColor: style.color,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.ios_share_rounded, size: 20),
                label: Text(
                  'Share this ${type.toLowerCase()}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
    );
  }
}

/// Full photo on a blurred copy of itself — no letterbox bars, nothing cropped.
class _HeroImage extends StatelessWidget {
  const _HeroImage({required this.imageUrl, required this.onTap});

  final String imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
            child: SpotImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          ColoredBox(color: Colors.black.withValues(alpha: 0.18)),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: SpotImage(
                imageUrl: imageUrl,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66000000), Colors.transparent],
                stops: [0.0, 0.35],
              ),
            ),
          ),
          Positioned(
            right: 14,
            bottom: 38,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.zoom_out_map_rounded, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text(
                    'Tap to view',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPlaceholder extends StatelessWidget {
  const _HeroPlaceholder({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.25)!],
        ),
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 44, color: Colors.white),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.32),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRowData {
  const _InfoRowData({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows, required this.accent});

  final List<_InfoRowData> rows;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                indent: 64,
                color: Color(0xFFE2E8F0),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(rows[i].icon, size: 20, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rows[i].label,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rows[i].value,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: Color(0xFFDC2626), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFB91C1C),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return const ShimmerScope(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 22),
          SkeletonBox(width: 96, height: 28, borderRadius: 999),
          SizedBox(height: 16),
          SkeletonBox(height: 26),
          SizedBox(height: 8),
          SkeletonBox(width: 220, height: 26),
          SizedBox(height: 20),
          SkeletonBox(height: 120, borderRadius: 18),
          SizedBox(height: 22),
          SkeletonBox(height: 14),
          SizedBox(height: 8),
          SkeletonBox(height: 14),
          SizedBox(height: 8),
          SkeletonBox(width: 180, height: 14),
          SizedBox(height: 28),
        ],
      ),
    );
  }
}

class _FullImageViewer extends StatelessWidget {
  const _FullImageViewer({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: SpotImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: _CircleIconButton(
                icon: Icons.close_rounded,
                tooltip: 'Close',
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
