import 'package:sqlite3/sqlite3.dart';

import 'models.dart';
import 'timetable.dart';

/// One hit from the pack's FTS5 search index.
class SearchHit {
  final String kind; // 'stop' | 'route'
  final int refI;
  final String name;

  const SearchHit({required this.kind, required this.refI, required this.name});
}

/// Loads a city pack (produced by pipeline/compile_gtfs.py) into an
/// in-memory [Timetable] for one service day.
///
/// Memory discipline (plan §1A: low-end Android is the dominant device):
/// the connections list is the only city-scale structure held in RAM.
/// Per-trip stop times are NOT duplicated in memory — journey
/// reconstruction queries the pack lazily via [Timetable.depAtProvider].
///
/// GTFS service-day rule: a service runs from noon minus 12h of its day
/// to noon of the next (times >= 24:00 belong to the previous day).
class PackLoader {
  final Database db;

  PackLoader(String path) : db = sqlite3.open(path, mode: OpenMode.readOnly);

  void close() => db.dispose();

  String? get cityId {
    final r = db.select("SELECT value FROM meta WHERE key='city_id'");
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  /// Looks up a single stop by its pack id (used after FTS search).
  StopNode? stopByI(int stopI) {
    final r = db.select(
        'SELECT stop_i, name, lat, lon FROM stops WHERE stop_i = ?',
        [stopI]);
    if (r.isEmpty) return null;
    final row = r.first;
    return StopNode(row['stop_i'] as int, (row['name'] as String?) ?? '',
        (row['lat'] as double?) ?? 0, (row['lon'] as double?) ?? 0);
  }

  /// Full-text search over stops and routes (FTS5 index built by the  /// compiler; trigram when available = substring matching).
  /// Query terms are quoted, so arbitrary user input can't break FTS syntax.
  List<SearchHit> search(String query, {int limit = 20}) {
    final terms = query
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map((t) => '"${t.replaceAll('"', ' ')}"')
        .join(' ');
    if (terms.isEmpty) return const [];
    return [
      for (final r in db.select(
          'SELECT kind, ref_i, name FROM search '
          'WHERE search MATCH ? LIMIT ?', [terms, limit]))
        SearchHit(
          kind: r['kind'] as String,
          refI: r['ref_i'] as int,
          name: r['name'] as String,
        ),
    ];
  }

  /// Service ids active on [day] per calendar.txt + calendar_dates.txt.
  Set<int> activeServices(DateTime day) {
    final ymd = '${day.year.toString().padLeft(4, '0')}'
        '${day.month.toString().padLeft(2, '0')}'
        '${day.day.toString().padLeft(2, '0')}';
    const cols = [
      'monday', 'tuesday', 'wednesday', 'thursday', 'friday',
      'saturday', 'sunday',
    ];
    final col = cols[day.weekday - 1];

    final active = <int>{};
    for (final r in db.select(
        'SELECT service_i FROM calendar '
        'WHERE start_date <= ? AND end_date >= ? AND $col = 1',
        [ymd, ymd])) {
      active.add(r['service_i'] as int);
    }
    for (final r in db.select(
        'SELECT service_i, exception_type FROM calendar_dates '
        'WHERE date = ?', [ymd])) {
      if (r['exception_type'] == 1) {
        active.add(r['service_i'] as int);
      } else {
        active.remove(r['service_i'] as int);
      }
    }
    return active;
  }

  /// Builds the full routing timetable for [day].
  ///
  /// [lazyDepAt] keeps a prepared statement for journey reconstruction.
  /// Set it to false when the Timetable must cross an isolate boundary
  /// (closures over native resources cannot be transferred); reconstruction
  /// then falls back to connection departure times, which differ only in
  /// rare board-earlier-than-first-improvement cases.
  Timetable loadForDay(DateTime day,
      {double footpathMaxMeters = 400, bool lazyDepAt = true}) {
    final services = activeServices(day);

    final stops = <int, StopNode>{};
    for (final r in db.select(
        'SELECT stop_i, name, lat, lon FROM stops '
        'WHERE location_type = 0 AND lat IS NOT NULL')) {
      stops[r['stop_i'] as int] = StopNode(
        r['stop_i'] as int,
        (r['name'] as String?) ?? '',
        r['lat'] as double,
        r['lon'] as double,
      );
    }

    final trips = <int, TripInfo>{};
    final connections = <Connection>[];
    if (services.isNotEmpty) {
      final marks = List.filled(services.length, '?').join(',');
      final list = services.toList();
      for (final r in db.select(
          'SELECT t.trip_i, t.headsign, t.freq_exact, t.service_i, '
          'r.short_name, r.route_type '
          'FROM trips t JOIN routes r USING (route_i) '
          'WHERE t.service_i IN ($marks)', list)) {
        trips[r['trip_i'] as int] = TripInfo(
          tripI: r['trip_i'] as int,
          routeShortName: (r['short_name'] as String?) ?? '',
          headsign: r['headsign'] as String?,
          routeType: (r['route_type'] as int?) ?? 3,
          serviceI: r['service_i'] as int,
          freqExact: r['freq_exact'] as int?,
        );
      }

      // Connections: consecutive stop_times pairs per active trip,
      // streamed in (trip, sequence) order. arrival NULL means = departure.
      final stmt = db.prepare(
          'SELECT trip_i, stop_i, '
          'COALESCE(arrival_secs, departure_secs) AS arr, departure_secs '
          'FROM stop_times WHERE departure_secs IS NOT NULL AND trip_i IN '
          '(SELECT trip_i FROM trips WHERE service_i IN ($marks)) '
          'ORDER BY trip_i, stop_sequence');
      int? prevTrip, prevStop, prevArr;
      for (final r in stmt.select(list)) {
        final tripI = r['trip_i'] as int;
        final stopI = r['stop_i'] as int;
        final arr = r['arr'] as int;
        final dep = r['departure_secs'] as int;
        if (prevTrip == tripI && prevArr != null) {
          connections.add(Connection(tripI, prevStop!, stopI, prevArr, arr));
        }
        prevTrip = tripI;
        prevStop = stopI;
        prevArr = dep;
      }
      stmt.dispose();
    }

    int? Function(int, int)? depAtProvider;
    if (lazyDepAt) {
      final depStmt = db.prepare(
          'SELECT departure_secs FROM stop_times '
          'WHERE trip_i = ? AND stop_i = ? LIMIT 1');
      depAtProvider = (tripI, stopI) {
        final r = depStmt.select([tripI, stopI]);
        return r.isEmpty ? null : r.first['departure_secs'] as int?;
      };
    }

    return Timetable(
      stops: stops,
      trips: trips,
      connections: connections,
      tripStopTimes: const {},
      depAtProvider: depAtProvider,
      footpaths: Timetable.buildFootpaths(stops,
          maxWalkMeters: footpathMaxMeters),
      activeServices: services,
    );
  }
}
