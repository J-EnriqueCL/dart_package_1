import 'dart:io';
import 'dart:math';

import 'package:dart_package_1/dart_package_1.dart';
import 'package:dart_package_1/pantalla_partida.dart';
import 'package:dart_package_1/pantalla_numeros_iniciales.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Índices del tablero (nivel uno) de las seis casillas iniciales, en orden.
const indicesIniciales = <int>[2, 12, 22, 25, 37, 46];

/// Fuente de azar determinista: cada `nextInt` devuelve el siguiente valor
/// de [valores] (0..5, que equivale a un dado de 1..6).
class AzarFijo implements Random {
  AzarFijo(this.valores);

  final List<int> valores;
  int _posicion = 0;

  @override
  int nextInt(int max) => valores[_posicion++];

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

/// Controlador con los números 1..6 en las casillas iniciales, en orden.
ControladorPartida controladorListo() {
  final celdas = crearTableroNivelUno();
  var siguiente = 1;
  for (final indice in indicesIniciales) {
    celdas[indice] = celdas[indice].copiarCon(valor: siguiente++);
  }
  return ControladorPartida()..establecerValoresIniciales(celdas);
}

bool _fuentesCargadas = false;

/// Carga fuentes reales (copiadas del SDK de Flutter a `test/fonts/`).
///
/// La fuente por defecto de flutter_test (Ahem) dibuja cada letra como un
/// cuadrado, lo que desborda la interfaz y haría los goldens ilegibles y
/// distintos entre equipos. Con estas fuentes el render es idéntico en
/// cualquier máquina.
Future<void> cargarFuentes() async {
  if (_fuentesCargadas) {
    return;
  }

  Future<void> cargar(String familia, List<String> archivos) async {
    final cargador = FontLoader(familia);
    for (final archivo in archivos) {
      cargador.addFont(
        File('test/fonts/$archivo')
            .readAsBytes()
            .then((bytes) => ByteData.view(Uint8List.fromList(bytes).buffer)),
      );
    }
    await cargador.load();
  }

  await cargar('Roboto', [
    'roboto-regular.ttf',
    'roboto-bold.ttf',
    'roboto-black.ttf',
  ]);
  await cargar('MaterialIcons', ['materialicons-regular.otf']);
  _fuentesCargadas = true;
}

Future<void> fijarPantalla(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> montarInicial(WidgetTester tester, {Random? azar}) async {
  await fijarPantalla(tester);
  await tester.pumpWidget(
    MaterialApp(home: PantallaNumerosIniciales(azar: azar)),
  );
  await tester.pumpAndSettle();
}

Future<void> montarPartida(WidgetTester tester, {Random? azar}) async {
  await fijarPantalla(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: PantallaPartida(controlador: controladorListo(), azar: azar),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tocar(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Coloca 1..6 en las seis casillas iniciales.
Future<void> completarIniciales(WidgetTester tester) async {
  for (var k = 0; k < 6; k++) {
    await tocar(tester, find.byKey(Key('inicial_$k')));
    await tocar(tester, find.byKey(Key('numero_${k + 1}')));
  }
}
