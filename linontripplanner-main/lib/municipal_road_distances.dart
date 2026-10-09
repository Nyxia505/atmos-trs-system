import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import 'data.dart';
import 'firestore_loader.dart' show municipalitySlug;
import 'services/auth_role_claims.dart'
    show ensurePermanentStaffRoleForCatalogWrite;
import 'services/public_firestore_read.dart';
import 'tourist_plan/tourist_travel_estimates.dart' show travelMinutesForKm;
import 'trip_planner_utils.dart' show normalizeMunicipalityName;

/// Firestore collection holding one document per directed municipality pair.
///
/// | Field | Type | Purpose |
/// |-------|------|---------|
/// | fromMunicipality / toMunicipality | string | Canonical LGU names |
/// | fromMunicipalitySlug / toMunicipalitySlug | string | Query keys |
/// | distanceKm | number | Road km between town centers |
/// | drivingMinutes | number | Free-flow driving time (OSRM) |
/// | travelMinutesByMode | map | Car / Motorcycle / Public Transport |
/// | fromLat, fromLng, toLat, toLng | number | Town-center coordinates |
/// | source | string | Data origin |
/// | updatedAt | timestamp | Last sync |
///
/// Document id: `{fromSlug}__{toSlug}` (same convention as `transportation_fees`).
const String kMunicipalRoadDistancesCollection = 'municipal_road_distances';

const List<String> kRoadDistanceTransportModes = kTransportModes;

/// Road distances between Misamis Occidental town centers (OSRM driving routes
/// on the OpenStreetMap road network). Row = from, column = to, same order as
/// [_kRoadTableTowns].
const List<String> _kRoadTableTowns = [
  'Aloran',
  'Baliangao',
  'Bonifacio',
  'Calamba',
  'Clarin',
  'Concepcion',
  'Don Victoriano Chiongbian',
  'Jimenez',
  'Lopez Jaena',
  'Oroquieta City (Provincial Capital)',
  'Ozamiz City',
  'Panaon',
  'Plaridel',
  'Sapang Dalaga',
  'Sinacaban',
  'Tangub City',
  'Tudela',
];

/// Extra spellings seen in spot `location` fields (already normalized).
const Map<String, int> _kRoadTableExtraAliases = {
  'don victoriano': 6,
  'don v chiongbian': 6,
  'dvc': 6,
  'ozamis': 10,
};

const List<List<double>> _kRoadKm = [
  [0, 54.6, 66.3, 41.9, 26.8, 72.1, 96.9, 10.4, 23.3, 9.3, 33.2, 7.1, 35.5, 54.3, 16.4, 51.0, 21.7],
  [54.6, 0, 120.0, 12.8, 80.6, 38.1, 70.9, 64.2, 31.4, 48.1, 87.0, 60.9, 19.4, 20.3, 70.2, 104.7, 75.5],
  [66.1, 120.0, 0, 107.3, 39.9, 93.0, 32.2, 56.4, 88.7, 74.7, 34.1, 59.6, 100.9, 95.0, 49.9, 18.1, 45.0],
  [41.9, 12.8, 107.3, 0, 67.8, 31.2, 64.0, 51.4, 23.0, 35.4, 74.2, 48.1, 11.3, 13.4, 57.4, 92.0, 62.7],
  [26.7, 80.6, 39.9, 67.8, 0, 98.0, 70.5, 17.0, 49.2, 35.3, 6.8, 20.1, 61.4, 80.2, 10.4, 24.6, 5.5],
  [72.1, 38.1, 93.0, 30.8, 98.0, 0, 48.7, 81.6, 53.5, 65.6, 104.4, 78.3, 41.8, 17.8, 87.6, 122.2, 92.9],
  [97.0, 69.6, 32.4, 62.3, 70.7, 47.3, 0, 87.3, 85.0, 97.1, 64.9, 90.5, 73.3, 49.3, 80.7, 49.2, 75.8],
  [10.3, 64.2, 56.4, 51.4, 17.0, 81.6, 87.0, 0, 32.8, 18.9, 23.4, 3.8, 45.0, 63.9, 6.5, 41.1, 11.9],
  [23.4, 31.8, 88.8, 23.4, 49.3, 53.9, 86.7, 32.9, 0, 14.2, 55.7, 29.6, 12.5, 36.2, 38.9, 73.5, 44.2],
  [9.5, 48.1, 74.9, 35.4, 35.4, 65.6, 105.5, 19.0, 14.2, 0, 41.8, 15.7, 26.4, 47.8, 25.0, 59.6, 30.3],
  [33.1, 87.0, 34.1, 74.2, 6.8, 104.4, 64.7, 23.4, 55.6, 41.7, 0, 26.6, 67.8, 86.7, 16.8, 18.8, 11.9],
  [7.0, 60.9, 59.6, 48.1, 20.1, 78.3, 90.2, 3.8, 29.5, 15.6, 26.5, 0, 41.7, 60.5, 9.7, 44.3, 15.0],
  [35.2, 19.4, 100.6, 11.3, 61.2, 41.9, 74.7, 44.8, 12.1, 26.0, 67.6, 41.5, 0, 24.1, 50.7, 85.3, 56.1],
  [54.3, 20.3, 95.0, 13.0, 80.2, 17.8, 50.6, 63.8, 35.8, 47.8, 86.6, 60.5, 24.1, 0, 69.8, 104.4, 75.1],
  [16.2, 70.2, 49.9, 57.4, 10.4, 87.6, 80.5, 6.5, 38.8, 24.9, 16.8, 9.7, 51.0, 69.8, 0, 34.6, 5.3],
  [50.8, 104.7, 18.1, 92.0, 24.6, 122.2, 48.9, 41.1, 73.4, 59.4, 18.8, 44.3, 85.6, 104.4, 34.6, 0, 29.7],
  [21.4, 75.3, 44.9, 62.6, 5.4, 92.8, 75.5, 11.7, 44.0, 30.0, 11.8, 14.9, 56.2, 75.0, 5.2, 29.6, 0],
];

