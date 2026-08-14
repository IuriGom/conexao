import 'dart:math';

import 'models.dart';

/// In-memory timetable for one city pack + one service day.
///
/// Built once per (pack, day) and reused for all queries. Connections are
/// pre-sorted by departure — the CSA scan is a single linear pass.
class Timetable {
  final Map<int, StopNode> stops;
  final Map<int, TripInfo> trips;

  /// All connections on the service day, sorted by departure time.
  final List<Connection> connections;

  /// tripI -> ordered (stopI, arrSecs, depSecs) for journey reconstruction.
  final Map<int, List<(int, int, int)>> tripStopTimes;

  /// Walking edges between nearby stops: stopI -> [(toI, walkSecs)].
  final Map<int, List<(int, int)>> footpaths;

  /// Active services on the queried day (service_i set).
  final Set<int> activeServices;

  /// Grid index for nearest-stop queries.
  final Map<(int, int), List<int>> _grid;
  final double _cellDeg;

  Timetable({
    required this.stops,
    required this.trips,
    required List<Connection> connections,
    required this.tripStopTimes,
    required this.footpaths,
    required this.activeServices,
    double gridCellDeg = 0.005, // ~500 m
  })  : connections = List.of(connections)..sort(
            (a, b) => a.dep.compareTo(b.dep)),
        _cellDeg = gridCellDeg,
        _grid = _buildGrid(stops, gridCellDeg);

  static Map<(int, int), List<int>> _buildGrid(
      Map<int, StopNode> stops, double cell) {
    final grid = <(int, int), List<int>>{};
    for (final s in stops.values) {
      grid.putIfAbsent(_cell(s.lat, s.lon, cell), () => []).add(s.i);
    }
    return grid;
  }

  static (int, int) _cell(double lat, double lon, double cell) =>
      ((lat / cell).floor(), (lon / cell).floor());

  /// Stops within [maxMeters] of a point, with walking time in seconds.
  Map<int, int> nearestStops(double lat, double lon, double maxMeters,
      {double walkSpeedMps = 1.2}) {
    final out = <int, int>{};
    final range = (maxMeters / 111000 / _cellDeg).ceil() + 1;
    final (clat, clon) = _cell(lat, lon, _cellDeg);
    for (var a = -range; a <= range; a++) {
      for (var o = -range; o <= range; o++) {
        for (final si in _grid[(clat + a, clon + o)] ?? const <int>[]) {
          final s = stops[si]!;
          final d = haversineM(lat, lon, s.lat, s.lon);
          if (d <= maxMeters) {
            final secs = (d / walkSpeedMps).ceil();
            if (!out.containsKey(si) || out[si]! > secs) out[si] = secs;
          }
        }
      }
    }
    return out;
  }

  /// Builds walking edges between stops closer than [maxWalkMeters].
  /// Used so the router can transfer between nearby stops on foot
  /// (e.g. bus stop -> metro station across the street).
  static Map<int, List<(int, int)>> buildFootpaths(
    Map<int, StopNode> stops, {
    double maxWalkMeters = 400,
    double walkSpeedMps = 1.2,
  }) {
    final foot = <int, List<(int, int)>>{};
    final grid = _buildGrid(stops, 0.005);
    for (final s in stops.values) {
      final (clat, clon) = _cell(s.lat, s.lon, 0.005);
      for (var a = -1; a <= 1; a++) {
        for (var o = -1; o <= 1; o++) {
          for (final oi in grid[(clat + a, clon + o)] ?? const <int>[]) {
            if (oi == s.i) continue;
            final t = stops[oi]!;
            final d = haversineM(s.lat, s.lon, t.lat, t.lon);
            if (d <= maxWalkMeters) {
              foot.putIfAbsent(s.i, () => []).add(
                  (oi, max(60, (d / walkSpeedMps).ceil())));
            }
          }
        }
      }
    }
    return foot;
  }
}

/// Great-circle distance in meters.
double haversineM(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
          sin(dLon / 2) * sin(dLon / 2);
  return 2 * r * asin(sqrt(a));
}
