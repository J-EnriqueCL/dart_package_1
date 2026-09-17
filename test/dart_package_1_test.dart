// test/dart_package_1_test.dart

import 'package:dart_package_1/dart_package_1.dart';
import 'package:test/test.dart';

void main() {
  group('Testear TipoVerde', () {
  final tipo = TipoVerde();

  test('Tiene el color verde correcto', () {
    expect(tipo.color, equals(Color.verde));
  });

  test('Permite cualquier número, aun si está repetido', () {
    expect(tipo.esPosibleAgregar([1, 1, 2], 1), isTrue);
    expect(tipo.esPosibleAgregar([1, 2, 3], 9), isTrue);
  });

  test('Calcula la puntuación verde', () {
    expect(tipo.calcularPuntuacion(1), equals(4));
    expect(tipo.calcularPuntuacion(2), equals(3));
    expect(tipo.calcularPuntuacion(3), equals(2));
    expect(tipo.calcularPuntuacion(4), equals(0));
  });
});

group('Testear TipoMorado', () {
  final tipo = TipoMorado();

  test('Tiene el color morado correcto', () {
    expect(tipo.color, equals(Color.morado));
  });

  test('Permite máximo dos números diferentes', () {
    expect(tipo.esPosibleAgregar([], 1), isTrue);
    expect(tipo.esPosibleAgregar([1, 1], 2), isTrue);
    expect(tipo.esPosibleAgregar([1, 2, 1], 2), isTrue);
  });

  test('No permite crear un tercer número distinto', () {
    expect(tipo.esPosibleAgregar([1, 2], 3), isFalse);
  });

  test('Calcula la puntuación morada', () {
    expect(tipo.calcularPuntuacion(1), equals(8));
    expect(tipo.calcularPuntuacion(2), equals(6));
    expect(tipo.calcularPuntuacion(3), equals(4));
    expect(tipo.calcularPuntuacion(4), equals(0));
  });
});

group('Testear TipoAmarillo', () {
  final tipo = TipoAmarillo();

  test('Tiene el color amarillo correcto', () {
    expect(tipo.color, equals(Color.amarillo));
  });

  test('Permite un número que no existe', () {
    expect(tipo.esPosibleAgregar([1, 2, 3], 4), isTrue);
  });

  test('No permite un número repetido', () {
    expect(tipo.esPosibleAgregar([1, 2, 3], 2), isFalse);
  });

  test('Calcula la puntuación amarilla', () {
    expect(tipo.calcularPuntuacion(1), equals(8));
    expect(tipo.calcularPuntuacion(2), equals(6));
    expect(tipo.calcularPuntuacion(3), equals(4));
  });
});

group('Testear TipoRojo', () {
  final tipo = TipoRojo();

  test('Tiene el color rojo correcto', () {
    expect(tipo.color, equals(Color.rojo));
  });

  test('Permite un número no repetido', () {
    expect(tipo.esPosibleAgregar([1, 2, 3], 4), isTrue);
  });

  test('No permite un número repetido', () {
    expect(tipo.esPosibleAgregar([1, 2, 3], 1), isFalse);
  });

  test('Calcula la puntuación roja', () {
    expect(tipo.calcularPuntuacion(1), equals(6));
    expect(tipo.calcularPuntuacion(2), equals(4));
    expect(tipo.calcularPuntuacion(3), equals(2));
  });
});

group('Testear TipoAzul', () {
  final tipo = TipoAzul();

  test('Tiene el color azul correcto', () {
    expect(tipo.color, equals(Color.azul));
  });

  test('Permite cualquier primer número', () {
    expect(tipo.esPosibleAgregar([], 5), isTrue);
  });

  test('Permite insertar un número igual al existente', () {
    expect(tipo.esPosibleAgregar([5, 5], 5), isTrue);
  });

  test('No permite insertar un número diferente', () {
    expect(tipo.esPosibleAgregar([5, 5], 3), isFalse);
  });

  test('Rechaza una lista previa con números mezclados', () {
    expect(tipo.esPosibleAgregar([5, 4], 5), isFalse);
  });

  test('Calcula la puntuación azul', () {
    expect(tipo.calcularPuntuacion(1), equals(7));
    expect(tipo.calcularPuntuacion(2), equals(5));
    expect(tipo.calcularPuntuacion(3), equals(3));
  });
});
}