/// Free-flow driving minutes (OSRM), same order as [_kRoadKm].
const List<List<int>> _kDrivingMin = [
  [0, 69, 84, 55, 34, 91, 137, 13, 32, 13, 43, 9, 49, 71, 21, 65, 28],
  [69, 0, 151, 15, 101, 46, 114, 81, 44, 62, 110, 77, 28, 26, 88, 132, 95],
  [84, 151, 0, 137, 50, 134, 61, 71, 114, 95, 44, 75, 131, 141, 63, 24, 57],
  [55, 15, 137, 0, 87, 38, 106, 67, 32, 48, 96, 63, 16, 18, 74, 118, 81],
  [34, 101, 50, 87, 0, 123, 104, 21, 64, 45, 9, 25, 81, 103, 13, 31, 7],
  [91, 46, 134, 38, 123, 0, 80, 103, 68, 84, 132, 99, 52, 20, 110, 154, 117],
  [138, 111, 61, 103, 105, 77, 0, 126, 133, 149, 98, 130, 117, 85, 118, 80, 112],
  [13, 81, 71, 67, 21, 103, 125, 0, 44, 25, 30, 5, 60, 83, 8, 52, 15],
  [32, 45, 114, 32, 64, 69, 136, 44, 0, 20, 73, 40, 18, 49, 52, 95, 59],
  [13, 62, 95, 48, 45, 84, 149, 25, 19, 0, 54, 21, 36, 64, 32, 76, 39],
  [43, 110, 44, 96, 9, 132, 98, 30, 73, 54, 0, 34, 90, 112, 22, 25, 16],
  [9, 77, 75, 63, 25, 99, 129, 5, 40, 21, 34, 0, 57, 79, 13, 56, 20],
  [48, 28, 130, 16, 80, 52, 120, 60, 17, 35, 89, 56, 0, 32, 67, 111, 74],
  [71, 26, 142, 18, 103, 20, 88, 82, 48, 64, 112, 79, 32, 0, 90, 134, 97],
  [21, 88, 63, 74, 13, 110, 117, 8, 51, 32, 22, 12, 68, 90, 0, 44, 7],
  [65, 132, 24, 118, 31, 154, 79, 52, 95, 76, 25, 56, 112, 134, 44, 0, 38],
  [27, 95, 57, 81, 7, 117, 111, 15, 58, 39, 16, 19, 74, 97, 7, 38, 0],
];

/// Town centers used to compute the tables (OpenStreetMap Nominatim).
const List<List<double>> _kTownCenters = [
  [8.4164194, 123.8210876],
  [8.6601564, 123.6027017],
  [8.0522878, 123.6139434],
  [8.5605342, 123.6442296],
  [8.1998924, 123.8616135],
  [8.4233368, 123.6032778],
  [8.2492223, 123.5673621],
  [8.3343655, 123.8400281],
  [8.5530838, 123.7657748],
  [8.4858864, 123.8077767],
  [8.1470175, 123.8459793],
  [8.3627950, 123.8409132],
  [8.6198081, 123.7113727],
  [8.5422258, 123.5670307],
  [8.2852005, 123.8428482],
  [8.0609053, 123.7512585],
  [8.2411877, 123.8469059],
];

