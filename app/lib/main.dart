import 'package:flutter/material.dart';

import 'map/map_screen.dart';
import 'map/offline_style.dart';
import 'packs/pack_manager.dart';
import 'planner/planner_screen.dart';

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

class CityPickerScreen extends StatelessWidget {
  const CityPickerScreen({super.key});

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
                trailing: Chip(
                  label: Text(
                    city.coverage.label,
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                  backgroundColor: city.coverage.color(cs),
                  padding: EdgeInsets.zero,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => CityScreen(city: city)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Mapa tab: the offline PMTiles map when present, otherwise the
/// placeholder explaining what comes with the pack.
class CityMapTab extends StatelessWidget {
  final City city;
  const CityMapTab({super.key, required this.city});

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

class CityScreen extends StatelessWidget {
  final City city;
  const CityScreen({super.key, required this.city});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(city.name),
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
          children: [
            CityMapTab(city: city),
            _placeholder(
              Icons.place_outlined,
              'Paradas próximas',
              'Partidas tabeladas por parada, direto do pacote SQLite. '
                  'Sem internet necessária.',
            ),
            _placeholder(
              Icons.directions_bus_outlined,
              'Linhas e horários',
              'Ônibus, BRT, metrô, trem e VLT — itinerários completos '
                  'e tabelas de horário offline.',
            ),
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

  Widget _placeholder(IconData icon, String title, String body) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: Colors.grey),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
