/// Core data types for the on-device routing engine.
///
/// The engine works on a Timetable loaded from a city pack (see
/// pipeline/compile_gtfs.py). Times are seconds since 00:00 of the service
/// day (values >= 24*3600 are legal, per GTFS convention).
library;

/// A transit stop as the router sees it.
class StopNode {
  final int i; // pack stop_i
  final String name;
  final double lat, lon;

  const StopNode(this.i, this.name, this.lat, this.lon);
}

/// One edge of the timetable graph: a trip visiting two consecutive stops.
/// Sorted by [dep] for the connection scan.
class Connection {
  final int tripI;
  final int fromI, toI;
  final int dep, arr; // seconds

  const Connection(this.tripI, this.fromI, this.toI, this.dep, this.arr);
}

/// Static info about a trip, for display and honest labeling.
class TripInfo {
  final int tripI;
  final String routeShortName;
  final String? headsign;
  final int routeType; // GTFS route_type: 0 VLT, 1 metro, 2 rail, 3 bus...
  final int serviceI;

  /// From frequencies.txt materialization: 1 = exact scheduled times,
  /// 0 = headway-based ("a cada ~X min" — never show fake precision),
  /// null = ordinary scheduled trip.
  final int? freqExact;

  const TripInfo({
    required this.tripI,
    required this.routeShortName,
    required this.serviceI,
    this.headsign,
    this.routeType = 3,
    this.freqExact,
  });
}

/// One leg of a journey: either a walk or a ride on a single trip.
class Leg {
  final bool isWalk;
  final int fromI, toI;
  final String fromName, toName;
  final int startSecs, endSecs;

  /// Ride legs only:
  final TripInfo? trip;
  final int stopCount;

  const Leg.walk({
    required this.fromI,
    required this.toI,
    required this.fromName,
    required this.toName,
    required this.startSecs,
    required this.endSecs,
  })  : isWalk = true,
        trip = null,
        stopCount = 0;

  const Leg.ride({
    required this.fromI,
    required this.toI,
    required this.fromName,
    required this.toName,
    required this.startSecs,
    required this.endSecs,
    required this.trip,
    required this.stopCount,
  }) : isWalk = false;

  int get durationSecs => endSecs - startSecs;

  /// True when times come from a headway-based feed: the UI must render
  /// "a cada ~X min", never a fake precise departure.
  bool get isApproximate => trip?.freqExact == 0;
}

/// A complete A->B journey.
class Journey {
  final List<Leg> legs;

  const Journey(this.legs);

  int get departureSecs => legs.first.startSecs;
  int get arrivalSecs => legs.last.endSecs;
  int get durationSecs => arrivalSecs - departureSecs;
  int get transfers => legs.where((l) => !l.isWalk).length - 1;

  @override
  String toString() {
    String fmt(int s) =>
        '${(s ~/ 3600).toString().padLeft(2, '0')}:'
        '${((s % 3600) ~/ 60).toString().padLeft(2, '0')}';
    final parts = legs.map((l) => l.isWalk
        ? 'walk ${l.durationSecs ~/ 60}min'
        : '${l.trip!.routeShortName} '
            '${fmt(l.startSecs)}->${fmt(l.endSecs)} '
            '(${l.stopCount} stops)${l.isApproximate ? ' ~' : ''}');
    return 'Journey ${fmt(departureSecs)}->${fmt(arrivalSecs)} '
        '(${durationSecs ~/ 60}min, $transfers transfers): '
        '${parts.join(' | ')}';
  }
}