const String _kRoadDataSource =
    'OSRM driving routes on the OpenStreetMap road network';

/// Values loaded from Firestore; keyed by `fromIndex * 100 + toIndex`.
/// When present they take precedence over the embedded tables.
final Map<int, double> _remoteRoadKm = {};
final Map<int, int> _remoteDrivingMin = {};

int _pairKey(int from, int to) => from * 100 + to;

double _roadKmAt(int from, int to) =>
    _remoteRoadKm[_pairKey(from, to)] ?? _kRoadKm[from][to];

int _drivingMinAt(int from, int to) =>
    _remoteDrivingMin[_pairKey(from, to)] ?? _kDrivingMin[from][to];

Map<String, int>? _aliasIndexCache;

Map<String, int> _aliasIndex() {
  final cached = _aliasIndexCache;
  if (cached != null) return cached;
  final out = <String, int>{};
  for (var i = 0; i < _kRoadTableTowns.length; i++) {
    final n = normalizeMunicipalityName(_kRoadTableTowns[i]);
    if (n.isNotEmpty) out[n] = i;
  }
  out.addAll(_kRoadTableExtraAliases);
  return _aliasIndexCache = out;
}

/// Table index for a municipality name or free-text spot location
/// (e.g. "Brgy. Poblacion, Jimenez"). Longest matching alias wins.
int? roadTableIndexFor(String nameOrLocation) {
  final n = normalizeMunicipalityName(nameOrLocation);
  if (n.isEmpty) return null;
  int? best;
  var bestLen = -1;
  _aliasIndex().forEach((alias, idx) {
    if (n == alias ||
        n.contains(alias) ||
        (n.length >= 4 && alias.contains(n))) {
      if (alias.length > bestLen) {
        bestLen = alias.length;
        best = idx;
      }
    }
  });
  return best;
}

/// Road network between town centers: each pair is joined by a drivable road
/// that does not pass through another town center. Routes are searched on this
/// graph, so a trip visits every town the road actually runs through, in road
/// order. Indices follow [_kRoadTableTowns].
///
/// The coastal highway runs Tangub – Ozamiz – Clarin – Tudela – Sinacaban –
/// Jimenez – Panaon – Aloran – Oroquieta – Lopez Jaena – Plaridel – Calamba –
/// Baliangao – Sapang Dalaga – Concepcion; the interior road links Tangub –
/// Bonifacio – Don Victoriano – Concepcion (Mt. Malindang Eco-Tourism
/// Highway), closing a loop around the province. The Oroquieta – Calamba
/// mountain road and the Calamba – Sapang Dalaga cut-off are left out on
/// purpose: they bypass Lopez Jaena, Plaridel and Baliangao.
const List<(int, int)> _kRoadLinks = [
  (15, 10), // Tangub – Ozamiz
  (10, 4), // Ozamiz – Clarin
  (4, 16), // Clarin – Tudela
  (16, 14), // Tudela – Sinacaban
  (14, 7), // Sinacaban – Jimenez
  (7, 11), // Jimenez – Panaon
  (11, 0), // Panaon – Aloran
  (0, 9), // Aloran – Oroquieta
  (9, 8), // Oroquieta – Lopez Jaena
  (8, 12), // Lopez Jaena – Plaridel
  (12, 3), // Plaridel – Calamba
  (3, 1), // Calamba – Baliangao
  (1, 13), // Baliangao – Sapang Dalaga
  (13, 5), // Sapang Dalaga – Concepcion
  (15, 2), // Tangub – Bonifacio
  (2, 6), // Bonifacio – Don Victoriano Chiongbian
  (6, 5), // Don Victoriano Chiongbian – Concepcion
];

/// Which way around the provincial road loop a trip goes.
enum RoadRouteDirection {
  /// Along the coast (Oroquieta, Calamba, Baliangao).
  coastal,

  /// Through the highlands (Tangub, Bonifacio, Don Victoriano).
  highland,
}

/// Link closed to force [direction]: the coastal route never uses Tangub –
/// Bonifacio, the highland route never uses Calamba – Baliangao.
(int, int) _closedLinkFor(RoadRouteDirection direction) =>
    direction == RoadRouteDirection.coastal ? (15, 2) : (3, 1);

Map<int, List<int>>? _roadNeighborsCache;

