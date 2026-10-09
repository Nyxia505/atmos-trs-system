import 'package:flutter/material.dart';

import 'package:atmos_trs_system/models/establishment_map_pin.dart';
import 'package:atmos_trs_system/services/establishment_gallery_service.dart';
import 'package:atmos_trs_system/services/establishment_map_pins_service.dart';
import 'package:atmos_trs_system/widgets/misamis_occidental_explore_map.dart'
    show kEstablishmentMapPinColor;

/// Full-screen tourist view of an approved establishment (gallery + location).
class EstablishmentPublicDetailScreen extends StatefulWidget {
  const EstablishmentPublicDetailScreen({
    super.key,
    required this.pin,
  });

  final EstablishmentMapPin pin;

  @override
  State<EstablishmentPublicDetailScreen> createState() =>
      _EstablishmentPublicDetailScreenState();
}

class _EstablishmentPublicDetailScreenState
    extends State<EstablishmentPublicDetailScreen> {
  late EstablishmentMapPin _pin;
  final _pageController = PageController();
  int _pageIndex = 0;
  // Kept across gallery swipes (setState) so listeners are not re-created.
  late final Stream<List<String>> _galleryStream =
      EstablishmentGalleryService.watchUrls(widget.pin.id);

  @override
  void initState() {
    super.initState();
    _pin = widget.pin;
    _refreshPin();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _refreshPin() async {
    final fresh = await EstablishmentMapPinsService.getById(_pin.id);
    if (!mounted || fresh == null) return;
    setState(() => _pin = fresh);
  }

  String get _subtitle {
    final parts = <String>[
      if (_pin.category.trim().isNotEmpty) _pin.category.trim(),
      if (_pin.barangay.trim().isNotEmpty) _pin.barangay.trim(),
      if (_pin.municipality.trim().isNotEmpty) _pin.municipality.trim(),
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final images = _pin.displayImageUrls;

    return Scaffold(
      backgroundColor: Colors.white,
      body: StreamBuilder<List<String>>(
        stream: _galleryStream,
        builder: (context, gallerySnap) {
          final liveImages = gallerySnap.data;
          final urls = (liveImages != null && liveImages.isNotEmpty)
              ? liveImages
              : images;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: MediaQuery.sizeOf(context).height * 0.42,
                pinned: true,
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                leading: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Center(
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.45),
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_rounded),
                        color: Colors.white,
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (urls.isEmpty)
                        ColoredBox(
                          color: const Color(0xFF0F172A),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.hotel_rounded,
                                  size: 56,
                                  color: kEstablishmentMapPinColor
                                      .withValues(alpha: 0.9),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Photos coming soon',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.75),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        PageView.builder(
                          controller: _pageController,
                          itemCount: urls.length,
                          onPageChanged: (i) =>
                              setState(() => _pageIndex = i),
                          itemBuilder: (context, i) {
                            return Image.network(
                              urls[i],
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => ColoredBox(
                                color: const Color(0xFF1E293B),
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 48,
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                              ),
                            );
                          },
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: EdgeInsets.fromLTRB(
                            20,
                            48,
                            20,
                            20 + (urls.length > 1 ? 8 : 0),
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.75),
                              ],
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _pin.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  height: 1.15,
                                ),
                              ),
                              if (_subtitle.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _subtitle,
                                  style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.88),
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                              if (urls.length > 1) ...[
                                const SizedBox(height: 12),
                                Row(
                                  children: List.generate(urls.length, (i) {
                                    final active = i == _pageIndex;
                                    return Container(
                                      width: active ? 18 : 7,
                                      height: 7,
                                      margin: const EdgeInsets.only(right: 5),
                                      decoration: BoxDecoration(
                                        color: active
                                            ? Colors.white
                                            : Colors.white
                                                .withValues(alpha: 0.4),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    );
                                  }),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      // Keep status bar readable
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: topInset + 8,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.35),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_pin.location.trim().isNotEmpty)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.place_outlined,
                              size: 18,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _pin.location.trim(),
                                style: TextStyle(
                                  fontSize: 14,
                                  height: 1.35,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
