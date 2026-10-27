import 'package:dart_package_1/main.dart';
import 'package:dart_package_1/pantalla_numeros_iniciales.dart';
import 'package:dart_package_1/pantalla_partida.dart';
import 'package:dart_package_1/pantalla_seleccion_mapa.dart';
import 'package:dart_package_1/widgets/celda_gema.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ayudas_pruebas.dart';

bool _inicioHabilitado(WidgetTester tester) {
  final boton = tester.widget<FilledButton>(
    find.byKey(const Key('boton_inicio')),
  );
  return boton.onPressed != null;
}

CeldaGema _celda(WidgetTester tester, int indice) {
  return tester.widget<CeldaGema>(find.byKey(Key('celda_$indice')));
}

Finder _textoEnDado(int posicion, String texto) {
  return find.descendant(
    of: find.byKey(Key('dado_$posicion')),
    matching: find.text(texto),
  );
}

void main() {
  setUpAll(cargarFuentes);

  group('Pantalla de números iniciales', () {
    testWidgets(
      'muestra el tablero, las seis estrellas e Inicio deshabilitado',
      (tester) async {
        await fijarPantalla(tester);
        await tester.pumpWidget(const AplicacionBrilliant());
        await tester.pumpAndSettle();

        expect(find.byType(PantallaSeleccionMapa), findsOneWidget);
        await tocar(tester, find.byKey(const Key('mapa_0')));

        expect(find.byType(PantallaNumerosIniciales), findsOneWidget);
        expect(find.text('BRILLIANT'), findsOneWidget);
        expect(find.byType(CeldaGema), findsNWidgets(49));
        expect(find.byIcon(Icons.star_rounded), findsNWidgets(6));
        for (var k = 0; k < 6; k++) {
          expect(find.byKey(Key('inicial_$k')), findsOneWidget);
        }
        expect(_inicioHabilitado(tester), isFalse);
      },
    );

    testWidgets('no permite repetir un número ya usado', (tester) async {
      await montarInicial(tester);

      await tocar(tester, find.byKey(const Key('inicial_0')));
      await tocar(tester, find.byKey(const Key('numero_3')));

      // La siguiente casilla queda seleccionada, así que el 3 ya no es elegible.
      final boton = tester.widget<FilledButton>(
        find.byKey(const Key('numero_3')),
      );
      expect(boton.onPressed, isNull);
    });

    testWidgets('Inicio se habilita solo al colocar los seis valores', (
      tester,
    ) async {
      await montarInicial(tester);

      for (var k = 0; k < 5; k++) {
        await tocar(tester, find.byKey(Key('inicial_$k')));
        await tocar(tester, find.byKey(Key('numero_${k + 1}')));
        expect(_inicioHabilitado(tester), isFalse);
      }

      await tocar(tester, find.byKey(const Key('inicial_5')));
      await tocar(tester, find.byKey(const Key('numero_6')));

      expect(_inicioHabilitado(tester), isTrue);
      expect(find.text('Todo listo. Presiona Inicio.'), findsOneWidget);
    });
  });

  group('Camino feliz completo', () {
    testWidgets('de números iniciales a colocar un número en la partida', (
      tester,
    ) async {
      // Dados fijos: [1, 2].
      await montarInicial(tester, azar: AzarFijo([0, 1]));
      await completarIniciales(tester);

      await tocar(tester, find.byKey(const Key('boton_inicio')));
      expect(find.byType(PantallaPartida), findsOneWidget);
      expect(find.text('Tirar dados'), findsOneWidget);
      expect(find.text('0 pts'), findsOneWidget);
      expect(find.text('Turno 1'), findsOneWidget);

      await tocar(tester, find.byKey(const Key('boton_tirar_dados')));
      expect(_textoEnDado(0, '1'), findsOneWidget);
      expect(_textoEnDado(1, '2'), findsOneWidget);
      expect(_textoEnDado(0, 'ELEGIR'), findsOneWidget);
      expect(_textoEnDado(1, 'ELEGIR'), findsOneWidget);

      // Se elige el dado 1 como ancla; el 2 es el valor a colocar.
      await tocar(tester, find.byKey(const Key('dado_0')));
      expect(_textoEnDado(0, 'ANCLA'), findsOneWidget);
      expect(_textoEnDado(1, 'A COLOCAR'), findsOneWidget);

      // La casilla 2 contiene el 1; sus vecinos válidos para el 2 son 1 y 3.
      // La 9 es azul y ya contiene un 1, por eso no es destino.
      expect(_celda(tester, 1).esDestino, isTrue);
      expect(_celda(tester, 3).esDestino, isTrue);
      expect(_celda(tester, 9).esDestino, isFalse);
      expect(_celda(tester, 2).esAncla, isTrue);

      await tocar(tester, find.byKey(const Key('celda_1')));

      expect(_celda(tester, 1).valor, 2);
      expect(find.text('Turno 2'), findsOneWidget);
      expect(find.text('Colocaste el 2. Tira los dados.'), findsOneWidget);
      expect(find.text('0 pts'), findsOneWidget);
      expect(_celda(tester, 3).esDestino, isFalse);

      // Una casilla ocupada no se puede sobrescribir.
      await tocar(tester, find.byKey(const Key('celda_1')));
      expect(_celda(tester, 1).valor, 2);
      expect(find.text('Turno 2'), findsOneWidget);
    });
  });

  group('Pantalla de partida', () {
    testWidgets('estado inicial: dados sin tirar y puntuación en cero', (
      tester,
    ) async {
      await montarPartida(tester);

      expect(find.text('Tira los dados para comenzar.'), findsOneWidget);
      expect(find.text('0 pts'), findsOneWidget);
      expect(_textoEnDado(0, '?'), findsOneWidget);
      expect(_textoEnDado(1, '?'), findsOneWidget);
      expect(find.text('Tirar dados'), findsOneWidget);
    });

    testWidgets('quitar el ancla vuelve a apagar los destinos', (tester) async {
      await montarPartida(tester, azar: AzarFijo([0, 1]));

      await tocar(tester, find.byKey(const Key('boton_tirar_dados')));
      await tocar(tester, find.byKey(const Key('dado_0')));
      expect(_celda(tester, 1).esDestino, isTrue);

      await tocar(tester, find.byKey(const Key('dado_0')));
      expect(_celda(tester, 1).esDestino, isFalse);
      expect(_textoEnDado(0, 'ELEGIR'), findsOneWidget);
    });

    testWidgets('pasar turno descarta los dados y avanza el turno', (
      tester,
    ) async {
      await montarPartida(tester, azar: AzarFijo([0, 1]));

      await tocar(tester, find.byKey(const Key('boton_tirar_dados')));
      await tocar(tester, find.text('Pasar turno'));

      expect(find.text('Turno 2'), findsOneWidget);
      expect(find.text('Turno pasado. Tira los dados.'), findsOneWidget);
      expect(_textoEnDado(0, '?'), findsOneWidget);
    });

    testWidgets('completar un área azul recalcula la puntuación (+7)', (
      tester,
    ) async {
      // Tres tiradas [1, 1]. El área azul {2, 9, 10, 17} exige todos iguales
      // y la casilla 2 ya tiene un 1; se llenan 9, 10 y 17 con 1.
      await montarPartida(tester, azar: AzarFijo([0, 0, 0, 0, 0, 0]));

      for (final indice in [9, 10, 17]) {
        expect(find.text('0 pts'), findsOneWidget);
        await tocar(tester, find.byKey(const Key('boton_tirar_dados')));
        await tocar(tester, find.byKey(const Key('dado_0')));
        expect(_celda(tester, indice).esDestino, isTrue);
        await tocar(tester, find.byKey(Key('celda_$indice')));
        expect(_celda(tester, indice).valor, 1);
      }

      expect(find.text('7 pts'), findsOneWidget);
      expect(find.text('0 pts'), findsNothing);
      expect(find.textContaining('Área completada! +7 puntos'), findsOneWidget);
      expect(_celda(tester, 17).completada, isTrue);
      expect(find.text('Turno 4'), findsOneWidget);
    });
  });
}
