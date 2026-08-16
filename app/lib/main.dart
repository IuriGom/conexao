import 'package:flutter/material.dart';

import 'map/map_screen.dart';
import 'map/offline_style.dart';
import 'location/location_service.dart';
import 'packs/pack_download.dart';
import 'packs/pack_manager.dart';
import 'planner/planner_screen.dart';
import 'stops/lines_screen.dart';
import 'stops/stops_screen.dart';

void main() => runApp(const ConexaoApp());

/// Conexão — app de transporte público offline, open source e sem Google.
///
/// This is the app shell (Phase 0/1). It shows the city catalog with honest
/// coverage badges. Real data arrives via signed city packs (see
/// docs/ARCHITECTURE.md); until the pack manager lands, the catalog below is
/// a static placeholder mirroring cities/*.yaml.
class ConexaoApp extends StatelessWidget {
  const ConexaoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Conexão',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00695C)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00695C),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const CityPickerScreen(),
    );
  }
}

enum Coverage { live, scheduled, planned }

class City {
  final String id;
  final String name;
  final String region;
  final Coverage coverage;
  final String note;
  final double centerLat, centerLon;

  const City({
    required this.id,
    required this.name,
    required this.region,
    required this.coverage,
    required this.note,
    required this.centerLat,
    required this.centerLon,
  });
}

// Placeholder catalog — mirrors cities/*.yaml until pack manager exists.
const cities = [
  City(
    id: 'brasilia',
    name: 'Brasília',
    region: 'Distrito Federal',
    coverage: Coverage.scheduled,
    note: 'Metrô-DF (feed comunitário, horários aproximados). '
        'Ônibus: GTFS oficial ainda não publicado (Lei 7.836/2025).',
    centerLat: -15.7942, centerLon: -47.8822,
  ),
  City(
    id: 'belo_horizonte',
    name: 'Belo Horizonte',
    region: 'Minas Gerais',
    coverage: Coverage.planned,
    note: 'Cidade de referência do pipeline. Dados abertos CC-BY, '
        'posições ao vivo a cada 20 s.',
    centerLat: -19.9167, centerLon: -43.9345,
  ),
];

extension on Coverage {
  String get label => switch (this) {
        Coverage.live => 'AO VIVO',
        Coverage.scheduled => 'TABELADO',
        Coverage.planned => 'EM BREVE',
      };

  Color color(ColorScheme cs) => switch (this) {
        Coverage.live => Colors.green.shade700,
        Coverage.scheduled => Colors.orange.shade800,
        Coverage.planned => cs.outline,
      };
}

class CityPickerScreen extends StatefulWidget {
  const CityPickerScreen({super.key});

  @override
  State<CityPickerScreen> createState() => _CityPickerScreenState();
}

class _CityPickerScreenState extends State<CityPickerScreen> {
  Set<String> _installed = {};
  PackCatalog? _catalog;
  String? _downloading; // city id currently downloading
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final installed = await PackManager().installedCities();
      if (mounted) setState(() => _installed = installed.toSet());
    } catch (_) {/* storage unreadable: show as not installed */}
    try {
      final catalog = await PackCatalog.fetch();
      if (mounted) setState(() => _catalog = catalog);
    } catch (_) {/* offline or unverifiable catalog: hide download buttons */}
  }

  Future<void> _download(City city) async {
    final entry = _catalog?.cities[city.id];
    if (entry == null || _downloading != null) return;
    setState(() {
      _downloading = city.id;
      _progress = 0;
    });
    try {
      await downloadCity(entry, (recv, total) {
        if (mounted && total > 0) {
          setState(() => _progress = recv / total);
        }
      });
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Download falhou — verifique a conexão e '
                'tente de novo. Nada foi instalado.')));
      }
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Conexão')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Funciona sem internet, sem Google, sem gastar seus dados.\n'
              'Escolha sua cidade:',
              style: TextStyle(fontSize: 15),
            ),
          ),
          for (final city in cities)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ListTile(
                title: Text(city.name),
                subtitle: Text('${city.region}\n${city.note}'),
                isThreeLine: true,
                trailing: _trailing(city, cs),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => CityScreen(city: city)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _trailing(City city, ColorScheme cs) {
    if (_downloading == city.id) {
      return SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: _progress),
            Text('${(_progress * 100).round()}%',
                style: const TextStyle(fontSize: 11)),
          ],
        ),
      );
    }
    if (!_installed.contains(city.id)) {
      final entry = _catalog?.cities[city.id];
      if (entry != null) {
        final mb = (entry.totalSize / 1048576).toStringAsFixed(0);
        return FilledButton.tonal(
          onPressed: () => _download(city),
          child: Text('Baixar\n$mb MB', textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11)),
        );
      }
    }
    return Chip(
      label: Text(
        city.coverage.label,
        style: const TextStyle(fontSize: 11, color: Colors.white),
      ),
      backgroundColor: city.coverage.color(cs),
      padding: EdgeInsets.zero,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Mapa tab: the offline PMTiles map when present, otherwise the
/// placeholder explaining what comes with the pack.
class CityMapTab extends StatelessWidget {
  final City city;
  final (double, double)? userPosition;
  const CityMapTab({super.key, required this.city, this.userPosition});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _style(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final style = snap.data;
        if (style == null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.map_outlined, size: 56, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('Mapa offline',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('Chega com o pacote de dados da cidade '
                      '(tiles PMTiles, renderizado com MapLibre).',
                      textAlign: TextAlign.center),
                ],
              ),
            ),
          );
        }
        return TransitMap(
          styleJson: style,
          centerLat: city.centerLat,
          centerLon: city.centerLon,
          userPosition: userPosition,
        );
      },
    );
  }

  Future<String?> _style() async {
    try {
      final pm = PackManager();
      final map = await pm.mapFile(city.id);
      if (map == null) return null;
      final glyphs = await pm.ensureGlyphs();
      return await OfflineStyle.build(
          pmtilesPath: map.path, glyphsDir: glyphs.path);
    } catch (_) {
      // No plugin (tests) or unreadable storage: same as no pack.
      return null;
    }
  }
}

class CityScreen extends StatefulWidget {
  final City city;
  const CityScreen({super.key, required this.city});

  @override
  State<CityScreen> createState() => _CityScreenState();
}

class _CityScreenState extends State<CityScreen> {
  (double, double)? _userPosition;
  bool _locating = false;

  Future<void> _locate() async {
    setState(() => _locating = true);
    final pos = await LocationService.current();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (pos != null) _userPosition = pos;
    });
    if (pos == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Sem sinal de localização (permissão negada ou '
              'GPS indisponível).')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final city = widget.city;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(city.name),
          actions: [
            IconButton(
              icon: _locating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
              tooltip: 'Minha localização',
              onPressed: _locating ? null : _locate,
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Mapa'),
              Tab(text: 'Paradas'),
              Tab(text: 'Linhas'),
              Tab(text: 'Planejar'),
            ],
          ),
        ),
        body: TabBarView(
          // Horizontal page-swipe fights the map's pan gesture; tabs still
          // switch by tapping the headers.
          physics: const NeverScrollableScrollPhysics(),
          children: [
            CityMapTab(city: city, userPosition: _userPosition),
            StopsScreen(
              cityId: city.id,
              refLat: _userPosition?.$1 ?? city.centerLat,
              refLon: _userPosition?.$2 ?? city.centerLon,
              refIsUser: _userPosition != null,
            ),
            LinesScreen(cityId: city.id),
            PlannerScreen(
              cityId: city.id,
              centerLat: city.centerLat,
              centerLon: city.centerLon,
            ),
          ],
        ),
      ),
    );
  }
}
