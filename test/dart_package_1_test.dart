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
      expect(tipo.esPosibleAgregar([1, 2, 3], 6), isTrue);
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
      expect(tipo.calcularPuntuacion(4), equals(0));
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
      expect(tipo.calcularPuntuacion(4), equals(0));
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
      expect(tipo.calcularPuntuacion(4), equals(0));
    });
  });

  group('Testear ControladorPartida', () {
    late ControladorPartida controlador;

    final matrizInicial = [
      const Celda(
        region: Region.verde,
        valor: 2,
        esInicial: true,
      ),
      const Celda(region: Region.verde),
      const Celda(
        region: Region.azul,
        valor: 4,
        esInicial: true,
      ),
      const Celda(region: Region.azul),
      const Celda(
        region: Region.rojo,
        valor: 3,
        esInicial: true,
      ),
      const Celda(region: Region.rojo),
      const Celda(
        region: Region.morado,
        valor: 6,
        esInicial: true,
      ),
      const Celda(region: Region.morado),
      const Celda(
        region: Region.amarillo,
        valor: 1,
        esInicial: true,
      ),
      const Celda(region: Region.amarillo),
    ];

    setUp(() {
      controlador = ControladorPartida();
    });

    test('Inicia bloqueado sin valores iniciales', () {
      expect(controlador.tieneValoresIniciales, isFalse);
    });

    test('No permite consultar la matriz sin valores iniciales', () {
      expect(
        () => controlador.matriz,
        throwsA(isA<ValoresInicialesNoProporcionadosException>()),
      );
    });

    test('No permite agregar números sin valores iniciales', () {
      expect(
        () => controlador.agregarNumero(
          Region.verde,
          5,
        ),
        throwsA(isA<ValoresInicialesNoProporcionadosException>()),
      );
    });

    test('No permite calcular puntuación sin valores iniciales', () {
      expect(
        () => controlador.calcularPuntuacionTotal(),
        throwsA(isA<ValoresInicialesNoProporcionadosException>()),
      );
    });

    test('No acepta una matriz inicial vacía', () {
      expect(
        () => controlador.establecerValoresIniciales([]),
        throwsArgumentError,
      );
    });

    test('No acepta una matriz sin casillas iniciales', () {
      expect(
        () => controlador.establecerValoresIniciales([
          const Celda(region: Region.verde),
        ]),
        throwsArgumentError,
      );
    });

    test('No acepta casillas iniciales sin número', () {
      expect(
        () => controlador.establecerValoresIniciales([
          const Celda(
            region: Region.verde,
            esInicial: true,
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('No acepta números iniciales repetidos', () {
      expect(
        () => controlador.establecerValoresIniciales([
          const Celda(
            region: Region.verde,
            valor: 2,
            esInicial: true,
          ),
          const Celda(
            region: Region.rojo,
            valor: 2,
            esInicial: true,
          ),
        ]),
        throwsArgumentError,
      );
    });

    test('Se desbloquea después de proporcionar valores iniciales válidos', () {
      controlador.establecerValoresIniciales(matrizInicial);

      expect(controlador.tieneValoresIniciales, isTrue);
      expect(controlador.matriz, hasLength(10));
    });

    test('Obtiene los valores existentes de una región', () {
      controlador.establecerValoresIniciales(matrizInicial);

      expect(
        controlador.valoresPorRegion(Region.verde),
        equals([2]),
      );

      expect(
        controlador.valoresPorRegion(Region.azul),
        equals([4]),
      );
    });

    test('Agrega un número permitido en una región azul', () {
      controlador.establecerValoresIniciales(matrizInicial);

      final agregado = controlador.agregarNumero(
        Region.azul,
        4,
      );

      expect(agregado, isTrue);
      expect(
        controlador.valoresPorRegion(Region.azul),
        equals([4, 4]),
      );
    });

    test('No agrega un número diferente en una región azul', () {
      controlador.establecerValoresIniciales(matrizInicial);

      final agregado = controlador.agregarNumero(
        Region.azul,
        2,
      );

      expect(agregado, isFalse);
      expect(
        controlador.valoresPorRegion(Region.azul),
        equals([4]),
      );
    });

    test('No agrega números si la región ya no tiene celdas vacías', () {
      controlador.establecerValoresIniciales([
        const Celda(
          region: Region.verde,
          valor: 2,
          esInicial: true,
        ),
      ]);

      final agregado = controlador.agregarNumero(
        Region.verde,
        8,
      );

      expect(agregado, isFalse);
      expect(
        controlador.valoresPorRegion(Region.verde),
        equals([2]),
      );
    });

    test('Calcula la puntuación total de la matriz', () {
      controlador.establecerValoresIniciales([
        const Celda(
          region: Region.verde,
          valor: 2,
          esInicial: true,
        ),
        const Celda(
          region: Region.verde,
          valor: 5,
        ),
        const Celda(
          region: Region.azul,
          valor: 4,
          esInicial: true,
        ),
        const Celda(
          region: Region.azul,
          valor: 4,
        ),
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

      final puntuacion = controlador.calcularPuntuacionTotal();

      expect(puntuacion, equals(30));
    });
  });
}