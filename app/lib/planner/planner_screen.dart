import 'package:flutter/material.dart';

import '../packs/pack_manager.dart';
import '../routing/models.dart';
import '../routing/pack_loader.dart';
import '../routing/router_worker.dart';
import 'journey_view.dart';

/// A->B trip planning, fully offline: stops come from the pack's FTS index,
/// the journey from the on-device CSA engine. No network call is made.
class PlannerScreen extends StatefulWidget {
  final String cityId;
  const PlannerScreen({super.key, required this.cityId});

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  PackLoader? _loader;
  RouterWorker? _worker;
  String? _packPath;
  bool _dayLoaded = false;
  bool _packMissing = false;
  bool _loadingDay = false;
  Journey? _journey;
  bool _searched = false;

  @override
  void initState() {
    super.initState();
    _openPack();
  }

  Future<void> _openPack() async {
    final f = await PackManager().packFile(widget.cityId);
    if (!mounted) return;
    if (f == null) {
      setState(() => _packMissing = true);
      return;
    }
    _packPath = f.path;
    _loader = PackLoader(f.path);
    _worker = await RouterWorker.spawn();
    if (mounted) setState(() {});
  }

  Future<void> _plan(StopNode origin, StopNode dest) async {
    if (!_dayLoaded) {
      setState(() => _loadingDay = true);
      // The worker isolate builds the day's timetable off the UI thread
      // and keeps it resident for subsequent queries.
      await _worker!.loadDay(_packPath!, DateTime.now());
      if (!mounted) return;
      setState(() {
        _dayLoaded = true;
        _loadingDay = false;
      });
    }
    final now = DateTime.now();
    final depSecs = now.hour * 3600 + now.minute * 60 + now.second;
    final journey = await _worker!.route(
      originLat: origin.lat, originLon: origin.lon,
      destLat: dest.lat, destLon: dest.lon,
      departureSecs: depSecs,
    );
    if (!mounted) return;
    setState(() {
      _journey = journey;
      _searched = true;
    });
  }

  @override
  void dispose() {
    _worker?.close();
    _loader?.close();
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
    if (_loader == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.55),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
            children: [
              _StopPicker(
                label: 'Origem',
                loader: _loader!,
                onSelected: (s) => _origin = s,
              ),
              const SizedBox(height: 8),
              _StopPicker(
                label: 'Destino',
                loader: _loader!,
                onSelected: (s) => _dest = s,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loadingDay
                      ? null
                      : () {
                          final o = _origin, d = _dest;
                          if (o != null && d != null) _plan(o, d);
                        },
                  icon: const Icon(Icons.route),
                  label: Text(_loadingDay
                      ? 'Carregando horários do dia…'
                      : 'Planejar'),
                ),
              ),
            ],
          ),
        ),
        ),
        if (_loadingDay) const LinearProgressIndicator(),
        Expanded(
          child: ListView(
            children: [
              if (_journey != null) JourneyView(journey: _journey!),
              if (_searched && _journey == null)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Nenhum itinerário encontrado.\n'
                    'Tente outro horário ou paradas mais próximas.',
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  StopNode? _origin;
  StopNode? _dest;
}

class _StopPicker extends StatefulWidget {
  final String label;
  final PackLoader loader;
  final ValueChanged<StopNode> onSelected;

  const _StopPicker({
    required this.label,
    required this.loader,
    required this.onSelected,
  });

  @override
  State<_StopPicker> createState() => _StopPickerState();
}

class _StopPickerState extends State<_StopPicker> {
  final _controller = TextEditingController();
  List<SearchHit> _hits = [];
  StopNode? _selected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _selected != null
                ? const Icon(Icons.check_circle, color: Colors.green)
                : null,
          ),
          onChanged: (q) {
            setState(() {
              _selected = null;
              _hits = q.trim().length >= 2
                  ? widget.loader
                      .search(q)
                      .where((h) => h.kind == 'stop')
                      .toList()
                  : [];
            });
          },
        ),
        for (final hit in _hits.take(5))
          ListTile(
            dense: true,
            title: Text(hit.name),
            onTap: () async {
              final stop = widget.loader.stopByI(hit.refI);
              if (stop == null) return;
              setState(() {
                _selected = stop;
                _hits = [];
                _controller.text = stop.name;
              });
              widget.onSelected(stop);
            },
          ),
      ],
    );
  }
}
