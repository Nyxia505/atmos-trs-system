import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../data.dart';
import '../firestore_loader.dart';
import '../services/admin_live_collections.dart';
import '../services/reports/report_check_ins.dart';
import '../services/spot_ratings_store.dart';
import '../services/tourist_spot_unique_views_service.dart';
import '../theme/tourism_app_theme.dart';
import '../utils/spot_coordinates.dart';
import 'municipality_image.dart';
import 'osm_map_tiles.dart';

const String _kNotAvailable = 'Not Available';

/// Opens a read-only Tourist Spot details dialog for OPTACA admins.
Future<void> showAdminTouristSpotDetailsDialog(
  BuildContext context, {
  required TouristSpot spot,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      final size = MediaQuery.sizeOf(ctx);
      final wide = size.width >= 900;
      return Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: wide ? 48 : 16,
          vertical: wide ? 28 : 20,
        ),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: SizedBox(
          width: wide ? 860 : size.width,
          height: size.height * (wide ? 0.88 : 0.92),
          child: AdminTouristSpotDetailsView(initialSpot: spot),
        ),
      );
    },
  );
}

class AdminTouristSpotDetailsView extends StatefulWidget {
  const AdminTouristSpotDetailsView({super.key, required this.initialSpot});

  final TouristSpot initialSpot;

  @override
  State<AdminTouristSpotDetailsView> createState() =>
      _AdminTouristSpotDetailsViewState();
}

