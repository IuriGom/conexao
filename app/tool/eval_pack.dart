// Development tool: route on a real compiled pack.
// Usage: dart run tool/eval_pack.dart <pack.sqlite> [YYYY-MM-DD]
// ignore_for_file: avoid_print
import 'dart:io';

import 'package:conexao/routing/csa.dart';
import 'package:conexao/routing/pack_loader.dart';

void main(List<String> args) {
  final loader = PackLoader(args.first);
  final day = args.length > 1 ? DateTime.parse(args[1]) : DateTime(2026, 8, 14);
  print('city: ${loader.cityId}');

  final sw = Stopwatch()..start();
  final tt = loader.loadForDay(day);
  print('load: ${sw.elapsed} | stops=${tt.stops.length} '
      'trips=${tt.trips.length} connections=${tt.connections.length}');

  final router = CsaRouter(tt);
  final pairs = {
    'Centro -> Pampulha': [-19.9191, -43.9386, -19.8519, -43.9506],
    'Centro -> Barreiro': [-19.9191, -43.9386, -19.9762, -44.0245],
    'Savassi -> Estação Central': [-19.9369, -43.9372, -19.9170, -43.9340],
  };
  for (final e in pairs.entries) {
    sw.reset();
    final j = router.route(
      originLat: e.value[0], originLon: e.value[1],
      destLat: e.value[2], destLon: e.value[3],
      departureSecs: 8 * 3600,
    );
    print('\n== ${e.key} (${sw.elapsedMilliseconds}ms)');
    print(j == null ? '   no journey found' : '   $j');
  }
  loader.close();
  exit(0);
}
