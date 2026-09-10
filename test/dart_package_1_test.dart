// test/dart_package_1_test.dart

import 'package:dart_package_1/dart_package_1.dart';
import 'package:test/test.dart';

void main() {
  group('Testear grupos', () {
    test('No hay numeros en la lista', () {
      expect(ListaNumeros([], 5), isTrue);
    });

    test('El numero 5 no esta en la lista', () {
      expect(ListaNumeros([1, 2, 3, 4], 5), isTrue);
    });

    test('El numero 3 se repite', () {
      expect(ListaNumeros([1, 2, 3, 4], 3), isFalse);
    });

    test('No hay numero 5', () {
      expect(ListaNumeros([1, 2, 2, 3], 5), isFalse);
    });
  });

  group('Testear Bloque Verde (Cualquiera)', () {
    test('Lista vacia permite insertar cualquier numero', () {
      expect(BloqueVerde([], 5), isTrue);
    });

    test('Permite insertar un numero repetido', () {
      expect(BloqueVerde([3, 3, 2], 3), isTrue);
    });

    test('Permite insertar un numero diferente', () {
      expect(BloqueVerde([1, 2, 4], 6), isTrue);
    });
  });

  group('Testear Bloque Azul (Todos iguales)', () {
    test('Lista vacia permite cualquier primer numero', () {
      expect(BloqueAzul([], 5), isTrue);
    });

    test('Permite insertar el mismo numero que ya existe', () {
      expect(BloqueAzul([5, 5], 5), isTrue);
    });

    test('No permite insertar un numero diferente al grupo', () {
      expect(BloqueAzul([5, 5], 3), isFalse);
    });

    test('No permite si la lista previa ya contiene valores mezclados', () {
      expect(BloqueAzul([5, 4], 5), isFalse);
    });
  });

  group('Testear Bloque Rojo / Amarillo (Todos diferentes)', () {
    test('Permite insertar un numero que no esta en la lista', () {
      expect(BloqueRojo([1, 2, 3], 4), isTrue);
    });

    test('No permite insertar un numero que ya existe', () {
      expect(BloqueRojo([1, 2, 3], 2), isFalse);
    });
  });

  group('Testear obtenerValoresFoIn', () {
    test('Devuelve lista vacia cuando el tablero no tiene celdas', () {
      final tablero = <Celda>[];
      final resultado = obtenerValoresForIn(tablero, Region.verde);

      expect(resultado, isEmpty);
    });

    test('Extrae correctamente los valores de la region solicitada', () {
      final tablero = [
        Celda(valor: 4, region: Region.verde),
        Celda(valor: 6, region: Region.verde),
        Celda(valor: 2, region: Region.rojo),
      ];

      final resultado = obtenerValoresForIn(tablero, Region.verde);

      expect(resultado, equals([4, 6]));
    });

    test('Ignora las celdas vacias (valor null) de la region', () {
      final tablero = [
        Celda(valor: 4, region: Region.verde),
        Celda(valor: null, region: Region.verde),
        Celda(valor: 2, region: Region.verde),
      ];

      final resultado = obtenerValoresForIn(tablero, Region.verde);

      expect(resultado, equals([4, 2]));
    });

    test('Devuelve lista vacia si ninguna celda coincide con la region', () {
      final tablero = [
        Celda(valor: 5, region: Region.azul),
        Celda(valor: 1, region: Region.amarillo),
      ];

      final resultado = obtenerValoresForIn(tablero, Region.rojo);

      expect(resultado, isEmpty);
    });

    test('Filtra correctamente en un tablero con multiples colores y valores nulos', () {
      final tablero = [
        Celda(valor: 5, region: Region.azul),
        Celda(valor: 3, region: Region.morado),
        Celda(valor: null, region: Region.azul),
        Celda(valor: 5, region: Region.azul),
        Celda(valor: 1, region: Region.rojo),
      ];

      final resultado = obtenerValoresForIn(tablero, Region.azul);

      expect(resultado, equals([5, 5]));
    });
  });
}
