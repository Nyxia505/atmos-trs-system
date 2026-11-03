import 'dart:async' show Completer, StreamSubscription, unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../road_route_direction.dart';

/// Firestore collection for bus stops and terminals.
const String kBusLocationsCollection = 'bus_locations';

/// One bus stop or terminal. Coordinates come only from Firestore.
class BusLocation {
  final String id;
  final String name;
  final String municipality;
  final String routeType;
  final double latitude;
  final double longitude;
  final String locationType;
  final String status;
  final int sortOrder;

  /// Other [BusLocation.id]s this stop can travel to. Empty means no explicit
  /// list is stored; route type and the selected road still apply.
  final List<String> connectsTo;

  const BusLocation({
    required this.id,
    required this.name,
    required this.municipality,
    required this.routeType,
    required this.latitude,
    required this.longitude,
    required this.locationType,
    required this.status,
    required this.sortOrder,
    this.connectsTo = const [],
  });

  bool get isActive => status == 'active';

  bool get hasValidCoordinates =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      !(latitude == 0 && longitude == 0);

  bool serves(RoadRouteDirection direction) {
    if (routeType == 'both') return true;
    return routeType == direction.name;
  }

  factory BusLocation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return BusLocation(
      id: doc.id,
      name: '${d['name'] ?? ''}'.trim(),
      municipality: '${d['municipality'] ?? ''}'.trim(),
      routeType: _routeType('${d['routeType'] ?? ''}'),
      latitude: _double(d['latitude']),
      longitude: _double(d['longitude']),
      locationType: _locationType('${d['locationType'] ?? d['kind'] ?? ''}'),
      status: _status('${d['status'] ?? ''}'),
      sortOrder: (d['sortOrder'] as num?)?.toInt() ?? 0,
      connectsTo: _idList(d['connectsTo']),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'municipality': municipality,
        'routeType': routeType,
        'latitude': latitude,
        'longitude': longitude,
        'locationType': locationType,
        'status': status,
        'sortOrder': sortOrder,
        if (connectsTo.isNotEmpty) 'connectsTo': connectsTo,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  static String? validate({
    required String name,
    required String municipality,
    required String routeType,
    required String locationType,
    required String status,
    required double? latitude,
    required double? longitude,
  }) {
    if (name.trim().isEmpty) return 'Enter a name.';
    if (municipality.trim().isEmpty) return 'Choose a municipality.';
    if (routeType != 'coastal' &&
        routeType != 'highland' &&
        routeType != 'both') {
      return 'Choose Coastal, Highland, or Both.';
    }
    if (locationType != 'stop' && locationType != 'terminal') {
      return 'Choose Bus Stop or Bus Terminal.';
    }
    if (status != 'active' && status != 'inactive') {
      return 'Choose Active or Inactive.';
    }
    if (latitude == null || longitude == null) {
      return 'Set a location on the map or enter coordinates.';
    }
    if (latitude < -90 || latitude > 90) {
      return 'Latitude must be between -90 and 90.';
    }
    if (longitude < -180 || longitude > 180) {
      return 'Longitude must be between -180 and 180.';
    }
    if (latitude == 0 && longitude == 0) {
      return 'Those coordinates are not a valid stop in Misamis Occidental.';
    }
    return null;
  }
}

String _routeType(String raw) {
  final v = raw.trim().toLowerCase();
  if (v == 'highland') return 'highland';
  if (v == 'both') return 'both';
  return 'coastal';
}

String _locationType(String raw) {
  return raw.trim().toLowerCase() == 'terminal' ? 'terminal' : 'stop';
}

String _status(String raw) {
  return raw.trim().toLowerCase() == 'inactive' ? 'inactive' : 'active';
}

List<String> _idList(dynamic raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if ('$item'.trim().isNotEmpty) '$item'.trim(),
  ];
}

double _double(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim()) ?? 0;
  return 0;
}

String busLocationMunicipalityKey(String name) =>
    name.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

/// Live cache of [kBusLocationsCollection].
class BusLocationStore {
  BusLocationStore._();
  static final BusLocationStore instance = BusLocationStore._();

  final List<BusLocation> locations = [];
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  bool _listening = false;
  Future<void>? _firstLoad;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  List<BusLocation> get active =>
      locations.where((l) => l.isActive && l.hasValidCoordinates).toList();

  void ensureListening() {
    if (_listening) return;
    _listening = true;
    final done = Completer<void>();
    _firstLoad ??= done.future;
    _sub = FirebaseFirestore.instance
        .collection(kBusLocationsCollection)
        .snapshots()
        .listen(
      (snap) {
        locations
          ..clear()
          ..addAll(snap.docs.map(BusLocation.fromDoc))
          ..sort((a, b) {
            final byOrder = a.sortOrder.compareTo(b.sortOrder);
            if (byOrder != 0) return byOrder;
            return a.name.compareTo(b.name);
          });
        revision.value++;
        if (!done.isCompleted) done.complete();
      },
      onError: (Object e) {
        debugPrint('BusLocationStore: $e');
        if (!done.isCompleted) done.complete();
        _listening = false;
        unawaited(_sub?.cancel());
        _sub = null;
        Future<void>.delayed(const Duration(seconds: 3), ensureListening);
      },
    );
  }

  Future<void> ensureLoaded() async {
    ensureListening();
    await _firstLoad;
  }

  BusLocation? primaryForMunicipality(
    String municipalityName, {
    RoadRouteDirection? direction,
  }) {
    final key = busLocationMunicipalityKey(municipalityName);
    final matches = active.where((l) {
      if (busLocationMunicipalityKey(l.municipality) != key) return false;
      if (direction == null) return true;
      return l.serves(direction);
    }).toList();
    if (matches.isEmpty) return null;
    matches.sort((a, b) {
      final terminalFirst = (a.locationType == 'terminal' ? 0 : 1)
          .compareTo(b.locationType == 'terminal' ? 0 : 1);
      if (terminalFirst != 0) return terminalFirst;
      return a.sortOrder.compareTo(b.sortOrder);
    });
    return matches.first;
  }

  List<BusLocation> alongMunicipalities(
    Iterable<String> municipalityNames,
    RoadRouteDirection direction,
  ) {
    final out = <BusLocation>[];
    for (final name in municipalityNames) {
      final key = busLocationMunicipalityKey(name);
      final row = active.where((l) {
        return busLocationMunicipalityKey(l.municipality) == key &&
            l.serves(direction);
      }).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      out.addAll(row);
    }
    return out;
  }

  Future<void> save(BusLocation location) async {
    final error = BusLocation.validate(
      name: location.name,
      municipality: location.municipality,
      routeType: location.routeType,
      locationType: location.locationType,
      status: location.status,
      latitude: location.latitude,
      longitude: location.longitude,
    );
    if (error != null) throw StateError(error);
    final ref = location.id.isEmpty
        ? FirebaseFirestore.instance.collection(kBusLocationsCollection).doc()
        : FirebaseFirestore.instance
            .collection(kBusLocationsCollection)
            .doc(location.id);
    await ref.set(location.toFirestore(), SetOptions(merge: true));
  }

  Future<void> delete(String id) async {
    await FirebaseFirestore.instance
        .collection(kBusLocationsCollection)
        .doc(id)
        .delete();
  }
}
