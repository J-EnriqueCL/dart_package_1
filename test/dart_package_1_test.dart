import 'package:dart_package_1/dart_package_1.dart';
import 'package:test/test.dart';

void main() {
  group('TipoVerde', () {
    final tipo = TipoVerde();

    test('Tiene el color verde correcto', () {
      expect(tipo.color, equals(Color.verde));
    });

    test('Permite números repetidos', () {
      expect(tipo.esPosibleAgregar([1, 1, 2], 1), isTrue);
    });

    test('Calcula la puntuación verde', () {
      expect(tipo.calcularPuntuacion(1), equals(4));
      expect(tipo.calcularPuntuacion(2), equals(3));
      expect(tipo.calcularPuntuacion(3), equals(2));
      expect(tipo.calcularPuntuacion(4), equals(0));
    });
  });

  group('TipoMorado', () {
    final tipo = TipoMorado();

    test('Tiene el color morado correcto', () {
      expect(tipo.color, equals(Color.morado));
    });

    test('Permite hasta dos números diferentes', () {
      expect(tipo.esPosibleAgregar([1, 1], 2), isTrue);
      expect(tipo.esPosibleAgregar([1, 2], 3), isFalse);
    });
  });

  group('TipoAmarillo', () {
    final tipo = TipoAmarillo();

    test('No permite números repetidos', () {
      expect(tipo.esPosibleAgregar([1, 2, 3], 4), isTrue);
      expect(tipo.esPosibleAgregar([1, 2, 3], 2), isFalse);
    });
  });

  group('TipoRojo', () {
    final tipo = TipoRojo();

    test('No permite números repetidos', () {
      expect(tipo.esPosibleAgregar([1, 2, 3], 4), isTrue);
      expect(tipo.esPosibleAgregar([1, 2, 3], 1), isFalse);
    });
  });

  group('TipoAzul', () {
    final tipo = TipoAzul();

    test('Solo permite números iguales', () {
      expect(tipo.esPosibleAgregar([], 5), isTrue);
      expect(tipo.esPosibleAgregar([5, 5], 5), isTrue);
      expect(tipo.esPosibleAgregar([5, 5], 3), isFalse);
    });
  });

  group('ControladorPartida', () {
    late ControladorPartida controlador;

    setUp(() {
      controlador = ControladorPartida();
    });

    test('Inicia bloqueado sin valores iniciales', () {
      expect(controlador.tieneValoresIniciales, isFalse);
    });

    test('No permite leer la matriz sin valores iniciales', () {
      expect(
        () => controlador.matriz,
        throwsA(isA<ValoresInicialesNoProporcionadosException>()),
      );
    });

    test('No acepta una matriz vacía', () {
      expect(
        () => controlador.establecerValoresIniciales([]),
        throwsArgumentError,
      );
    });

    test('Agrega un número en una celda específica válida', () {
      controlador.establecerValoresIniciales([
        const Celda(
          region: Region.azul,
          valor: 4,
          esInicial: true,
        ),
        const Celda(region: Region.azul),
      ]);

      final agregado = controlador.agregarNumeroEnCelda(1, 4);

      expect(agregado, isTrue);
      expect(controlador.matriz[1].valor, equals(4));
    });

    test('No agrega un número en una casilla inicial', () {
      controlador.establecerValoresIniciales([
        const Celda(
          region: Region.verde,
          valor: 1,
          esInicial: true,
        ),
      ]);

      final agregado = controlador.agregarNumeroEnCelda(0, 5);

      expect(agregado, isFalse);
    });

    test('No agrega números fuera del rango del dado', () {
      controlador.establecerValoresIniciales([
        const Celda(
          region: Region.verde,
          valor: 1,
          esInicial: true,
        ),
        const Celda(region: Region.verde),
      ]);

      final agregado = controlador.agregarNumeroEnCelda(1, 7);

      expect(agregado, isFalse);
    });

    test('Calcula la puntuación total', () {
      controlador.establecerValoresIniciales([
        const Celda(
          region: Region.verde,
          valor: 2,
          esInicial: true,
        ),
        const Celda(region: Region.verde, valor: 5),
        const Celda(
          region: Region.azul,
          valor: 4,
          esInicial: true,
        ),
        const Celda(region: Region.azul, valor: 4),
        const Celda(
          region: Region.rojo,
          valor: 3,
          esInicial: true,
        ),
        const Celda(
          region: Region.morado,
          valor: 6,
          esInicial: true,
        ),
        const Celda(
          region: Region.amarillo,
          valor: 1,
          esInicial: true,
        ),
      ]);

      expect(controlador.calcularPuntuacionTotal(), equals(30));
    });
  });
}