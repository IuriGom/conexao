import 'package:flutter/material.dart';

import '../routing/models.dart';

/// Renders a Journey as a vertical list of legs with mode icons,
/// times, and honest approximate labels.
class JourneyView extends StatelessWidget {
  final Journey journey;

  const JourneyView({super.key, required this.journey});

  static String fmt(int secs) {
    final h = (secs ~/ 3600) % 24;
    final m = (secs % 3600) ~/ 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  static IconData modeIcon(int routeType) => switch (routeType) {
        0 => Icons.tram,
        1 => Icons.subway,
        2 => Icons.train,
        4 => Icons.directions_boat,
        7 => Icons.directions_railway,
        _ => Icons.directions_bus,
      };

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${fmt(journey.departureSecs)} → ${fmt(journey.arrivalSecs)}'
              '  (${journey.durationSecs ~/ 60} min, '
              '${journey.transfers == 1 ? '1 baldeação' : '${journey.transfers} baldeações'})',
              style: tt.titleMedium,
            ),
            const Divider(),
            for (final leg in journey.legs) _LegTile(leg: leg),
          ],
        ),
      ),
    );
  }
}

class _LegTile extends StatelessWidget {
  final Leg leg;
  const _LegTile({required this.leg});

  @override
  Widget build(BuildContext context) {
    if (leg.isWalk) {
      return ListTile(
        dense: true,
        leading: const Icon(Icons.directions_walk),
        title: Text(leg.fromI == -1
            ? 'Caminhe até ${leg.toName}'
            : leg.toI == -1
                ? 'Caminhe até o destino'
                : 'Caminhe: ${leg.fromName} → ${leg.toName}'),
        subtitle: Text('${leg.durationSecs ~/ 60} min a pé'),
      );
    }
    final trip = leg.trip!;
    return ListTile(
      dense: true,
      leading: Icon(JourneyView.modeIcon(trip.routeType)),
      title: Text(
        '${trip.routeShortName}'
        '${trip.headsign != null ? ' → ${trip.headsign}' : ''}'
        '${leg.isApproximate ? ' (horário aproximado)' : ''}',
      ),
      subtitle: Text(
        '${leg.fromName} → ${leg.toName}\n'
        '${JourneyView.fmt(leg.startSecs)} → ${JourneyView.fmt(leg.endSecs)}'
        ' · ${leg.stopCount} paradas',
      ),
      isThreeLine: true,
    );
  }
}
