import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import 'data.dart';
import 'mapping_screen.dart';
import 'services/public_firestore_read.dart';
import 'spot_detail_screen.dart';
import 'widgets/bus_terminal_map_markers.dart';
import 'widgets/municipality_image.dart';
import 'widgets/osm_map_tiles.dart';
import 'widgets/responsive_layout.dart';

Widget _gradientPlaceholder() {
  return Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1A6B3C), Color(0xFF2E8B57)],
      ),
    ),
  );
}

class MunicipalityDetailScreen extends StatelessWidget {
  final Municipality municipality;
  const MunicipalityDetailScreen({super.key, required this.municipality});

  @override
  Widget build(BuildContext context) {
    final spotsInMunicipality = municipality.spots.isNotEmpty
        ? municipality.spots
        : allSpots.where((s) {
            final location = s.location.toLowerCase().trim();
            final name = municipality.name.toLowerCase().trim();
            final shortName = municipality.shortName.toLowerCase().trim();
            return location == name || location == shortName;
          }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          // Collapsible App Bar with hero image
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: AppColors.primary,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                municipality.shortName.isNotEmpty
                    ? municipality.shortName
                    : municipality.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  buildMunicipalityImageForMunicipality(
                    municipality,
                    fallback: _gradientPlaceholder(),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.6),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    municipality.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                      height: 1.15,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(
                        icon: Icons.landscape_outlined,
                        label:
                            '${spotsInMunicipality.length} spot${spotsInMunicipality.length == 1 ? '' : 's'}',
                      ),
                      if (busTerminalForMap(municipality) != null)
                        _InfoChip(
                          icon: Icons.directions_bus_outlined,
                          label: busTerminalMarkerTitle(
                            municipality.busTerminal!,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.05),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'About',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textDark,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          municipality.description.trim().isEmpty
                              ? 'No description yet.'
                              : municipality.description,
                          style: const TextStyle(
                            fontSize: 14.5,
                            color: AppColors.textGrey,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),
                  if (busTerminalForMap(municipality) != null)
                    _BusTerminalMapCard(municipality: municipality)
                  else
                    const Text(
                      'No bus stop is saved for this municipality.',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textGrey,
                        height: 1.4,
                      ),
                    ),

                  const SizedBox(height: 20),

                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Tourist spots',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                      ),
                      Text(
                        '${spotsInMunicipality.length}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // Spots Grid
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                final cols = tourismSpotGridCrossAxisCount(
                  constraints.crossAxisExtent,
                  maxColumns: 2,
                );
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.78,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    if (index >= spotsInMunicipality.length) {
                      return const SizedBox.shrink();
                    }
                    final spot = spotsInMunicipality[index];
                    return _SpotGridCard(
                      spot: spot,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SpotDetailScreen(spot: spot),
                        ),
                      ),
                    );
                  }, childCount: spotsInMunicipality.length),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: _MunicipalityEstablishments(municipality: municipality),
          ),
        ],
      ),
    );
  }
}

class _BusTerminalMapCard extends StatelessWidget {
  final Municipality municipality;

  const _BusTerminalMapCard({required this.municipality});

