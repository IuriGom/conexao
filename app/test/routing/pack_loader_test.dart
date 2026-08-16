import 'dart:io';

import 'package:conexao/routing/csa.dart';
import 'package:conexao/routing/pack_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

/// Builds a tiny pack SQLite with the exact schema compile_gtfs.py writes,
/// containing the same mini-city as csa_test.dart.
String buildFixturePack(Directory tmp) {
  final path = '${tmp.path}/testlandia.sqlite';
  final db = sqlite3.open(path);
  db.execute('''
CREATE TABLE agency (agency_id TEXT PRIMARY KEY, name TEXT, url TEXT, timezone TEXT, lang TEXT);
CREATE TABLE stops (stop_i INTEGER PRIMARY KEY, stop_id TEXT UNIQUE, code TEXT, name TEXT, lat REAL, lon REAL, parent_i INTEGER, location_type INTEGER DEFAULT 0);
CREATE TABLE routes (route_i INTEGER PRIMARY KEY, route_id TEXT UNIQUE, agency_id TEXT, short_name TEXT, long_name TEXT, route_type INTEGER, color TEXT, text_color TEXT);
CREATE TABLE services (service_i INTEGER PRIMARY KEY, service_id TEXT UNIQUE);
CREATE TABLE trips (trip_i INTEGER PRIMARY KEY, trip_id TEXT UNIQUE, route_i INTEGER, service_i INTEGER, headsign TEXT, direction_id INTEGER, shape_i INTEGER, freq_exact INTEGER);
CREATE TABLE stop_times (trip_i INTEGER, stop_sequence INTEGER, stop_i INTEGER, arrival_secs INTEGER, departure_secs INTEGER, PRIMARY KEY (trip_i, stop_sequence)) WITHOUT ROWID;
CREATE TABLE calendar (service_i INTEGER PRIMARY KEY, monday INTEGER, tuesday INTEGER, wednesday INTEGER, thursday INTEGER, friday INTEGER, saturday INTEGER, sunday INTEGER, start_date TEXT, end_date TEXT);
CREATE TABLE calendar_dates (service_i INTEGER, date TEXT, exception_type INTEGER);
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
''');
  db.execute("INSERT INTO meta VALUES ('city_id', 'testlandia')");
  db.execute(
      "INSERT INTO stops VALUES (1,'S1',NULL,'Terminal Centro',-15.8,-47.9,NULL,0),"
      "(2,'S2',NULL,'Av. Sul 1200',-15.811,-47.9,NULL,0),"
      "(3,'S3',NULL,'Av. Sul 2400',-15.822,-47.9,NULL,0),"
      "(4,'S4',NULL,'Praça da Estação',-15.833,-47.9,NULL,0),"
      "(5,'S5',NULL,'Metrô Centro',-15.8328,-47.9,NULL,0),"
      "(6,'S6',NULL,'Metrô Norte',-15.845,-47.9,NULL,0)");
  db.execute(
      "INSERT INTO routes VALUES (1,'R_BUS',NULL,'100','Centro - Praça',3,NULL,NULL),"
      "(2,'R_METRO',NULL,'L1','Linha 1',1,NULL,NULL)");
  db.execute("INSERT INTO services VALUES (1,'WKD'),(2,'SUN')");
  db.execute(
      "INSERT INTO trips VALUES (101,'T1',1,1,'Praça',0,NULL,NULL),"
      "(102,'T2',1,1,'Praça',0,NULL,NULL),"
      "(201,'M1',2,1,NULL,0,NULL,0),"
      "(202,'M3',2,1,NULL,0,NULL,NULL),"
      "(203,'MS',2,2,NULL,0,NULL,NULL)");
  int h(int hh, int mm) => hh * 3600 + mm * 60;
  final st = db.prepare(
      'INSERT INTO stop_times VALUES (?,?,?,?,?)');
  void strows(int trip, List<(int, int, int)> rows) {
    var seq = 1;
    for (final (stop, arr, dep) in rows) {
      // compiler rule: arrival NULL when equal to departure
      st.execute([trip, seq++, stop, arr == dep ? null : arr, dep]);
    }
  }

  strows(101, [(1, h(8, 0), h(8, 0)), (2, h(8, 3), h(8, 3)), (3, h(8, 6), h(8, 6)), (4, h(8, 10), h(8, 10))]);
  strows(102, [(1, h(9, 0), h(9, 0)), (2, h(9, 3), h(9, 3)), (3, h(9, 6), h(9, 6)), (4, h(9, 10), h(9, 10))]);
  strows(201, [(5, h(8, 15), h(8, 15)), (6, h(8, 25), h(8, 25))]);
  strows(202, [(5, h(9, 20), h(9, 20)), (6, h(9, 30), h(9, 30))]);
  strows(203, [(5, h(10, 0), h(10, 0)), (6, h(10, 10), h(10, 10))]);
  st.dispose();
  // WKD = Monday-Friday, a wide window covering the test dates.
  db.execute(
      "INSERT INTO calendar VALUES (1,1,1,1,1,1,0,0,'20260101','20261231')");
  db.execute(
      "INSERT INTO calendar VALUES (2,0,0,0,0,0,0,1,'20260101','20261231')");
  // Exception: Sunday service also runs on one Monday (2026-08-17).
  db.execute("INSERT INTO calendar_dates VALUES (2,'20260817',1)");
  // And WKD is cancelled on Tuesday 2026-08-18 (holiday).
  db.execute("INSERT INTO calendar_dates VALUES (1,'20260818',2)");
  db.dispose();
  return path;
}