Map<int, List<int>> _roadNeighbors() {
  final cached = _roadNeighborsCache;
  if (cached != null) return cached;
  final out = <int, List<int>>{};
  for (final (a, b) in _kRoadLinks) {
    out.putIfAbsent(a, () => []).add(b);
    out.putIfAbsent(b, () => []).add(a);
  }
  return _roadNeighborsCache = out;
}

/// Table indices of the towns on the road from [from] to [to], both included
/// (Dijkstra on [_kRoadLinks] weighted by road km). With [direction], the
/// link on the other side of the loop is closed; [closedLink] closes a
/// specific link instead. Null when unreachable.
List<int>? _roadPathIndices(
  int from,
  int to, {
  RoadRouteDirection? direction,
  (int, int)? closedLink,
}) {
  if (from == to) return [from];
  final n = _kRoadTableTowns.length;
  final dist = List<double>.filled(n, double.infinity);
  final prev = List<int>.filled(n, -1);
  final done = List<bool>.filled(n, false);
  dist[from] = 0;
  final neighbors = _roadNeighbors();
  final closed = closedLink ??
      (direction == null ? null : _closedLinkFor(direction));
  bool isClosed(int a, int b) =>
      closed != null &&
      ((a == closed.$1 && b == closed.$2) || (a == closed.$2 && b == closed.$1));
  for (var iter = 0; iter < n; iter++) {
    var u = -1;
    for (var i = 0; i < n; i++) {
      if (!done[i] && (u == -1 || dist[i] < dist[u])) u = i;
    }
    if (u == -1 || dist[u] == double.infinity) break;
    if (u == to) break;
    done[u] = true;
    for (final v in neighbors[u] ?? const <int>[]) {
      if (isClosed(u, v)) continue;
      final alt = dist[u] + _roadKmAt(u, v);
      if (alt < dist[v]) {
        dist[v] = alt;
        prev[v] = u;
      }
    }
  }
  if (dist[to] == double.infinity) return null;
  final path = <int>[to];
  while (path.last != from) {
    path.add(prev[path.last]);
  }
  return path.reversed.toList();
}

double _pathKm(List<int> path) {
  var km = 0.0;
  for (var i = 0; i < path.length - 1; i++) {
    km += _roadKmAt(path[i], path[i + 1]);
  }
  return km;
}

int _pathMinutes(List<int> path) {
  var min = 0;
  for (var i = 0; i < path.length - 1; i++) {
    min += _drivingMinAt(path[i], path[i + 1]);
  }
  return min;
}

/// Road km between the centers of two different municipalities along the road
/// network, or null when either is unknown or both are the same municipality.
double? roadDistanceKmBetween(String fromNameOrLocation, String toNameOrLocation) {
  final a = roadTableIndexFor(fromNameOrLocation);
  final b = roadTableIndexFor(toNameOrLocation);
  if (a == null || b == null || a == b) return null;
  final path = _roadPathIndices(a, b);
  return path == null ? _roadKmAt(a, b) : _pathKm(path);
}

/// Free-flow driving minutes between two municipality centers along the road
/// network, or null.
int? roadDrivingMinutesBetween(
  String fromNameOrLocation,
  String toNameOrLocation,
) {
  final a = roadTableIndexFor(fromNameOrLocation);
  final b = roadTableIndexFor(toNameOrLocation);
  if (a == null || b == null || a == b) return null;
  final path = _roadPathIndices(a, b);
  return path == null ? _drivingMinAt(a, b) : _pathMinutes(path);
}

/// Town-center coordinates `(lat, lng)` for a municipality or spot location.
(double, double)? roadTownCenterFor(String nameOrLocation) {
  final i = roadTableIndexFor(nameOrLocation);
  if (i == null) return null;
  return (_kTownCenters[i][0], _kTownCenters[i][1]);
}

Municipality? _municipalityForIndex(int index) {
  for (final m in municipalities) {
    if (_indexForMunicipality(m) == index) return m;
  }
  return null;
}

int? _indexForMunicipality(Municipality m) =>
    roadTableIndexFor(m.name) ?? roadTableIndexFor(m.shortName);

/// Concepcion and Don Victoriano Chiongbian: trips to or from them always get
/// both the coastal and the highland route, except trips between the two.
const Set<int> _kBothRoutesTowns = {5, 6};

/// Links of the interior highway (Tangub – Bonifacio – Don Victoriano –
/// Concepcion).
const List<(int, int)> _kHighlandLinks = [(15, 2), (2, 6), (6, 5)];

