import 'package:dart_package_1/dart_package_1.dart';
import 'package:dart_package_1/pantalla_numeros_iniciales.dart';
import 'package:dart_package_1/pantalla_partida.dart';
import 'package:dart_package_1/pantalla_seleccion_mapa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ayudas_pruebas.dart';

void main() {
  setUpAll(cargarFuentes);

  group('Mapas oficiales', () {
    test('son cuatro, de 7x7 y con seis casillas iniciales distintas', () {
      expect(mapasOficiales, hasLength(4));

      for (final mapa in mapasOficiales) {
        expect(mapa.plano, hasLength(7), reason: mapa.nombre);
        for (final fila in mapa.plano) {
          expect(fila, hasLength(7), reason: mapa.nombre);
        }
        expect(mapa.indicesIniciales.toSet(), hasLength(6));
        expect(mapa.crearTablero().where((c) => c.esInicial), hasLength(6));
      }
    });

    test('todos se pueden inicializar y calculan sus áreas', () {
      for (final mapa in mapasOficiales) {
        final celdas = mapa.crearTablero();
        var siguiente = 1;
        for (final indice in mapa.indicesIniciales) {
          celdas[indice] = celdas[indice].copiarCon(valor: siguiente++);
        }

        final controlador = ControladorPartida(
          gruposConectados: mapa.gruposConectados,
        )..establecerValoresIniciales(celdas);

        final cubiertas = controlador.areas.expand((a) => a.indices).toList();
        expect(cubiertas, hasLength(49), reason: mapa.nombre);
        expect(cubiertas.toSet(), hasLength(49), reason: mapa.nombre);
      }
    });
  });

  group('Selección de mapa', () {
    for (var i = 0; i < mapasOficiales.length; i++) {
      testWidgets(
        '${mapasOficiales[i].nombre}: se elige y se llega a la partida',
        (tester) async {
          await fijarPantalla(tester);
          await tester.pumpWidget(
            const MaterialApp(home: PantallaSeleccionMapa()),
          );
          await tester.pumpAndSettle();

          await tocar(tester, find.byKey(Key('mapa_$i')));
          expect(find.byType(PantallaNumerosIniciales), findsOneWidget);
          expect(find.text(mapasOficiales[i].nombre), findsOneWidget);

          await completarIniciales(tester);
          await tocar(tester, find.byKey(const Key('boton_inicio')));
          expect(find.byType(PantallaPartida), findsOneWidget);
        },
      );
    }
  });
}
