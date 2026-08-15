import 'package:conexao/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('city picker lists cities with honest badges',
      (tester) async {
    await tester.pumpWidget(const ConexaoApp());

    expect(find.text('Conexão'), findsOneWidget);
    expect(find.text('Brasília'), findsOneWidget);
    expect(find.text('Belo Horizonte'), findsOneWidget);
    expect(find.text('EM BREVE'), findsOneWidget); // BH: pack download flow pending
    expect(find.text('TABELADO'), findsOneWidget); // Brasília: Metrô-DF community feed
  });

  testWidgets('tapping a city opens its screen with four tabs',
      (tester) async {
    await tester.pumpWidget(const ConexaoApp());

    await tester.tap(find.text('Brasília'));
    // Not pumpAndSettle: the map/planner tabs depend on platform channels
    // (path_provider) that don't exist in tests, so loading indicators
    // would spin forever. Bounded pumps are enough to settle navigation
    // and flush the async pack lookups (which fail fast without plugins).
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }

    expect(find.text('Mapa'), findsOneWidget);
    expect(find.text('Paradas'), findsOneWidget);
    expect(find.text('Linhas'), findsOneWidget);
    expect(find.text('Planejar'), findsOneWidget);
  });
}