void main() {
  late Directory tmp;
  late String packPath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('conexao-pack-');
    packPath = buildFixturePack(tmp);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  // 2026-08-14 is a Friday (WKD). 2026-08-16 is a Sunday.
  final friday = DateTime(2026, 8, 14);
  final sunday = DateTime(2026, 8, 16);

  test('reads city id', () {
    final loader = PackLoader(packPath);
    expect(loader.cityId, 'testlandia');
    loader.close();
  });

  test('active services: weekday vs weekend vs exceptions', () {
    final loader = PackLoader(packPath);
    expect(loader.activeServices(friday), {1});
    expect(loader.activeServices(sunday), {2});
    expect(loader.activeServices(DateTime(2026, 8, 17)), {1, 2}); // Monday + SUN exception
    expect(loader.activeServices(DateTime(2026, 8, 18)), isEmpty); // WKD cancelled
    loader.close();
  });

  test('loads timetable and routes a trip with a footpath transfer', () {
    final loader = PackLoader(packPath);
    final tt = loader.loadForDay(friday);
    expect(tt.stops.length, 6);
    expect(tt.trips.length, 4); // WKD trips only
    expect(tt.connections, hasLength(8)); // 3 + 3 + 1 + 1
    expect(tt.footpaths.keys, containsAll([4, 5]));

    final j = CsaRouter(tt, transferSlackSecs: 120).route(
      originLat: -15.8, originLon: -47.9,
      destLat: -15.845, destLon: -47.9,
      departureSecs: 7 * 3600,
    );
    expect(j, isNotNull);
    expect(j!.transfers, 1);
    expect(j.legs.map((l) => l.isWalk ? 'walk' : 'ride'),
        ['ride', 'walk', 'ride']);
    expect(j.arrivalSecs, 8 * 3600 + 25 * 60);
    loader.close();
  });

  test('Sunday loads only Sunday service', () {
    final loader = PackLoader(packPath);
    final tt = loader.loadForDay(sunday);
    expect(tt.trips.keys, [203]);
    expect(tt.connections, hasLength(1));
    loader.close();
  });

  test('routes() lists lines ordered by short name', () {
    final loader = PackLoader(packPath);
    final r = loader.routes();
    expect(r.map((x) => x.shortName), ['100', 'L1']);
    expect(r[1].routeType, 1);
    loader.close();
  });

  test('stopsForRoute returns the canonical stop order per direction', () {
    final loader = PackLoader(packPath);
    expect(loader.routeDirections(1), [0]);
    final stops = loader.stopsForRoute(1, 0);
    expect(stops.map((s) => s.name),
        ['Terminal Centro', 'Av. Sul 1200', 'Av. Sul 2400',
         'Praça da Estação']);
    loader.close();
  });

  test('nextDepartures honors service day and afterSecs', () {
    final loader = PackLoader(packPath);
    final fridayMorning =
        loader.nextDepartures(1, friday, 7 * 3600, limit: 5);
    expect(fridayMorning.map((d) => d.depSecs),
        [8 * 3600, 9 * 3600]); // T1 08:00, T2 09:00
    expect(fridayMorning.first.routeShortName, '100');

    final afterT1 = loader.nextDepartures(1, friday, 8 * 3600 + 1);
    expect(afterT1.map((d) => d.depSecs), [9 * 3600]);

    // Sunday: only the metro (trip 203, stops 5-6) runs.
    expect(loader.nextDepartures(1, sunday, 0), isEmpty);
    final metro =
        loader.nextDepartures(5, sunday, 9 * 3600, limit: 1);
    expect(metro.single.depSecs, 10 * 3600);
    expect(metro.single.isApproximate, isFalse);
    loader.close();
  });
}
