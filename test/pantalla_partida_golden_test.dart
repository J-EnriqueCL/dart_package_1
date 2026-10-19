import 'package:dart_package_1/pantalla_partida.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ayudas_pruebas.dart';

void main() {
  setUpAll(cargarFuentes);

  testWidgets('golden: pantalla de partida inicial', (tester) async {
    await montarPartida(tester);

    await expectLater(
      find.byType(PantallaPartida),
      matchesGoldenFile('goldens/pantalla_partida_inicial.png'),
    );
  });

  testWidgets('golden: partida con ancla seleccionada', (tester) async {
    // Dados fijos [1, 2].
    await montarPartida(tester, azar: AzarFijo([0, 1]));
    await tocar(tester, find.byKey(const Key('boton_tirar_dados')));
    await tocar(tester, find.byKey(const Key('dado_0')));

    await expectLater(
      find.byType(PantallaPartida),
      matchesGoldenFile('goldens/pantalla_partida_ancla_seleccionada.png'),
    );
  });
}
