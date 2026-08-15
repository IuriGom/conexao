import 'package:conexao/routing/csa.dart';
import 'package:conexao/routing/models.dart';
import 'package:conexao/routing/timetable.dart';
import 'package:flutter_test/flutter_test.dart';

/// Synthetic mini-city (stops ~1.2 km apart — big enough that walking
/// doesn't degenerately beat the bus on earliest-arrival):
///
///   Bus 100 (WKD):  1 -> 2 -> 3 -> 4        dep 08:00, arr 08:10
///   Bus 100 (WKD):  1 -> 2 -> 3 -> 4        dep 09:00, arr 09:10 (T2)
///   Metro L1 (WKD): 5 -> 6                  dep 08:15 (headway-based)
///   Metro L1 (WKD): 5 -> 6                  dep 09:20 (T_M3)
///   Metro L1 (SUN): 5 -> 6                  dep 10:00
///
/// Stop 4 (Praça da Estação) and stop 5 (Metrô Centro) are ~25 m apart:
/// footpath transfer. Geometry is schematic; times are what matter.
Timetable buildMiniCity({Set<int>? activeServices}) {
  final stops = {
    1: const StopNode(1, 'Terminal Centro', -15.8000, -47.9000),
    2: const StopNode(2, 'Av. Sul 1200', -15.8110, -47.9000),
    3: const StopNode(3, 'Av. Sul 2400', -15.8220, -47.9000),
    4: const StopNode(4, 'Praça da Estação', -15.8330, -47.9000),
    5: const StopNode(5, 'Metrô Centro', -15.8328, -47.9000),
    6: const StopNode(6, 'Metrô Norte', -15.8450, -47.9000),
  };
  const wkd = 1, sun = 2;
  final trips = {
    101: const TripInfo(tripI: 101, routeShortName: '100', serviceI: wkd),
    102: const TripInfo(tripI: 102, routeShortName: '100', serviceI: wkd),
    201: const TripInfo(
        tripI: 201, routeShortName: 'L1', serviceI: wkd,
        routeType: 1, freqExact: 0),
    202: const TripInfo(
        tripI: 202, routeShortName: 'L1', serviceI: wkd, routeType: 1),
    203: const TripInfo(
        tripI: 203, routeShortName: 'L1', serviceI: sun, routeType: 1),
  };
  int h(int hh, int mm) => hh * 3600 + mm * 60;
  final connections = <Connection>[
    // T1 bus, 08:00 -> 08:10
    Connection(101, 1, 2, h(8, 0), h(8, 3)),
    Connection(101, 2, 3, h(8, 3), h(8, 6)),
    Connection(101, 3, 4, h(8, 6), h(8, 10)),
    // T2 bus, 09:00 -> 09:10
    Connection(102, 1, 2, h(9, 0), h(9, 3)),
    Connection(102, 2, 3, h(9, 3), h(9, 6)),
    Connection(102, 3, 4, h(9, 6), h(9, 10)),
    // Metro WKD (headway-based trip + later exact trip)
    Connection(201, 5, 6, h(8, 15), h(8, 25)),
    Connection(202, 5, 6, h(9, 20), h(9, 30)),
    // Metro SUN only
    Connection(203, 5, 6, h(10, 0), h(10, 10)),
  ];
  final tripStopTimes = {
    101: [(1, h(8, 0), h(8, 0)), (2, h(8, 3), h(8, 3)), (3, h(8, 6), h(8, 6)), (4, h(8, 10), h(8, 10))],
    102: [(1, h(9, 0), h(9, 0)), (2, h(9, 3), h(9, 3)), (3, h(9, 6), h(9, 6)), (4, h(9, 10), h(9, 10))],
    201: [(5, h(8, 15), h(8, 15)), (6, h(8, 25), h(8, 25))],
    202: [(5, h(9, 20), h(9, 20)), (6, h(9, 30), h(9, 30))],
    203: [(5, h(10, 0), h(10, 0)), (6, h(10, 10), h(10, 10))],
  };
  final footpaths = {
    4: [(5, 60)],
    5: [(4, 60)],
  };
  return Timetable(
    stops: stops,
    trips: trips,
    connections: connections,
    tripStopTimes: tripStopTimes,
    footpaths: footpaths,
    activeServices: activeServices ?? {wkd},
  );
}

