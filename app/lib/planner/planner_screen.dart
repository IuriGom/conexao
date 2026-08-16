import 'package:flutter/material.dart';

import '../map/map_screen.dart';
import '../map/offline_style.dart';
import '../packs/pack_manager.dart';
import '../routing/models.dart';
import '../routing/pack_loader.dart';
import '../routing/router_worker.dart';
import 'journey_view.dart';

/// Map-first trip planning (Google-Maps style): tap the map to drop the
/// origin pin, tap again for the destination, then Planejar. Everything is
/// offline — tiles from the local PMTiles pack, routing on-device via CSA.
class PlannerScreen extends StatefulWidget {
  final String cityId;
  final double centerLat, centerLon;

  const PlannerScreen({
    super.key,
    required this.cityId,
    required this.centerLat,
    required this.centerLon,
  });

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  String? _styleJson;
  String? _packPath;
  RouterWorker? _worker;
  PackLoader? _searchLoader; // main-isolate loader for FTS stop search
  bool _dayLoaded = false;
  bool _packMissing = false;
  bool _mapMissing = false;
  bool _busy = false;

  MapPin? _origin, _dest;
  Journey? _journey;
  bool _noResult = false;

  final _originCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  bool _searchingOrigin = true; // which field the suggestions belong to
  List<SearchHit> _hits = const [];
  (double, double)? _focusPoint;

  @override
  void initState() {
    super.initState();
    _openPack();
  }

  Future<void> _openPack() async {
    try {
      final pm = PackManager();
      final transit = await pm.packFile(widget.cityId);
      final map = await pm.mapFile(widget.cityId);
      if (!mounted) return;
      if (transit == null) {
        setState(() => _packMissing = true);
        return;
      }
      _packPath = transit.path;
      _searchLoader = PackLoader(transit.path);
      _worker = await RouterWorker.spawn();
      if (map == null) {
        setState(() => _mapMissing = true);
        return;
      }
      final glyphs = await pm.ensureGlyphs();
      final style =
          await OfflineStyle.build(pmtilesPath: map.path, glyphsDir: glyphs.path);
      if (mounted) setState(() => _styleJson = style);
    } catch (_) {
      // No plugin (tests) or unreadable storage: same as no pack.
      if (mounted) setState(() => _packMissing = true);
    }
  }

  void _onTapMap(double lat, double lon) {
    setState(() {
      _journey = null;
      _hits = const [];
      if (_origin == null) {
        _origin = MapPin(lat, lon, '#2E7D32'); // green
        _originCtrl.text = 'Ponto no mapa';
      } else {
        _dest = MapPin(lat, lon, '#C62828'); // red
        _destCtrl.text = 'Ponto no mapa';
      }
    });
  }

  void _search(String query, bool origin) {
    final loader = _searchLoader;
    if (loader == null || query.trim().length < 2) {
      setState(() => _hits = const []);
      return;
    }
    List<SearchHit> hits;
    try {
      hits = loader
          .search(query, limit: 6)
          .where((h) => h.kind == 'stop')
          .toList();
    } catch (_) {
      hits = const []; // old pack without the norm column: no suggestions
    }
    setState(() {
      _searchingOrigin = origin;
      _hits = hits;
    });
  }

  void _pick(SearchHit hit) {
    final stop = _searchLoader?.stopByI(hit.refI);
    if (stop == null) return;
    setState(() {
      _journey = null;
      _hits = const [];
      _focusPoint = (stop.lat, stop.lon);
      if (_searchingOrigin) {
        _origin = MapPin(stop.lat, stop.lon, '#2E7D32');
        _originCtrl.text = stop.name;
      } else {
        _dest = MapPin(stop.lat, stop.lon, '#C62828');
        _destCtrl.text = stop.name;
      }
    });
    FocusScope.of(context).unfocus();
  }

  Widget _searchField(
      TextEditingController ctrl, String hint, bool origin) {
    return TextField(
      controller: ctrl,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        prefixIcon: Icon(Icons.circle,
            size: 10, color: origin ? Colors.green : Colors.red),
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      onTap: () => setState(() {
        _searchingOrigin = origin;
        _hits = const [];
      }),
      onChanged: (v) => _search(v, origin),
    );
  }

  Future<void> _plan() async {
    final o = _origin, d = _dest;
    if (o == null || d == null) return;
    setState(() {
      _busy = true;
      _journey = null;
    });
    if (!_dayLoaded) {
      await _worker!.loadDay(_packPath!, DateTime.now());
      if (!mounted) return;
      _dayLoaded = true;
    }
    final now = DateTime.now();
    final journey = await _worker!.route(
      originLat: o.lat, originLon: o.lon,
      destLat: d.lat, destLon: d.lon,
      departureSecs: now.hour * 3600 + now.minute * 60 + now.second,
      // Brazilian cities are spread out — Brasília's metro stations are
      // 1-2 km apart. 900 m is too tight for map taps at city zoom.
      maxWalkMeters: 1500,
    );
    if (!mounted) return;
    setState(() {
      _journey = journey;
      _busy = false;
      _noResult = journey == null;
    });
  }

  void _clear() => setState(() {        _origin = null;
        _dest = null;
        _journey = null;
        _noResult = false;
        _hits = const [];
        _originCtrl.clear();
        _destCtrl.clear();
      });

  @override
  void dispose() {
    _worker?.close();
    _searchLoader?.close();
    _originCtrl.dispose();
    _destCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_packMissing) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Pacote de dados não encontrado.\n'
            'O download de pacotes chega na Fase 1 — por enquanto, instale '
            'manualmente em packs/<cidade>.sqlite.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_mapMissing) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Mapa offline não encontrado (packs/<cidade>.pmtiles).',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_styleJson == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final pins = [?_origin, ?_dest];
    return Stack(
      children: [
        TransitMap(
          styleJson: _styleJson!,
          centerLat: widget.centerLat,
          centerLon: widget.centerLon,
          pins: pins,
          onTap: _onTapMap,
          focusPoint: _focusPoint,
        ),
        // Search + status + actions
        Positioned(
          top: 8, left: 8, right: 8,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _searchField(_originCtrl, 'Origem', true),
                  const SizedBox(height: 4),
                  _searchField(_destCtrl, 'Destino', false),
                  if (_hits.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final h in _hits)
                            ListTile(
                              dense: true,
                              leading: const Icon(Icons.place_outlined,
                                  size: 18),
                              title: Text(h.name,
                                  style: const TextStyle(fontSize: 13)),
                              onTap: () => _pick(h),
                            ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _origin == null
                              ? 'Busque ou toque no mapa: origem'
                              : _dest == null
                                  ? 'Agora o destino'
                                  : 'Origem e destino marcados',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      TextButton(
                          onPressed: _clear, child: const Text('Limpar')),
                      FilledButton(
                        onPressed:
                            (_origin != null && _dest != null && !_busy)
                                ? _plan
                                : null,
                        child: Text(_busy ? '…' : 'Planejar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_busy)
          const Positioned(
            top: 170, left: 8, right: 8,
            child: LinearProgressIndicator(),
          ),
        // Result
        if (_journey != null)
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45),
              child: SingleChildScrollView(
                child: JourneyView(journey: _journey!),
              ),
            ),
          ),
        if (_noResult)
          const Positioned(
            left: 0, right: 0, bottom: 24,
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nenhum itinerário encontrado. '
                    'Tente pontos mais próximos da malha.'),
              ),
            ),
          ),
      ],
    );
  }
}
