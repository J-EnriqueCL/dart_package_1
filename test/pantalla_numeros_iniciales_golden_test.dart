import 'package:dart_package_1/pantalla_numeros_iniciales.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ayudas_pruebas.dart';

void main() {
  setUpAll(cargarFuentes);

  testWidgets('golden: pantalla inicial vacía', (tester) async {
    await montarInicial(tester);

    await expectLater(
      find.byType(PantallaNumerosIniciales),
      matchesGoldenFile('goldens/pantalla_inicial_vacia.png'),
    );
  });

  testWidgets('golden: pantalla inicial completa', (tester) async {
    await montarInicial(tester);
    await completarIniciales(tester);

    await expectLater(
      find.byType(PantallaNumerosIniciales),
      matchesGoldenFile('goldens/pantalla_inicial_completa.png'),
    );
  });
}
