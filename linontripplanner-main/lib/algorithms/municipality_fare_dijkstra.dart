import '../misamis_occidental_fare_matrix.dart';

/// Minimum-fare paths on the official Misamis Occidental LGU fare graph (Dijkstra).
abstract final class MunicipalityFareDijkstra {
  static int get _n => kFareMatrixMunicipalityKeys.length;

  static int? _indexForKey(String matrixKey) {
    final idx = kFareMatrixMunicipalityKeys.indexOf(matrixKey);
    return idx >= 0 ? idx : null;
  }

  /// Directed fare PHP from matrix key [from] to [to], or null if unknown.
  static int? _edgeFare(String from, String to) {
    if (from == to) return 0;
    return farePhpBetweenMatrixKeys(from, to);
  }

  /// Shortest (minimum total fare) path as matrix keys, including endpoints.
  static List<String> shortestPathKeys(String fromKey, String toKey) {
    if (fromKey == toKey) return [fromKey];

    final fromIdx = _indexForKey(fromKey);
    final toIdx = _indexForKey(toKey);
    if (fromIdx == null || toIdx == null) return [fromKey, toKey];

    final dist = List<double>.filled(_n, double.infinity);
    final prev = List<int?>.filled(_n, null);
    final settled = List<bool>.filled(_n, false);
    dist[fromIdx] = 0;

    for (var step = 0; step < _n; step++) {
      var u = -1;
      var best = double.infinity;
      for (var i = 0; i < _n; i++) {
        if (!settled[i] && dist[i] < best) {
          best = dist[i];
          u = i;
        }
      }
      if (u < 0 || best == double.infinity) break;
      if (u == toIdx) break;
      settled[u] = true;

      for (var v = 0; v < _n; v++) {
        if (u == v) continue;
        final fare = kMisamisOccidentalFareMatrixPhp[u][v];
        if (fare <= 0) continue;
        final alt = dist[u] + fare;
        if (alt < dist[v]) {
          dist[v] = alt;
          prev[v] = u;
        }
      }
    }

    if (dist[toIdx] == double.infinity) return [fromKey, toKey];

    final pathIdx = <int>[];
    for (var at = toIdx; at >= 0; at = prev[at] ?? -1) {
      pathIdx.add(at);
      if (at == fromIdx) break;
    }
    if (pathIdx.isEmpty || pathIdx.last != fromIdx) return [fromKey, toKey];
    return [
      for (final i in pathIdx.reversed) kFareMatrixMunicipalityKeys[i],
    ];
  }

  /// Sum of matrix fares along [pathKeys] (consecutive hops).
  static int? totalFareAlongPath(List<String> pathKeys) {
    if (pathKeys.length < 2) return 0;
    var sum = 0;
    for (var i = 0; i < pathKeys.length - 1; i++) {
      final hop = _edgeFare(pathKeys[i], pathKeys[i + 1]);
      if (hop == null) return null;
      sum += hop;
    }
    return sum;
  }

  /// Minimum total fare PHP between two matrix keys (Dijkstra).
  static int? minimumFarePhp(String fromKey, String toKey) {
    final path = shortestPathKeys(fromKey, toKey);
    return totalFareAlongPath(path);
  }
}
