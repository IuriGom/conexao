import 'dart:async';
import 'dart:isolate';

import 'csa.dart';
import 'models.dart';
import 'pack_loader.dart';
import 'timetable.dart';

/// Persistent background isolate that owns the pack database and the day's
/// Timetable, and answers routing queries.
///
/// Why: loading a big-city timetable takes tens of seconds and builds
/// millions of Connection objects — far too heavy to block the UI thread
/// (ANR) or to copy across an isolate boundary per query. With a worker,
/// only small request/response messages cross: the Timetable and the native
/// SQLite handle stay inside the worker for the app's lifetime.
class RouterWorker {
  final SendPort _toWorker;
  final _pending = <int, Completer<Object?>>{};
  var _nextId = 0;

  RouterWorker._(this._toWorker, ReceivePort responses) {
    responses.listen((msg) {
      final m = msg as List;
      _pending.remove(m[0] as int)?.complete(m[1]);
    });
  }

  static Future<RouterWorker> spawn() async {
    final handshake = ReceivePort();
    await Isolate.spawn(_entry, handshake.sendPort);
    final toWorker = await handshake.first as SendPort;
    handshake.close();
    final responses = ReceivePort();
    toWorker.send(responses.sendPort);
    return RouterWorker._(toWorker, responses);
  }

  Future<void> loadDay(String packPath, DateTime day) =>
      _request(['load', packPath, day.millisecondsSinceEpoch]).then((_) {});

  Future<Journey?> route({
    required double originLat,
    required double originLon,
    required double destLat,
    required double destLon,
    required int departureSecs,
  }) async {
    final r = await _request(
        ['route', originLat, originLon, destLat, destLon, departureSecs]);
    return r as Journey?;
  }

  Future<void> close() => _request(['close']).then((_) {});

  Future<Object?> _request(List<Object?> payload) {
    final id = _nextId++;
    final c = Completer<Object?>();
    _pending[id] = c;
    _toWorker.send([id, payload]);
    return c.future;
  }

  static void _entry(SendPort handshake) {
    final inbox = ReceivePort();
    handshake.send(inbox.sendPort);

    SendPort? out;
    PackLoader? loader;
    Timetable? tt;

    inbox.listen((msg) {
      if (msg is SendPort) {
        out = msg;
        return;
      }
      final m = msg as List;
      final id = m[0] as int;
      final p = m[1] as List;
      Object? result;
      switch (p[0] as String) {
        case 'load':
          loader?.close();
          loader = PackLoader(p[1] as String);
          tt = loader!.loadForDay(
              DateTime.fromMillisecondsSinceEpoch(p[2] as int));
          result = true;
        case 'route':
          result = tt == null
              ? null
              : CsaRouter(tt!).route(
                  originLat: p[1] as double, originLon: p[2] as double,
                  destLat: p[3] as double, destLon: p[4] as double,
                  departureSecs: p[5] as int);
        case 'close':
          loader?.close();
          loader = null;
          tt = null;
          result = true;
      }
      out?.send([id, result]);
    });
  }
}