bool _alwaysBothRoutes(int from, int to) =>
    _kBothRoutesTowns.contains(from) != _kBothRoutesTowns.contains(to);

bool _samePath(List<int> a, List<int> b) =>
    a.length == b.length &&
    Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

/// Share of [path]'s km driven on the interior highway.
double _highlandShare(List<int> path) {
  final total = _pathKm(path);
  if (total <= 0) return 0;
  var highland = 0.0;
  for (var i = 0; i < path.length - 1; i++) {
    final a = path[i];
    final b = path[i + 1];
    if (_kHighlandLinks.any(
      (l) => (l.$1 == a && l.$2 == b) || (l.$1 == b && l.$2 == a),
    )) {
      highland += _roadKmAt(a, b);
    }
  }
  return highland / total;
}

/// Coastal and highland paths from [from] to [to] (null when that way cannot
/// reach). For trips to or from [_kBothRoutesTowns] that stay on one side of
/// the loop, the other way round is found by closing the first link of the
/// direct road; the path with more interior highway is the highland one.
({List<int>? coastal, List<int>? highland}) _directionPaths(int from, int to) {
  final coastal =
      _roadPathIndices(from, to, direction: RoadRouteDirection.coastal);
  final highland =
      _roadPathIndices(from, to, direction: RoadRouteDirection.highland);
  if (coastal == null ||
      highland == null ||
      coastal.length < 2 ||
      !_samePath(coastal, highland) ||
      !_alwaysBothRoutes(from, to)) {
    return (coastal: coastal, highland: highland);
  }
  final other =
      _roadPathIndices(from, to, closedLink: (coastal[0], coastal[1]));
  if (other == null) return (coastal: coastal, highland: highland);
  return _highlandShare(other) > _highlandShare(coastal)
      ? (coastal: coastal, highland: other)
      : (coastal: other, highland: coastal);
}

/// [direction] path, or the shortest path when that direction cannot reach.
/// [wholeTrip] uses [_directionPaths] (a start → end trip); legs between
/// stops keep the plain closed-link path so they never loop the province.
List<int>? _pathFor(
  int from,
  int to,
  RoadRouteDirection? direction, {
  bool wholeTrip = false,
}) {
  if (direction != null) {
    final List<int>? forced;
    if (wholeTrip) {
      final paths = _directionPaths(from, to);
      forced = direction == RoadRouteDirection.coastal
          ? paths.coastal
          : paths.highland;
    } else {
      forced = _roadPathIndices(from, to, direction: direction);
    }
    if (forced != null) return forced;
  }
  return _roadPathIndices(from, to);
}

List<Municipality> _municipalitiesForPath(
  Municipality start,
  Municipality end,
  List<int> path,
) {
  return [
    start,
    for (final i in path.sublist(1, path.length - 1)) ?_municipalityForIndex(i),
    end,
  ];
}

/// Municipalities on the road from [start] to [end] in driving order, both
/// included, following the road network (not straight-line proximity). With
/// [direction], goes that way around the loop. Null when either end is not in
/// the table or no road connects them.
List<Municipality>? municipalitiesOnRoadBetween(
  Municipality start,
  Municipality end, {
  RoadRouteDirection? direction,
}) {
  final s = _indexForMunicipality(start);
  final e = _indexForMunicipality(end);
  if (s == null || e == null) return null;
  if (s == e) return [start];
  final path = _pathFor(s, e, direction, wholeTrip: true);
  if (path == null) return null;
  return _municipalitiesForPath(start, end, path);
}

/// One way to drive from a start to an end municipality.
class RoadRouteOption {
  final RoadRouteDirection direction;
  final List<Municipality> municipalities;
  final double distanceKm;
  final int drivingMinutes;

  const RoadRouteOption({
    required this.direction,
    required this.municipalities,
    required this.distanceKm,
    required this.drivingMinutes,
  });
}

/// Coastal and highland routes from [start] to [end] when both are sensible
/// (they differ and the longer is at most twice the shorter), shortest first.
/// Trips to or from Concepcion or Don Victoriano Chiongbian always get both.
/// Empty when there is only one sensible way.
List<RoadRouteOption> roadRouteOptionsBetween(
  Municipality start,
  Municipality end,
) {
  final s = _indexForMunicipality(start);
  final e = _indexForMunicipality(end);
  if (s == null || e == null || s == e) return const [];
  final paths = _directionPaths(s, e);
  final coastal = paths.coastal;
  final highland = paths.highland;
  if (coastal == null || highland == null) return const [];
  if (_samePath(coastal, highland)) return const [];
  final options = [
    for (final (dir, path) in [
      (RoadRouteDirection.coastal, coastal),
      (RoadRouteDirection.highland, highland),
    ])
      RoadRouteOption(
        direction: dir,
        municipalities: _municipalitiesForPath(start, end, path),
        distanceKm: _pathKm(path),
        drivingMinutes: _pathMinutes(path),
      ),
  ]..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
  if (!_alwaysBothRoutes(s, e) &&
      options.last.distanceKm > options.first.distanceKm * 2) {
    return const [];
  }
  return options;
}

