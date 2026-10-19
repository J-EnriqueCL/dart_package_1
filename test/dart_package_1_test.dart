import 'package:flutter_test/flutter_test.dart';

import 'package:dart_package_1/dart_package_1.dart';

void main() {
  group('Reglas de las regiones', () {
    test('la región verde permite cualquier número válido', () {
      expect(Region.verde.permite(<int>[], 1), isTrue);

      expect(Region.verde.permite(<int>[1, 2, 3, 4], 1), isTrue);

      expect(Region.verde.permite(<int>[1, 2, 3, 4], 6), isTrue);
    });

    test('la región azul permite solo números iguales', () {
      expect(Region.azul.permite(<int>[], 3), isTrue);

      expect(Region.azul.permite(<int>[3, 3], 3), isTrue);

      expect(Region.azul.permite(<int>[3, 3], 4), isFalse);
    });

    test('la región amarilla no permite números repetidos', () {
      expect(Region.amarillo.permite(<int>[1, 2, 3], 4), isTrue);

      expect(Region.amarillo.permite(<int>[1, 2, 3], 2), isFalse);
    });

    test('la región roja no permite números repetidos', () {
      expect(Region.rojo.permite(<int>[2, 4], 6), isTrue);

      expect(Region.rojo.permite(<int>[2, 4], 4), isFalse);
    });

    test('la región morada permite como máximo dos valores distintos', () {
      expect(Region.morado.permite(<int>[], 2), isTrue);

      expect(Region.morado.permite(<int>[2, 2], 5), isTrue);

      expect(Region.morado.permite(<int>[2, 5, 2], 2), isTrue);

      expect(Region.morado.permite(<int>[2, 5, 2], 4), isFalse);
    });

    test('ninguna región permite números fuera del rango de 1 a 6', () {
      for (final region in Region.values) {
        expect(region.permite(<int>[], 0), isFalse);

        expect(region.permite(<int>[], 7), isFalse);
      }
    });
  });

  group('Tablero', () {
    test('el tablero contiene 49 casillas', () {
      final tablero = crearTableroNivelUno();

      expect(tablero, hasLength(49));
    });

    test('el tablero contiene seis casillas iniciales', () {
      final tablero = crearTableroNivelUno();

      final iniciales = tablero.where((celda) => celda.esInicial);

      expect(iniciales, hasLength(6));
    });

    test('las casillas iniciales están vacías antes de elegir números', () {
      final tablero = crearTableroNivelUno();

      final iniciales = tablero.where((celda) => celda.esInicial);

      expect(iniciales.every((celda) => celda.valor == null), isTrue);
    });

    test('los vecinos de una esquina son válidos', () {
      final vecinos = ControladorPartida.vecinosDe(0);

      expect(vecinos, hasLength(2));
      expect(vecinos, contains(1));
      expect(vecinos, contains(7));
    });

    test('una casilla central tiene cuatro vecinos ortogonales', () {
      final vecinos = ControladorPartida.vecinosDe(24);

      expect(vecinos, hasLength(4));
    });

    test('un índice inválido no genera vecinos', () {
      expect(ControladorPartida.vecinosDe(-1), isEmpty);

      expect(ControladorPartida.vecinosDe(49), isEmpty);
    });
  });

  group('Configuración de números iniciales', () {
    test('acepta seis números distintos del 1 al 6', () {
      final controlador = ControladorPartida();
      final tablero = _crearTableroConInicialesValidos();

      expect(
        () => controlador.establecerValoresIniciales(tablero),
        returnsNormally,
      );

      expect(controlador.matriz, hasLength(49));
    });

    test('rechaza un tablero que no tiene 49 celdas', () {
      final controlador = ControladorPartida();

      final tableroIncompleto = List<Celda>.filled(
        48,
        const Celda(region: Region.verde),
      );

      expect(
        () => controlador.establecerValoresIniciales(tableroIncompleto),
        throwsArgumentError,
      );
    });

    test('rechaza valores iniciales repetidos', () {
      final controlador = ControladorPartida();
      final tablero = crearTableroNivelUno();

      final indicesIniciales = _obtenerIndicesIniciales(tablero);

      for (final indice in indicesIniciales) {
        tablero[indice] = tablero[indice].copiarCon(valor: 1);
      }

      expect(
        () => controlador.establecerValoresIniciales(tablero),
        throwsArgumentError,
      );
    });

    test('rechaza si falta uno de los valores del 1 al 6', () {
      final controlador = ControladorPartida();
      final tablero = crearTableroNivelUno();
      final indicesIniciales = _obtenerIndicesIniciales(tablero);

      const valoresIncorrectos = <int>[1, 2, 3, 4, 5, 5];

      for (var i = 0; i < indicesIniciales.length; i++) {
        final indice = indicesIniciales[i];

        tablero[indice] = tablero[indice].copiarCon(
          valor: valoresIncorrectos[i],
        );
      }

      expect(
        () => controlador.establecerValoresIniciales(tablero),
        throwsArgumentError,
      );
    });
  });

  group('Colocación de números', () {
    test('no permite jugar antes de configurar valores iniciales', () {
      final controlador = ControladorPartida();

      expect(() => controlador.matriz, throwsStateError);

      expect(() => controlador.areas, throwsStateError);
    });

    test('no permite colocar números fuera del rango de 1 a 6', () {
      final controlador = _crearControladorListo();
      final casillaVacia = _buscarCasillaLibreNoInicial(controlador);

      expect(controlador.puedeColocar(casillaVacia, 0), isFalse);

      expect(controlador.puedeColocar(casillaVacia, 7), isFalse);
    });

    test('no permite colocar un número fuera de los límites del tablero', () {
      final controlador = _crearControladorListo();

      expect(controlador.puedeColocar(-1, 1), isFalse);

      expect(controlador.puedeColocar(49, 1), isFalse);
    });

    test('no permite escribir sobre una casilla inicial', () {
      final controlador = _crearControladorListo();

      final indiceInicial = controlador.matriz.indexWhere(
        (celda) => celda.esInicial,
      );

      expect(controlador.puedeColocar(indiceInicial, 1), isFalse);
    });

    test('no permite sobrescribir una casilla ya ocupada', () {
      final controlador = _crearControladorListo();

      final indice = _buscarCasillaVerdeLibre(controlador);

      expect(controlador.colocar(indice, 1), isTrue);

      expect(controlador.colocar(indice, 2), isFalse);
    });

    test('permite colocar un número válido en una casilla verde libre', () {
      final controlador = _crearControladorListo();

      final indice = _buscarCasillaVerdeLibre(controlador);

      expect(controlador.colocar(indice, 6), isTrue);

      expect(controlador.matriz[indice].valor, 6);
    });
  });

  group('Regla del ancla', () {
    test('los destinos posibles no contienen diagonales', () {
      final controlador = _crearControladorListo();

      final numeroAncla = controlador.matriz
          .where((celda) => celda.valor != null)
          .first
          .valor!;

      final destinos = controlador.destinosPosibles(
        ancla: numeroAncla,
        colocar: 6,
      );

      for (final destino in destinos) {
        expect(destino, inInclusiveRange(0, 48));
      }
    });

    test('los destinos posibles nunca incluyen una casilla ya ocupada', () {
      final controlador = _crearControladorListo();

      final numeroAncla = controlador.matriz
          .where((celda) => celda.valor != null)
          .first
          .valor!;

      final destinos = controlador.destinosPosibles(
        ancla: numeroAncla,
        colocar: 6,
      );

      for (final destino in destinos) {
        expect(controlador.matriz[destino].valor, isNull);
      }
    });

    test('los destinos posibles nunca incluyen casillas iniciales', () {
      final controlador = _crearControladorListo();

      final numeroAncla = controlador.matriz
          .where((celda) => celda.valor != null)
          .first
          .valor!;

      final destinos = controlador.destinosPosibles(
        ancla: numeroAncla,
        colocar: 6,
      );

      for (final destino in destinos) {
        expect(controlador.matriz[destino].esInicial, isFalse);
      }
    });

    test('datos inválidos producen cero destinos posibles', () {
      final controlador = _crearControladorListo();

      expect(controlador.destinosPosibles(ancla: 0, colocar: 3), isEmpty);

      expect(controlador.destinosPosibles(ancla: 3, colocar: 7), isEmpty);
    });
  });

  group('Puntuación', () {
    test('la puntuación comienza en cero', () {
      final controlador = _crearControladorListo();

      expect(controlador.puntuacionTotal, 0);
    });

    test('las regiones comienzan sin puntos', () {
      final controlador = _crearControladorListo();

      for (final region in Region.values) {
        expect(controlador.puntosDeRegion(region), 0);
      }
    });

    test('un área incompleta no genera puntos', () {
      final controlador = _crearControladorListo();

      final area = controlador.areas.firstWhere((area) => area.tamano > 1);

      expect(controlador.areaCompleta(area), isFalse);

      expect(controlador.puntosDeArea(area), 0);
    });

    test('una región completa aporta puntos a la puntuación total', () {
      final controlador = _crearControladorListo();

      final areaVerde = controlador
          .areasDe(Region.verde)
          .firstWhere((area) => area.tamano > 1);

      final puntuacionAntes = controlador.puntuacionTotal;

      for (final indice in areaVerde.indices) {
        final celda = controlador.matriz[indice];

        if (celda.valor == null) {
          expect(controlador.colocar(indice, 1), isTrue);
        }
      }

      expect(controlador.areaCompleta(areaVerde), isTrue);

      expect(controlador.puntosDeArea(areaVerde), greaterThan(0));

      expect(controlador.puntuacionTotal, greaterThan(puntuacionAntes));
    });
  });
}

