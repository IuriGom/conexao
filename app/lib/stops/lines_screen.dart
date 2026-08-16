import 'package:flutter/material.dart';

import '../packs/pack_manager.dart';
import '../routing/models.dart';
import '../routing/pack_loader.dart';

/// Linhas tab: every line in the city pack, with its full stop sequence
/// per direction. Offline, straight from SQLite.
class LinesScreen extends StatefulWidget {
  final String cityId;
  const LinesScreen({super.key, required this.cityId});

  @override
  State<LinesScreen> createState() => _LinesScreenState();
}

class _LinesScreenState extends State<LinesScreen> {
  List<RouteInfo>? _routes;
  bool _noPack = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final f = await PackManager().packFile(widget.cityId);
      if (f == null) {
        if (mounted) setState(() => _noPack = true);
        return;
      }
      final loader = PackLoader(f.path);
      final routes = loader.routes();
      loader.close();
      if (mounted) setState(() => _routes = routes);
    } catch (_) {
      if (mounted) setState(() => _noPack = true);
    }
  }

  static IconData _icon(int routeType) => switch (routeType) {
        0 => Icons.tram,
        1 => Icons.subway,
        2 => Icons.train,
        _ => Icons.directions_bus,
      };

  @override
  Widget build(BuildContext context) {
    if (_noPack) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Pacote de dados não encontrado.\n'
              'Instale o pacote da cidade para ver as linhas.',
              textAlign: TextAlign.center),
        ),
      );
    }
    final routes = _routes;
    if (routes == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      children: [
        for (final r in routes)
          ListTile(
            leading: Icon(_icon(r.routeType)),
            title: Text(r.shortName.isEmpty ? r.longName : r.shortName),
            subtitle:
                r.shortName.isEmpty ? null : Text(r.longName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RouteDetailScreen(
                  cityId: widget.cityId, route: r, icon: _icon(r.routeType)),
            )),
          ),
      ],
    );
  }
}

/// One line: both directions with their ordered stops.
class RouteDetailScreen extends StatefulWidget {
  final String cityId;
  final RouteInfo route;
  final IconData icon;

  const RouteDetailScreen({
    super.key,
    required this.cityId,
    required this.route,
    required this.icon,
  });

  @override
  State<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends State<RouteDetailScreen> {
  /// (direction label, stops) pairs, loaded once.
  List<(String, List<StopNode>)>? _directions;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final f = await PackManager().packFile(widget.cityId);
    if (f == null) return;
    final loader = PackLoader(f.path);
    final out = <(String, List<StopNode>)>[];
    for (final dir in loader.routeDirections(widget.route.routeI)) {
      final stops = loader.stopsForRoute(widget.route.routeI, dir);
      if (stops.isEmpty) continue;
      out.add(('Sentido ${stops.last.name}', stops));
    }
    loader.close();
    if (mounted) setState(() => _directions = out);
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.route;
    return Scaffold(
      appBar: AppBar(
        title: Text(r.shortName.isEmpty ? r.longName : r.shortName),
      ),
      body: _directions == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                for (final (label, stops) in _directions!) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text(label,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  for (var i = 0; i < stops.length; i++)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        i == 0 || i == stops.length - 1
                            ? Icons.radio_button_checked
                            : Icons.circle,
                        size: i == 0 || i == stops.length - 1 ? 16 : 8,
                      ),
                      title: Text(stops[i].name),
                    ),
                ],
              ],
            ),
    );
  }
}