void main() {
  group('CsaRouter', () {
    test('direct ride, no transfers', () {
      final r = CsaRouter(buildMiniCity(), transferSlackSecs: 120);
      final j = r.route(
        originLat: -15.8000, originLon: -47.9000,
        destLat: -15.8220, destLon: -47.9000,
        departureSecs: 7 * 3600,
      );
      expect(j, isNotNull);
      expect(j!.transfers, 0);
      final rides = j.legs.where((l) => !l.isWalk).toList();
      expect(rides, hasLength(1));
      expect(rides.single.trip!.routeShortName, '100');
      expect(rides.single.startSecs, 8 * 3600);
      expect(rides.single.endSecs, 8 * 3600 + 6 * 60);
      expect(j.arrivalSecs, lessThan(8 * 3600 + 10 * 60));
    });

    test('one transfer via footpath (bus -> metro)', () {
      final r = CsaRouter(buildMiniCity(), transferSlackSecs: 120);
      final j = r.route(
        originLat: -15.8000, originLon: -47.9000,
        destLat: -15.8450, destLon: -47.9000,
        departureSecs: 7 * 3600,
      );
      expect(j, isNotNull);
      expect(j!.transfers, 1);
      final kinds = j.legs.map((l) => l.isWalk ? 'walk' : 'ride').toList();
      expect(kinds, ['ride', 'walk', 'ride']);
      expect(j.legs[0].trip!.routeShortName, '100');
      expect(j.legs[2].trip!.routeShortName, 'L1');
      expect(j.arrivalSecs, 8 * 3600 + 25 * 60);
    });

    test('later departure picks later trips', () {
      final r = CsaRouter(buildMiniCity(), transferSlackSecs: 120);
      final j = r.route(
        originLat: -15.8000, originLon: -47.9000,
        destLat: -15.8450, destLon: -47.9000,
        departureSecs: 8 * 3600 + 20 * 60, // 08:20 — T1/M1 both gone
      );
      expect(j, isNotNull);
      expect(j!.legs.where((l) => !l.isWalk).first.startSecs, 9 * 3600);
      expect(j.arrivalSecs, 9 * 3600 + 30 * 60);
    });

    test('service-day filter: Sunday service only', () {
      final r = CsaRouter(buildMiniCity(activeServices: {2}),
          transferSlackSecs: 120);
      final j = r.route(
        originLat: -15.8328, originLon: -47.9000, // at Metrô Centro
        destLat: -15.8450, destLon: -47.9000,
        departureSecs: 7 * 3600,
      );
      expect(j, isNotNull);
      final ride = j!.legs.firstWhere((l) => !l.isWalk);
      expect(ride.trip!.serviceI, 2);
      expect(ride.startSecs, 10 * 3600);
    });

    test('headway-based trips are labeled approximate', () {
      final r = CsaRouter(buildMiniCity(), transferSlackSecs: 120);
      final j = r.route(
        originLat: -15.8328, originLon: -47.9000,
        destLat: -15.8450, destLon: -47.9000,
        departureSecs: 7 * 3600,
      );
      final ride = j!.legs.firstWhere((l) => !l.isWalk);
      expect(ride.trip!.freqExact, 0);
      expect(ride.isApproximate, isTrue);
    });

    test('unreachable destination returns null', () {
      final r = CsaRouter(buildMiniCity(), transferSlackSecs: 120);
      final j = r.route(
        originLat: -15.8000, originLon: -47.9000,
        destLat: -15.5000, destLon: -47.5000, // far outside the city
        departureSecs: 7 * 3600,
      );
      expect(j, isNull);
    });

    test('identical parallel lines do not thrash transfers', () {
      // Metrô-DF case: Verde and Laranja share the trunk with identical
      // times. Earliest-arrival ties must not produce a journey that
      // alternates lines at every stop — staying on board wins ties.
      int h(int hh, int mm) => hh * 3600 + mm * 60;
      final stops = {
        for (var s = 1; s <= 6; s++)
          s: StopNode(s, 'Trunk $s', -15.8 - s * 0.011, -47.9),
      };
      final trips = {
        301: const TripInfo(tripI: 301, routeShortName: 'Verde', serviceI: 1),
        302: const TripInfo(
            tripI: 302, routeShortName: 'Laranja', serviceI: 1),
      };
      final conns = <Connection>[];
      final tst = <int, List<(int, int, int)>>{};
      for (final t in [301, 302]) {
        tst[t] = [];
        var secs = h(8, 0);
        for (var s = 1; s < 6; s++) {
          conns.add(Connection(t, s, s + 1, secs, secs + 120));
          tst[t]!.add((s, secs, secs));
          secs += 120;
        }
        tst[t]!.add((6, secs, secs));
      }
      final tt = Timetable(
        stops: stops, trips: trips, connections: conns,
        tripStopTimes: tst, footpaths: const {}, activeServices: {1},
      );
      final j = CsaRouter(tt).route(
        originLat: -15.811, originLon: -47.9,
        destLat: -15.866, destLon: -47.9,
        departureSecs: h(7, 55),
      );
      expect(j, isNotNull);
      expect(j!.transfers, 0);
      expect(j.legs.where((l) => !l.isWalk), hasLength(1));
      // Boards the 08:00 departure exactly — no phantom transfer slack
      // at the journey's first boarding.
      expect(j.legs.firstWhere((l) => !l.isWalk).startSecs, h(8, 0));
    });

    test('performance: 200k connections scan in reasonable time', () {
      // Synthetic big city: 2000 trips x 100 stops on a line.
      final stops = <int, StopNode>{};
      final trips = <int, TripInfo>{};
      final conns = <Connection>[];
      final tst = <int, List<(int, int, int)>>{};
      for (var s = 1; s <= 100; s++) {
        stops[s] = StopNode(s, 'Stop $s', -15.8 + s * 0.001, -47.9);
      }
      for (var t = 1; t <= 2000; t++) {
        trips[t] = TripInfo(tripI: t, routeShortName: 'X', serviceI: 1);
        var secs = 5 * 3600 + t * 30;
        tst[t] = [];
        for (var s = 1; s < 100; s++) {
          conns.add(Connection(t, s, s + 1, secs, secs + 60));
          tst[t]!.add((s, secs, secs));
          secs += 60;
        }
        tst[t]!.add((100, secs, secs));
      }
      final tt = Timetable(
        stops: stops, trips: trips, connections: conns,
        tripStopTimes: tst, footpaths: const {}, activeServices: {1},
      );
      final r = CsaRouter(tt);
      final sw = Stopwatch()..start();
      final j = r.route(
        originLat: -15.799, originLon: -47.9,
        destLat: -15.8 + 99 * 0.001, destLon: -47.9,
        departureSecs: 5 * 3600,
      );
      sw.stop();
      expect(j, isNotNull);
      // Debug-mode budget; release on a mid-range phone is far faster.
      expect(sw.elapsedMilliseconds, lessThan(5000));
      // ignore: avoid_print
      print('200k-connection scan: ${sw.elapsedMilliseconds}ms');
    });
  });
}
