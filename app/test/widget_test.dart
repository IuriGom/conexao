import 'package:conexao/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('city picker lists cities with honest badges',
      (tester) async {
    await tester.pumpWidget(const ConexaoApp());

    expect(find.text('Conexão'), findsOneWidget);
    expect(find.text('Brasília'), findsOneWidget);
    expect(find.text('Belo Horizonte'), findsOneWidget);
    expect(find.text('EM BREVE'), findsNWidgets(2));
  });

  testWidgets('tapping a city opens its screen with four tabs',
      (tester) async {
    await tester.pumpWidget(const ConexaoApp());

    await tester.tap(find.text('Brasília'));
    await tester.pumpAndSettle();

    expect(find.text('Mapa'), findsOneWidget);
    expect(find.text('Paradas'), findsOneWidget);
    expect(find.text('Linhas'), findsOneWidget);
    expect(find.text('Planejar'), findsOneWidget);
    expect(find.byIcon(Icons.map_outlined), findsOneWidget);
  });
}
