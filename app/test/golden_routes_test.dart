import 'dart:io';

import 'package:conexao/routing/csa.dart';
import 'package:conexao/routing/pack_loader.dart';
import 'package:flutter_test/flutter_test.dart';

/// Golden routes (docs/ROADMAP.md Phase 2): known A→B pairs asserted
/// against the Brasília pack built FROM SOURCE (build_metro_df.py →
/// compile_gtfs.py), so the whole chain is exercised offline. Skips when
/// python3 is unavailable.
void main() {
  final python = Process.runSync('which', ['python3']).exitCode == 0;

  test('Brasília golden routes', () async {
    final tmp = Directory.systemTemp.createTempSync('conexao-golden-');
    final root = Directory.current.parent.path; // repo root from app/
    final build = await Process.run(
        'python3', ['$root/pipeline/build_metro_df.py']);
    expect(build.exitCode, 0, reason: build.stderr.toString());
    final pack = '${tmp.path}/brasilia.sqlite';
    final compile = await Process.run('python3', [
      '$root/pipeline/compile_gtfs.py',
      '${Directory.current.parent.path}/pipeline/tmp/metro_df_gtfs.zip',
      '-o', pack, '--city', 'brasilia',
    ]);
    expect(compile.exitCode, 0, reason: compile.stderr.toString());

    final loader = PackLoader(pack);
    // A Monday: full weekday service.
    final tt = loader.loadForDay(DateTime(2026, 8, 17),
        lazyDepAt: false);
    final r = CsaRouter(tt);

    // Central -> Ceilândia: direct on Verde, ~59 interpolated minutes.
    final central = r.route(
      originLat: -15.7932, originLon: -47.8846,
      destLat: -15.8056, destLon: -48.1213,
      departureSecs: 8 * 3600,
    );
    expect(central, isNotNull, reason: 'Central->Ceilândia must be reachable');
    expect(central!.transfers, 0);
    expect(central.durationSecs, greaterThan(40 * 60));
    expect(central.durationSecs, lessThan(75 * 60));

    // Samambaia -> Ceilândia: exactly one transfer at Águas Claras.
    final cross = r.route(
      originLat: -15.8737, originLon: -48.0849,
      destLat: -15.8056, destLon: -48.1213,
      departureSecs: 8 * 3600,
    );
    expect(cross, isNotNull);
    expect(cross!.transfers, 1);

    // Central -> Guará: direct, short hop down the trunk.
    final hop = r.route(
      originLat: -15.7932, originLon: -47.8846,
      destLat: -15.8267, destLon: -47.9834,
      departureSecs: 8 * 3600,
    );
    expect(hop, isNotNull);
    expect(hop!.transfers, 0);
    expect(hop.durationSecs, lessThan(45 * 60));

    // Sunday: service starts 07:00 — an 05:30 query must board after 07:00.
    final ttSun = loader.loadForDay(DateTime(2026, 8, 16), lazyDepAt: false);
    final early = CsaRouter(ttSun).route(
      originLat: -15.7932, originLon: -47.8846,
      destLat: -15.8267, destLon: -47.9834,
      departureSecs: 5 * 3600 + 30 * 60,
    );
    expect(early, isNotNull);
    expect(early!.legs.firstWhere((l) => !l.isWalk).startSecs,
        greaterThanOrEqualTo(7 * 3600));

    loader.close();
    tmp.deleteSync(recursive: true);
  }, skip: python ? false : 'python3 not available');

  test('Brasília search folds diacritics (aguas -> Águas Claras)',
      () async {
    final tmp = Directory.systemTemp.createTempSync('conexao-golden-');
    final root = Directory.current.parent.path;
    await Process.run('python3', ['$root/pipeline/build_metro_df.py']);
    final pack = '${tmp.path}/brasilia.sqlite';
    await Process.run('python3', [
      '$root/pipeline/compile_gtfs.py',
      '$root/pipeline/tmp/metro_df_gtfs.zip',
      '-o', pack, '--city', 'brasilia',
    ]);
    final loader = PackLoader(pack);
    final hits = loader.search('aguas');
    expect(hits.map((h) => h.name), contains('Águas Claras'));
    // Display name keeps the original accents.
    expect(hits.firstWhere((h) => h.name == 'Águas Claras').kind, 'stop');
    loader.close();
    tmp.deleteSync(recursive: true);
  }, skip: python ? false : 'python3 not available');
}