  @override
  Widget build(BuildContext context) {
    final terminal = municipality.busTerminal!;
    final pos = busTerminalLatLng(municipality);
    if (pos == null) return const SizedBox.shrink();

    final center = ll.LatLng(pos.latitude, pos.longitude);
    final markers = buildOsmBusTerminalMarkers([municipality]);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: SizedBox(
              height: 160,
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 14,
                  minZoom: 10,
                  maxZoom: 18,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.none,
                  ),
                  backgroundColor: const Color(0xFFE8EEF2),
                ),
                children: [
                  osmBasemapTileLayer(),
                  MarkerLayer(markers: markers),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  terminal.kind == 'stop'
                      ? Icons.directions_bus
                      : Icons.directions_bus_filled,
                  color: terminal.kind == 'stop'
                      ? const Color(0xFF7B1FA2)
                      : const Color(0xFF1565C0),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        busTerminalMarkerTitle(terminal),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        terminal.name,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textGrey,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MappingScreen()),
                  ),
                  child: const Text('Full map'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const String _kAccommodationEstablishments = 'accommodation_establishments';

class _StoredEstablishment {
  const _StoredEstablishment({
    required this.id,
    required this.name,
    required this.category,
    required this.location,
    required this.imageUrls,
    required this.contactNumber,
    required this.email,
    required this.yearEstablished,
    required this.roomCount,
    required this.checkInTime,
    required this.checkOutTime,
    required this.rooms,
  });

  final String id;
  final String name;
  final String category;
  final String location;
  final List<String> imageUrls;
  final String contactNumber;
  final String email;
  final String yearEstablished;
  final String roomCount;
  final String checkInTime;
  final String checkOutTime;
  final List<_EstablishmentRoom> rooms;

  String get imageUrl => imageUrls.isEmpty ? '' : imageUrls.first;
}

class _EstablishmentRoom {
  const _EstablishmentRoom({
    required this.number,
    required this.type,
    required this.capacityMin,
    required this.capacityMax,
    required this.pricePerNight,
    required this.inclusions,
  });

  final String number;
  final String type;
  final int? capacityMin;
  final int? capacityMax;
  final int? pricePerNight;
  final List<String> inclusions;

  String get capacityLabel {
    final min = capacityMin;
    final max = capacityMax;
    if (min != null && max != null && min != max) return '$min–$max guests';
    final n = max ?? min;
    if (n == null || n <= 0) return '';
    return n == 1 ? '1 guest' : '$n guests';
  }
}

String _placeKey(String raw) {
  var t = raw.toLowerCase();
  t = t.replaceAll(RegExp(r'\(.*?\)'), ' ');
  t = t.replaceAll('city', ' ');
  return t.replaceAll(RegExp(r'[^a-z0-9]+'), '');
}

bool _establishmentInMunicipality(
  Map<String, dynamic> data,
  Municipality municipality,
) {
  final keys = <String>{
    _placeKey(municipality.name),
    _placeKey(municipality.shortName),
  }..removeWhere((k) => k.length < 4);
  if (keys.isEmpty) return false;

  final mun = _placeKey('${data['municipality'] ?? ''}');
  final id = _placeKey('${data['municipalityId'] ?? ''}');
  final loc = _placeKey('${data['location'] ?? ''}');
  for (final key in keys) {
    if (mun == key || id == key) return true;
    if (loc.contains(key)) return true;
  }
  return false;
}

bool _establishmentIsListed(Map<String, dynamic> data) {
  final status = '${data['status'] ?? ''}'.trim().toLowerCase();
  return status == 'active' || status == 'approved' || status == 'approve';
}

String _estText(Map<String, dynamic> data, String key) =>
    '${data[key] ?? ''}'.trim();

int? _estInt(dynamic raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse('$raw'.trim());
}

List<String> _establishmentImages(Map<String, dynamic> data) {
  final out = <String>[];
  void add(String raw) {
    final url = raw.trim();
    if (url.startsWith('http') && !out.contains(url)) out.add(url);
  }

  add(_estText(data, 'coverImageUrl'));
  final gallery = data['galleryUrls'];
  if (gallery is List) {
    for (final item in gallery) {
      add('$item');
    }
  }
  return out;
}

List<_EstablishmentRoom> _establishmentRooms(Map<String, dynamic> data) {
  final disabled = <String>{};
  final rawDisabled = data['disabledRooms'];
  if (rawDisabled is List) {
    for (final item in rawDisabled) {
      final id = '$item'.trim();
      if (id.isNotEmpty) disabled.add(id);
    }
  }
  final inventory = data['roomInventory'];
  if (inventory is! Map) return const [];
  final rooms = <_EstablishmentRoom>[];
  for (final entry in inventory.entries) {
    final number = '${entry.key}'.trim();
    if (number.isEmpty || disabled.contains(number)) continue;
    final raw = entry.value;
    if (raw is! Map) continue;
    final room = Map<String, dynamic>.from(raw);
    final inclusions = <String>[];
    final rawInclusions = room['inclusions'];
    if (rawInclusions is List) {
      for (final item in rawInclusions) {
        final label = '$item'.trim();
        if (label.isNotEmpty) inclusions.add(label);
      }
    }
    final price = _estInt(room['pricePerNight']);
    rooms.add(
      _EstablishmentRoom(
        number: number,
        type: '${room['type'] ?? ''}'.trim(),
        capacityMin: _estInt(room['capacityMin']),
        capacityMax: _estInt(room['capacityMax']),
        pricePerNight: price != null && price > 0 ? price : null,
        inclusions: inclusions,
      ),
    );
  }
  rooms.sort((a, b) {
    final an = int.tryParse(a.number) ?? 0;
    final bn = int.tryParse(b.number) ?? 0;
    return an.compareTo(bn);
  });
  return rooms;
}

class _MunicipalityEstablishments extends StatefulWidget {
  final Municipality municipality;

  const _MunicipalityEstablishments({required this.municipality});

  @override
  State<_MunicipalityEstablishments> createState() =>
      _MunicipalityEstablishmentsState();
}

class _MunicipalityEstablishmentsState
    extends State<_MunicipalityEstablishments> {
  late final Future<List<_StoredEstablishment>> _load = _fetch();

  Future<List<_StoredEstablishment>> _fetch() async {
    final snap =
        await fetchPublicFirestoreCollection(_kAccommodationEstablishments);
    final out = <_StoredEstablishment>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      if (!_establishmentIsListed(data)) continue;
      if (!_establishmentInMunicipality(data, widget.municipality)) continue;
      final name = '${data['businessName'] ?? data['name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final barangay = _estText(data, 'barangay');
      final municipality = _estText(data, 'municipality');
      final location = _estText(data, 'location');
      final rooms = _estInt(data['roomCount']);
      final year = _estInt(data['yearEstablished']);
      out.add(
        _StoredEstablishment(
          id: doc.id,
          name: name,
          category: '${data['category'] ?? data['type'] ?? ''}'.trim(),
          location: location.isNotEmpty
              ? location
              : [
                  if (barangay.isNotEmpty) barangay,
                  if (municipality.isNotEmpty) municipality,
                ].join(', '),
          imageUrls: _establishmentImages(data),
          contactNumber: _estText(data, 'contactNumber'),
          email: _estText(data, 'email'),
          yearEstablished: year == null || year <= 0 ? '' : '$year',
          roomCount: rooms == null || rooms <= 0 ? '' : '$rooms',
          checkInTime: _estText(data, 'checkInTime'),
          checkOutTime: _estText(data, 'checkOutTime'),
          rooms: _establishmentRooms(data),
        ),
      );
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_StoredEstablishment>>(
      future: _load,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final items = snapshot.data ?? const <_StoredEstablishment>[];
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Establishments',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  Text(
                    '${items.length}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Text(
                  'No approved establishments are saved for this municipality.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    color: AppColors.textGrey,
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = tourismSpotGridCrossAxisCount(
                      constraints.maxWidth,
                      maxColumns: 2,
                    );
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 14,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _EstablishmentGridCard(
                          item: item,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  _EstablishmentDetailPage(item: item),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EstablishmentGridCard extends StatelessWidget {
  final _StoredEstablishment item;
  final VoidCallback onTap;

  const _EstablishmentGridCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _EstablishmentCover(item: item)),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.category.isEmpty ? 'Establishment' : item.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
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
}

class _EstablishmentCover extends StatelessWidget {
  final _StoredEstablishment item;

  const _EstablishmentCover({required this.item});

  @override
  Widget build(BuildContext context) {
    if (item.imageUrl.isEmpty) {
      return ColoredBox(
        color: AppColors.primary.withValues(alpha: 0.08),
        child: const Center(
          child: Icon(Icons.storefront_outlined, color: AppColors.primary, size: 40),
        ),
      );
    }
    return Image.network(
      item.imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      errorBuilder: (_, _, _) => ColoredBox(
        color: AppColors.primary.withValues(alpha: 0.08),
        child: const Center(
          child: Icon(Icons.storefront_outlined, color: AppColors.primary, size: 40),
        ),
      ),
    );
  }
}

class _EstablishmentDetailPage extends StatelessWidget {
  final _StoredEstablishment item;

  const _EstablishmentDetailPage({required this.item});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: AppColors.primary,
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  _EstablishmentCover(item: item),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.5),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.05),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                            height: 1.15,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _InfoChip(
                              icon: Icons.storefront_outlined,
                              label: item.category.isEmpty
                                  ? 'Establishment'
                                  : item.category,
                            ),
                            if (item.location.isNotEmpty)
                              _InfoChip(
                                icon: Icons.location_on_outlined,
                                label: item.location,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _EstablishmentFacts(item: item),
                  if (item.imageUrls.length > 1) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Photos',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 88,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: item.imageUrls.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              item.imageUrls[index],
                              width: 120,
                              height: 88,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => const SizedBox(
                                width: 120,
                                height: 88,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  if (item.rooms.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Rooms',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (var i = 0; i < item.rooms.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      _RoomCard(room: item.rooms[i]),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final _EstablishmentRoom room;

  const _RoomCard({required this.room});

  @override
  Widget build(BuildContext context) {
    final title = room.type.isEmpty ? 'Room ${room.number}' : room.type;
    final price = room.pricePerNight;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$title · Room ${room.number}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: AppColors.textDark,
                  ),
                ),
              ),
              if (price != null)
                Text(
                  '₱$price / night',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
            ],
          ),
          if (room.capacityLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              room.capacityLabel,
              style: const TextStyle(fontSize: 13, color: AppColors.textGrey),
            ),
          ],
          if (room.inclusions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final inclusion in room.inclusions)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.listTilePeach,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      inclusion,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EstablishmentFacts extends StatelessWidget {
  final _StoredEstablishment item;

  const _EstablishmentFacts({required this.item});

  @override
  Widget build(BuildContext context) {
    final rows = <(IconData, String, String)>[
      if (item.category.isNotEmpty)
        (Icons.storefront_outlined, 'Type', item.category),
      if (item.location.isNotEmpty)
        (Icons.location_on_outlined, 'Address', item.location),
      if (item.contactNumber.isNotEmpty)
        (Icons.phone_outlined, 'Contact', item.contactNumber),
      if (item.email.isNotEmpty) (Icons.email_outlined, 'Email', item.email),
      if (item.yearEstablished.isNotEmpty)
        (Icons.calendar_today_outlined, 'Established', item.yearEstablished),
      if (item.roomCount.isNotEmpty)
        (Icons.bed_outlined, 'Rooms', item.roomCount),
      if (item.checkInTime.isNotEmpty)
        (Icons.login_rounded, 'Check-in', item.checkInTime),
      if (item.checkOutTime.isNotEmpty)
        (Icons.logout_rounded, 'Check-out', item.checkOutTime),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: Colors.black.withValues(alpha: 0.06),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(rows[i].$1, size: 20, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          rows[i].$2,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textGrey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rows[i].$3,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
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

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.listTilePeach,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotGridCard extends StatelessWidget {
  final TouristSpot spot;
  final VoidCallback onTap;

  const _SpotGridCard({required this.spot, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final kind = spot.isHotel ? 'Hotel' : spot.type;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    buildTouristSpotProfileImage(
                      spot,
                      fallback: Container(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        child: const Center(
                          child: Icon(
                            Icons.landscape,
                            color: AppColors.primary,
                            size: 40,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.94),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: Colors.amber.shade700,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              spot.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      spot.displayName,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      kind,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
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
}
