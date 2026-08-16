import 'package:flutter/material.dart';

import '../packs/pack_manager.dart';
import '../routing/models.dart';
import '../routing/pack_loader.dart';
import '../routing/timetable.dart' show haversineM;

/// Paradas tab: stops nearest the reference point with their next
/// departures today, straight from the pack. No network.
///
/// The reference point is the city center until the my-location layer
/// lands; the header says so honestly.
class StopsScreen extends StatefulWidget {
  final String cityId;
  final double refLat, refLon;

  /// True when the reference point is the device position (vs city center).
  final bool refIsUser;

  const StopsScreen({
    super.key,
    required this.cityId,
    required this.refLat,
    required this.refLon,
    this.refIsUser = false,
  });

  @override
  State<StopsScreen> createState() => _StopsScreenState();
}

class _StopRow {
  final StopNode stop;
  final int walkSecs;
  final List<StopDeparture> departures;
  const _StopRow(this.stop, this.walkSecs, this.departures);
}

class _StopsScreenState extends State<StopsScreen> {
  List<_StopRow>? _rows;
  bool _noPack = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(StopsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refLat != widget.refLat ||
        oldWidget.refLon != widget.refLon) {
      _load(); // reference point moved (e.g. my-location fix arrived)
    }
  }

  Future<void> _load() async {
    try {
      final f = await PackManager().packFile(widget.cityId);
      if (f == null) {
        if (mounted) setState(() => _noPack = true);
        return;
      }
      final loader = PackLoader(f.path);
      final now = DateTime.now();
      final nowSecs = now.hour * 3600 + now.minute * 60 + now.second;
      final stops = loader.allStops()
        ..sort((a, b) => haversineM(widget.refLat, widget.refLon, a.lat, a.lon)
            .compareTo(
                haversineM(widget.refLat, widget.refLon, b.lat, b.lon)));
      final rows = <_StopRow>[
        for (final s in stops.take(25))
          _StopRow(
            s,
            (haversineM(widget.refLat, widget.refLon, s.lat, s.lon) / 1.2)
                .ceil(),
            loader.nextDepartures(s.i, now, nowSecs, limit: 3),
          ),
      ];
      loader.close();
      if (mounted) setState(() => _rows = rows);
    } catch (_) {
      if (mounted) setState(() => _noPack = true);
    }
  }

  static String _fmt(int secs) =>
      '${(secs ~/ 3600).toString().padLeft(2, '0')}:'
      '${((secs % 3600) ~/ 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    if (_noPack) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Pacote de dados não encontrado.\n'
              'Instale o pacote da cidade para ver paradas e horários.',
              textAlign: TextAlign.center),
        ),
      );
    }
    final rows = _rows;
    if (rows == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(widget.refIsUser
              ? 'Perto de você. Horários de hoje:'
              : 'Perto do centro da cidade (toque ⊕ para usar sua '
                  'localização). Horários de hoje:'),
        ),
        for (final row in rows)
          ListTile(
            dense: true,
            leading: const Icon(Icons.place_outlined),
            title: Text(row.stop.name),
            subtitle: row.departures.isEmpty
                ? const Text('Sem mais partidas hoje')
                : Text(row.departures
                    .map((d) =>
                        '${d.isApproximate ? '~' : ''}${_fmt(d.depSecs)} '
                        '${d.routeShortName}')
                    .join('  ·  ')),
            trailing: Text('${row.walkSecs ~/ 60} min\na pé',
                textAlign: TextAlign.end,
                style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
  }
}
