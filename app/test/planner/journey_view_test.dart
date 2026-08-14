import 'package:conexao/planner/journey_view.dart';
import 'package:conexao/routing/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final journey = Journey([
    const Leg.walk(
      fromI: -1, toI: 1,
      fromName: 'Origem', toName: 'Terminal Centro',
      startSecs: 7 * 3600, endSecs: 7 * 3600 + 240,
    ),
    const Leg.ride(
      fromI: 1, toI: 4,
      fromName: 'Terminal Centro', toName: 'Praça da Estação',
      startSecs: 8 * 3600, endSecs: 8 * 3600 + 600,
      trip: TripInfo(tripI: 101, routeShortName: '100', serviceI: 1,
          headsign: 'Praça'),
      stopCount: 3,
    ),
    const Leg.walk(
      fromI: 4, toI: 5,
      fromName: 'Praça da Estação', toName: 'Metrô Centro',
      startSecs: 8 * 3600 + 600, endSecs: 8 * 3600 + 660,
    ),
    const Leg.ride(
      fromI: 5, toI: 6,
      fromName: 'Metrô Centro', toName: 'Metrô Norte',
      startSecs: 8 * 3600 + 900, endSecs: 8 * 3600 + 1500,
      trip: TripInfo(tripI: 201, routeShortName: 'L1', serviceI: 1,
          routeType: 1, freqExact: 0),
      stopCount: 1,
    ),
  ]);

  testWidgets('renders times, modes, transfer count, approximate label',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: JourneyView(journey: journey))));

    expect(find.textContaining('07:00 → 08:25'), findsOneWidget);
    expect(find.textContaining('1 baldeação'), findsOneWidget);
    expect(find.textContaining('100 → Praça'), findsOneWidget);
    expect(find.textContaining('L1'), findsWidgets);
    expect(find.textContaining('horário aproximado'), findsOneWidget);
    expect(find.byIcon(Icons.directions_bus), findsOneWidget);
    expect(find.byIcon(Icons.subway), findsOneWidget);
    expect(find.byIcon(Icons.directions_walk), findsNWidgets(2));
  });
}