/// Names of the towns strictly between [fromNameOrLocation] and
/// [toNameOrLocation] on the road network, in driving order.
List<String> roadTownsBetween(
  String fromNameOrLocation,
  String toNameOrLocation, {
  RoadRouteDirection? direction,
}) {
  final a = roadTableIndexFor(fromNameOrLocation);
  final b = roadTableIndexFor(toNameOrLocation);
  if (a == null || b == null || a == b) return const [];
  final path = _pathFor(a, b, direction);
  if (path == null || path.length <= 2) return const [];
  return [for (final i in path.sublist(1, path.length - 1)) _kRoadTableTowns[i]];
}

String municipalRoadDistanceDocId(String fromMunicipality, String toMunicipality) {
  return '${municipalitySlug(fromMunicipality)}__${municipalitySlug(toMunicipality)}';
}

Map<String, dynamic> _roadDistancePayload(int from, int to) {
  final km = _roadKmAt(from, to);
  final fromName = _kRoadTableTowns[from];
  final toName = _kRoadTableTowns[to];
  return {
    'fromMunicipality': fromName,
    'toMunicipality': toName,
    'fromMunicipalitySlug': municipalitySlug(fromName),
    'toMunicipalitySlug': municipalitySlug(toName),
    'distanceKm': km,
    'drivingMinutes': _drivingMinAt(from, to),
    'travelMinutesByMode': {
      for (final mode in kRoadDistanceTransportModes)
        mode: travelMinutesForKm(km, mode),
    },
    'fromLat': _kTownCenters[from][0],
    'fromLng': _kTownCenters[from][1],
    'toLat': _kTownCenters[to][0],
    'toLng': _kTownCenters[to][1],
    'source': _kRoadDataSource,
  };
}

/// Reads [kMunicipalRoadDistancesCollection] and overrides the embedded table.
/// Keeps the embedded values when Firestore is empty or unreadable.
Future<void> loadMunicipalRoadDistancesFromFirestore() async {
  try {
    final snap =
        await fetchPublicFirestoreCollection(kMunicipalRoadDistancesCollection);
    var applied = 0;
    for (final doc in snap.docs) {
      final d = doc.data();
      final from = roadTableIndexFor('${d['fromMunicipality'] ?? ''}');
      final to = roadTableIndexFor('${d['toMunicipality'] ?? ''}');
      if (from == null || to == null || from == to) continue;
      final km = d['distanceKm'];
      if (km is num && km > 0) {
        _remoteRoadKm[_pairKey(from, to)] = km.toDouble();
        applied++;
      }
      final min = d['drivingMinutes'];
      if (min is num && min > 0) {
        _remoteDrivingMin[_pairKey(from, to)] = min.round();
      }
    }
    if (kDebugMode) {
      debugPrint('Firestore load $kMunicipalRoadDistancesCollection: $applied pairs');
    }
  } catch (e) {
    debugPrint('loadMunicipalRoadDistancesFromFirestore: $e');
  }
}

/// Uploads every directed pair (272 docs). Stable ids — safe to re-run.
Future<int> syncMunicipalRoadDistancesToFirestore() async {
  await ensurePermanentStaffRoleForCatalogWrite();
  final firestore = FirebaseFirestore.instance;
  final col = firestore.collection(kMunicipalRoadDistancesCollection);
  final batch = firestore.batch();
  var count = 0;
  for (var i = 0; i < _kRoadTableTowns.length; i++) {
    for (var j = 0; j < _kRoadTableTowns.length; j++) {
      if (i == j) continue;
      final payload = _roadDistancePayload(i, j)
        ..['updatedAt'] = FieldValue.serverTimestamp();
      batch.set(
        col.doc(municipalRoadDistanceDocId(_kRoadTableTowns[i], _kRoadTableTowns[j])),
        payload,
        SetOptions(merge: true),
      );
      count++;
    }
  }
  await batch.commit();
  return count;
}
