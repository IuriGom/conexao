import 'models.dart';
import 'timetable.dart';

/// On-device trip planner using the Connection Scan Algorithm (CSA).
///
/// Single linear pass over the day's connections, earliest-arrival.
/// Reference implementation: Mobroute (github.com/MobilityData/awesome-transit).
///
/// Layer 1 of the app's routing strategy (docs/ARCHITECTURE.md): always
/// works, fully offline. Honest-labeling rules: legs on headway-based trips
/// (frequencies.txt, `freqExact == 0`) are marked approximate.
class CsaRouter {
  final Timetable tt;

  /// Minimum time to alight one vehicle and board another at/near a stop.
  final int transferSlackSecs;

  CsaRouter(this.tt, {this.transferSlackSecs = 180});

  /// Plans a journey from (originLat, originLon) to (destLat, destLon),
  /// departing no earlier than [departureSecs]. Returns null if unreachable.
  Journey? route({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
    required int departureSecs,
    double maxWalkMeters = 900,
  }) {
    final origins = tt.nearestStops(originLat, originLon, maxWalkMeters);
    final dests = tt.nearestStops(destLat, destLon, maxWalkMeters);
    if (origins.isEmpty || dests.isEmpty) return null;

    const inf = 1 << 62;
    final inTime = <int, int>{}; // earliest arrival per stop
    final parent = <int, _Link>{}; // how we got there
    final boarded = <int, int>{}; // tripI -> boarding stop

    for (final e in origins.entries) {
      inTime[e.key] = departureSecs + e.value;
      parent[e.key] = _Link.origin(e.key, departureSecs + e.value);
    }

    var bestDest = inf;
    int? bestDestStop;

    void relax(int tripI, int fromI, int toI, int dep, int arr) {
      if (arr >= (inTime[toI] ?? inf)) return;
      inTime[toI] = arr;
      parent[toI] = _Link.ride(tripI, fromI, toI, dep, arr);
      // Walk onward from this stop (footpath transfer / dest approach).
      for (final f in tt.footpaths[toI] ?? const <(int, int)>[]) {
        final wArr = arr + f.$2;
        if (wArr < (inTime[f.$1] ?? inf)) {
          inTime[f.$1] = wArr;
          parent[f.$1] = _Link.walk(toI, f.$1, arr, wArr);
        }
      }
      final dw = dests[toI];
      if (dw != null && arr + dw < bestDest) {
        bestDest = arr + dw;
        bestDestStop = toI;
      }
    }

    for (final c in tt.connections) {
      if (c.dep > bestDest) break; // nothing later can improve the result
      final trip = tt.trips[c.tripI];
      if (trip == null || !tt.activeServices.contains(trip.serviceI)) {
        continue;
      }
      if (boarded.containsKey(c.tripI)) {
        relax(c.tripI, c.fromI, c.toI, c.dep, c.arr);
        continue;
      }
      final reach = inTime[c.fromI];
      if (reach != null && reach + transferSlackSecs <= c.dep) {
        boarded[c.tripI] = c.fromI;
        relax(c.tripI, c.fromI, c.toI, c.dep, c.arr);
      }
    }

    if (bestDestStop == null) return null;
    return _reconstruct(bestDestStop!, parent, origins, dests,
        departureSecs, dests[bestDestStop]!);
  }

  Journey _reconstruct(
    int destStop,
    Map<int, _Link> parent,
    Map<int, int> origins,
    Map<int, int> dests,
    int departureSecs,
    int finalWalkSecs,
  ) {
    // Walk the parent chain back to an origin stop.
    final links = <_Link>[];
    var cur = destStop;
    while (true) {
      final link = parent[cur];
      if (link == null || link.kind == _Kind.origin) break;
      links.add(link);
      cur = link.fromI;
    }
    final chain = links.reversed.toList();
    final originStop = chain.isEmpty ? destStop : chain.first.fromI;

    final legs = <Leg>[];
    String name(int i) => i == -1
        ? '—'
        : tt.stops[i]?.name ?? '#$i';

    // Initial walk: origin point -> first boarding stop.
    final firstWalk = origins[originStop] ?? 0;
    if (firstWalk > 0) {
      legs.add(Leg.walk(
        fromI: -1, toI: originStop,
        fromName: 'Origem', toName: name(originStop),
        startSecs: departureSecs, endSecs: departureSecs + firstWalk,
      ));
    }

    var i = 0;
    while (i < chain.length) {
      final link = chain[i];
      if (link.kind == _Kind.walk) {
        legs.add(Leg.walk(
          fromI: link.fromI, toI: link.toI,
          fromName: name(link.fromI), toName: name(link.toI),
          startSecs: link.dep, endSecs: link.arr,
        ));
        i++;
        continue;
      }
      // Ride: consume all consecutive links of this trip.
      final tripI = link.tripI!;
      var last = link;
      var j = i;
      while (j < chain.length &&
          chain[j].kind == _Kind.ride &&
          chain[j].tripI == tripI) {
        last = chain[j];
        j++;
      }
      legs.add(Leg.ride(
        fromI: link.fromI, toI: last.toI,
        fromName: name(link.fromI), toName: name(last.toI),
        startSecs: _depAt(tripI, link.fromI, link.dep),
        endSecs: last.arr,
        trip: tt.trips[tripI],
        stopCount: j - i,
      ));
      i = j;
    }

    // Final walk: alighting stop -> destination point.
    if (finalWalkSecs > 0) {
      final alight = legs.isEmpty ? departureSecs : legs.last.endSecs;
      legs.add(Leg.walk(
        fromI: destStop, toI: -1,
        fromName: name(destStop), toName: 'Destino',
        startSecs: alight, endSecs: alight + finalWalkSecs,
      ));
    }
    return Journey(legs);
  }

  /// Departure time of [tripI] at [stopI], falling back to the scanned
  /// connection's departure. The board stop may precede the first
  /// arrival-improving connection of the trip.
  int _depAt(int tripI, int stopI, int fallback) {
    final lazy = tt.depAtProvider;
    if (lazy != null) return lazy(tripI, stopI) ?? fallback;
    final st = tt.tripStopTimes[tripI] ?? const <(int, int, int)>[];
    for (final row in st) {
      if (row.$1 == stopI) return row.$3;
    }
    return fallback;
  }
}

enum _Kind { origin, walk, ride }

class _Link {
  final _Kind kind;
  final int? tripI;
  final int fromI;
  final int toI;
  final int dep, arr;

  _Link.origin(this.toI, this.arr)
      : kind = _Kind.origin,
        tripI = null,
        fromI = -1,
        dep = 0;

  _Link.walk(this.fromI, this.toI, this.dep, this.arr)
      : kind = _Kind.walk,
        tripI = null;

  _Link.ride(this.tripI, this.fromI, this.toI, this.dep, this.arr)
      : kind = _Kind.ride;
}