class _AdminTouristSpotDetailsViewState
    extends State<AdminTouristSpotDetailsView> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;
  late TouristSpot _spot;
  String? _address;
  String? _operatingHours;
  bool _docMissing = false;
  int _uniqueViews = 0;
  bool _viewsReady = false;
  int _checkInCount = 0;
  bool _checkInsReady = false;

  @override
  void initState() {
    super.initState();
    _spot = widget.initialSpot;
    _uniqueViews = TouristSpotUniqueViewsService.instance.cachedCountForSpot(
      _spot,
    );
    _viewsReady =
        TouristSpotUniqueViewsService.instance.hasConfirmedCountForSpot(_spot);
    SpotRatingsStore.instance.revision.addListener(_onStoreBump);
    TouristSpotUniqueViewsService.instance.revision.addListener(_onStoreBump);
    AdminLiveCollections.instance.revision.addListener(_onCheckInsBump);
    AdminLiveCollections.instance.retain();
    _refreshViews();
    _recountCheckIns();
    _listenToFirestoreDoc();
  }

  @override
  void dispose() {
    _docSub?.cancel();
    SpotRatingsStore.instance.revision.removeListener(_onStoreBump);
    TouristSpotUniqueViewsService.instance.revision.removeListener(
      _onStoreBump,
    );
    AdminLiveCollections.instance.revision.removeListener(_onCheckInsBump);
    AdminLiveCollections.instance.release();
    super.dispose();
  }

  void _onStoreBump() {
    if (!mounted) return;
    setState(() {
      if (TouristSpotUniqueViewsService.instance.hasConfirmedCountForSpot(
        _spot,
      )) {
        _uniqueViews = TouristSpotUniqueViewsService.instance
            .cachedCountForSpot(_spot);
        _viewsReady = true;
      }
    });
  }

  void _onCheckInsBump() {
    if (!mounted) return;
    _recountCheckIns();
  }

  Future<void> _refreshViews() async {
    await TouristSpotUniqueViewsService.instance.prefetchForSpots([_spot]);
    if (!mounted) return;
    setState(() {
      _uniqueViews =
          TouristSpotUniqueViewsService.instance.cachedCountForSpot(_spot);
      _viewsReady = TouristSpotUniqueViewsService.instance
          .hasConfirmedCountForSpot(_spot);
    });
  }

  void _recountCheckIns() {
    final live = AdminLiveCollections.instance;
    if (!live.checkInsReady) {
      _checkInsReady = false;
      if (mounted) setState(() {});
      return;
    }
    final docId = (_spot.firestoreDocId ?? '').trim().toLowerCase();
    final name = _spot.name.trim().toLowerCase();
    var count = 0;
    for (final doc in live.checkIns) {
      final raw = doc.data();
      final spotId = checkInStringField(raw, const [
        'spot_id',
        'spotId',
        'touristSpotId',
        'tourist_spot_id',
        'attractionId',
      ]).trim().toLowerCase();
      final spotName = checkInSpotName(raw).trim().toLowerCase();
      final matchId =
          docId.isNotEmpty && (spotId == docId || spotName == docId);
      final matchName = name.isNotEmpty &&
          (spotName == name ||
              spotId == name ||
              normalizeTourismNameKey(spotName) ==
                  normalizeTourismNameKey(_spot.name));
      if (matchId || matchName) count++;
    }
    _checkInCount = count;
    _checkInsReady = true;
    if (mounted) setState(() {});
  }

  void _listenToFirestoreDoc() {
    final docId = (_spot.firestoreDocId ?? '').trim();
    if (docId.isEmpty || docId.contains('/')) {
      _docMissing = true;
      return;
    }
    _docSub = FirebaseFirestore.instance
        .collection(kTouristSpotsCollection)
        .doc(docId)
        .snapshots()
        .listen(
      (snap) {
        if (!mounted) return;
        if (!snap.exists) {
          setState(() => _docMissing = true);
          return;
        }
        final data = snap.data();
        if (data == null) return;
        final updated = touristSpotFromFirestoreDoc(snap.id, data);
        if (updated == null) return;
        setState(() {
          _docMissing = false;
          _spot = updated;
          _address = _firstNonEmpty(data, const [
            'address',
            'locationAddress',
            'location_address',
            'streetAddress',
            'street_address',
            'fullAddress',
            'full_address',
          ]);
          _operatingHours = _firstNonEmpty(data, const [
            'operatingHours',
            'operating_hours',
            'openingHours',
            'opening_hours',
            'openHours',
            'open_hours',
            'hours',
            'businessHours',
            'business_hours',
          ]);
        });
        _refreshViews();
        _recountCheckIns();
      },
      onError: (Object e, StackTrace st) {
        debugPrint('AdminTouristSpotDetailsView listen: $e\n$st');
      },
    );
  }

  static String? _firstNonEmpty(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final v = data[key];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  String _displayOrNa(String? value) {
    final s = (value ?? '').trim();
    return s.isEmpty ? _kNotAvailable : s;
  }

  int get _reviewCount {
    final fromStore =
        SpotRatingsStore.instance.forSpot(_spot.name).length;
    if (fromStore > 0) return fromStore;
    if (_spot.ratingCount > 0) return _spot.ratingCount;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final hasCoords = isValidSpotCoordinate(_spot.latitude, _spot.longitude);
    final category = _spot.category.trim().isNotEmpty
        ? _spot.category.trim()
        : (_spot.type.trim().isNotEmpty ? _spot.type.trim() : '');

    return Material(
      color: Colors.white,
      child: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeroImage(),
                  const SizedBox(height: 18),
                  Text(
                    _spot.displayName.isEmpty ? _kNotAvailable : _spot.displayName,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: OptacaAdminTheme.text,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.location_city_outlined,
                        size: 18,
                        color: OptacaAdminTheme.primary.withValues(alpha: 0.9),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _displayOrNa(_spot.location),
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: OptacaAdminTheme.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_docMissing) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: OptacaAdminTheme.primary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: const Text(
                        'Showing catalog data. Live Firestore document was not found for this spot id.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: OptacaAdminTheme.textMuted,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _buildMetricRow(),
                  const SizedBox(height: 18),
                  _sectionCard(
                    title: 'About',
                    child: Text(
                      _displayOrNa(_spot.description),
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: OptacaAdminTheme.text,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _sectionCard(
                    title: 'Details',
                    child: Column(
                      children: [
                        _detailRow('Category', _displayOrNa(category)),
                        _detailRow('Location / Address', _displayOrNa(_address)),
                        _detailRow(
                          'Entrance Fee',
                          _displayOrNa(_spot.entranceFee),
                        ),
                        _detailRow(
                          'Operating Hours',
                          _displayOrNa(_operatingHours),
                        ),
                        _detailRow(
                          'Latitude',
                          hasCoords
                              ? _spot.latitude!.toStringAsFixed(6)
                              : _kNotAvailable,
                        ),
                        _detailRow(
                          'Longitude',
                          hasCoords
                              ? _spot.longitude!.toStringAsFixed(6)
                              : _kNotAvailable,
                          showDivider: false,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _sectionCard(
                    title: 'Map Location',
                    child: hasCoords
                        ? _InteractiveSpotMap(
                            latitude: _spot.latitude!,
                            longitude: _spot.longitude!,
                          )
                        : const Padding(
                            padding: EdgeInsets.symmetric(vertical: 28),
                            child: Center(
                              child: Text(
                                _kNotAvailable,
                                style: TextStyle(
                                  color: OptacaAdminTheme.textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: OptacaAdminTheme.border)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded),
            color: OptacaAdminTheme.text,
          ),
          const Expanded(
            child: Text(
              'Tourist Spot Details',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: OptacaAdminTheme.text,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: OptacaAdminTheme.lightOrange,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'OPTACA',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: OptacaAdminTheme.primary,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroImage() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: buildTouristSpotProfileImage(
          _spot,
          fallback: ColoredBox(
            color: OptacaAdminTheme.lightOrange,
            child: Icon(
              _spot.isHotel ? Icons.hotel : Icons.place_outlined,
              size: 56,
              color: OptacaAdminTheme.primary,
            ),
          ),
          memCacheWidth: 1200,
          memCacheHeight: 675,
        ),
      ),
    );
  }

  Widget _buildMetricRow() {
    final ratingLabel = _spot.rating > 0
        ? _spot.rating.toStringAsFixed(1)
        : _kNotAvailable;
    final reviewsLabel = _reviewCount > 0
        ? OptacaAdminTheme.formatCount(_reviewCount)
        : '0';
    final viewsLabel = _viewsReady
        ? OptacaAdminTheme.formatCount(_uniqueViews)
        : '…';
    final checkInsLabel = _checkInsReady
        ? OptacaAdminTheme.formatCount(_checkInCount)
        : '…';

    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 640 ? 4 : 2;
        final items = [
          _metricTile(
            icon: Icons.star_rounded,
            label: 'Rating',
            value: ratingLabel,
          ),
          _metricTile(
            icon: Icons.reviews_outlined,
            label: 'Reviews',
            value: reviewsLabel,
          ),
          _metricTile(
            icon: Icons.visibility_outlined,
            label: 'Unique Views',
            value: viewsLabel,
          ),
          _metricTile(
            icon: Icons.qr_code_scanner_rounded,
            label: 'QR Check-ins',
            value: checkInsLabel,
          ),
        ];
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: cols,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: cols == 4 ? 2.2 : 2.4,
          children: items,
        );
      },
    );
  }

  Widget _metricTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFAF6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OptacaAdminTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: OptacaAdminTheme.lightOrange,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: OptacaAdminTheme.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: OptacaAdminTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: OptacaAdminTheme.text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OptacaAdminTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.3,
              color: OptacaAdminTheme.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool showDivider = true}) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 140,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: OptacaAdminTheme.textMuted,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: value == _kNotAvailable
                        ? OptacaAdminTheme.textMuted
                        : OptacaAdminTheme.text,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, color: OptacaAdminTheme.border.withValues(alpha: 0.9)),
      ],
    );
  }
}

class _InteractiveSpotMap extends StatelessWidget {
  const _InteractiveSpotMap({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(latitude, longitude);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 240,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 14,
            minZoom: 7,
            maxZoom: 18,
            backgroundColor: const Color(0xFFE8EEF2),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: [
            osmBasemapTileLayer(),
            MarkerLayer(
              markers: [
                Marker(
                  point: point,
                  width: 40,
                  height: 48,
                  alignment: Alignment.topCenter,
                  child: const Icon(
                    Icons.location_on,
                    color: OptacaAdminTheme.primary,
                    size: 40,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