List<int> _obtenerIndicesIniciales(List<Celda> tablero) {
  final indices = <int>[];

  for (var indice = 0; indice < tablero.length; indice++) {
    if (tablero[indice].esInicial) {
      indices.add(indice);
    }
  }

  return indices;
}

List<Celda> _crearTableroConInicialesValidos() {
  final tablero = crearTableroNivelUno();
  final indicesIniciales = _obtenerIndicesIniciales(tablero);

  for (var posicion = 0; posicion < indicesIniciales.length; posicion++) {
    final indice = indicesIniciales[posicion];

    tablero[indice] = tablero[indice].copiarCon(valor: posicion + 1);
  }

  return tablero;
}

ControladorPartida _crearControladorListo() {
  final controlador = ControladorPartida();

  controlador.establecerValoresIniciales(_crearTableroConInicialesValidos());

  return controlador;
}

int _buscarCasillaLibreNoInicial(ControladorPartida controlador) {
  return controlador.matriz.indexWhere(
    (celda) => !celda.esInicial && celda.valor == null,
  );
}

int _buscarCasillaVerdeLibre(ControladorPartida controlador) {
  return controlador.matriz.indexWhere((celda) {
    return celda.region == Region.verde &&
        !celda.esInicial &&
        celda.valor == null;
  });
}
