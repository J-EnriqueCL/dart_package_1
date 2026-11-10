import 'dart:convert';

import 'package:brilliant_nucleo/brilliant_nucleo.dart';
import 'package:test/test.dart';

void main() {
  final mapa = mapasOficiales.first; // iniciales [2, 12, 22, 25, 37, 46]
  final ini = mapa.indicesIniciales;

  List<int?> vacio() => List<int?>.filled(49, null);

  group('Posiciones iniciales de los mapas', () {
    test('todos los mapas tienen exactamente seis, distintas y válidas', () {
      for (final m in mapasOficiales) {
        expect(m.indicesIniciales, hasLength(6), reason: m.nombre);
        expect(m.indicesIniciales.toSet(), hasLength(6), reason: m.nombre);
        expect(m.indicesIniciales.every((i) => i >= 0 && i < 49), isTrue);
        expect(
          m.crearTablero().where((c) => c.esInicial),
          hasLength(6),
          reason: m.nombre,
        );
      }
    });
  });

  group('errorColocarInicial', () {
    test('acepta cualquier número del 1 al 6 en cualquiera de las seis', () {
      for (final i in ini) {
        for (final n in numerosIniciales) {
          expect(errorColocarInicial(mapa, vacio(), i, n), isNull);
        }
      }
    });

    test('rechaza números fuera de rango', () {
      for (final n in [0, 7, -1, 99]) {
        expect(errorColocarInicial(mapa, vacio(), ini[0], n), isNotNull);
      }
    });

    test('rechaza posiciones que no son iniciales', () {
      for (var i = 0; i < 49; i++) {
        if (ini.contains(i)) continue;
        expect(errorColocarInicial(mapa, vacio(), i, 1), isNotNull);
        expect(errorQuitarInicial(mapa, i), isNotNull);
      }
    });

    test('rechaza número ya usado y posición ocupada con otro número', () {
      final t = vacio()..[ini[0]] = 3;
      expect(errorColocarInicial(mapa, t, ini[1], 3), isNotNull);
      expect(errorColocarInicial(mapa, t, ini[0], 4), isNotNull);
    });

    test('repetir exactamente lo ya colocado es válido y no cambia nada', () {
      final t = vacio()..[ini[0]] = 3;
      expect(errorColocarInicial(mapa, t, ini[0], 3), isNull);
    });
  });

  group('Confirmación', () {
    test('exige los seis números, sin repetir', () {
      final t = vacio();
      expect(errorConfirmarDistribucion(mapa, t), contains('Faltan 6'));
      for (var k = 0; k < 5; k++) {
        t[ini[k]] = k + 1;
      }
      expect(errorConfirmarDistribucion(mapa, t), contains('Falta 1'));
      t[ini[5]] = 6;
      expect(errorConfirmarDistribucion(mapa, t), isNull);
    });

    test('un duplicado deja un número sin colocar y no se confirma', () {
      final t = vacio();
      for (var k = 0; k < 6; k++) {
        t[ini[k]] = k + 1;
      }
      t[ini[5]] = 1;
      expect(numerosPendientes(mapa, t), [6]);
      expect(errorConfirmarDistribucion(mapa, t), isNotNull);
    });

    test('pendientes y colocados cuadran en cualquier reparto parcial', () {
      final t = vacio()
        ..[ini[1]] = 5
        ..[ini[3]] = 2;
      expect(numerosColocados(mapa, t), {5, 2});
      expect(numerosPendientes(mapa, t), [1, 3, 4, 6]);
    });
  });

  group('Preparación a medias en el cliente', () {
    EstadoSala parcial(List<int?> tablero) => EstadoSala(
      yo: 'a',
      codigo: 'ABC234',
      fase: FaseSala.preparacion,
      mapa: 0,
      maxJugadores: 4,
      anfitrion: 'a',
      jugadores: const [
        JugadorSala(id: 'a', nombre: 'Ana', conectado: true),
        JugadorSala(id: 'b', nombre: 'Beto', conectado: true),
      ],
      tablero: tablero,
    );

    test('crearControlador acepta un tablero incompleto', () {
      final t = vacio()
        ..[ini[0]] = 4
        ..[ini[1]] = 2;
      final c = parcial(t).crearControlador();
      expect(c.matriz[ini[0]].valor, 4);
      expect(c.matriz[ini[2]].valor, isNull);
      expect(c.puntuacionTotal, 0);
    });

    test('numerosPorColocar y el JSON de la fase de preparación', () {
      final e = parcial(vacio()..[ini[0]] = 4);
      expect(e.numerosPorColocar, [1, 2, 3, 5, 6]);
      final copia = EstadoSala.fromJson(
        (jsonDecode(jsonEncode(e.toJson())) as Map).cast<String, Object?>(),
      );
      expect(copia.fase, FaseSala.preparacion);
      expect(copia.numerosPorColocar, [1, 2, 3, 5, 6]);
      expect(copia.esMiTurno, isFalse);
    });
  });

  group('Estados de los jugadores', () {
    test('todos los estados viajan por JSON y distinguen la participación', () {
      for (final e in EstadoJugador.values) {
        final j = JugadorSala(
          id: 'a',
          nombre: 'A',
          conectado: false,
          estado: e,
        );
        final copia = JugadorSala.fromJson(
          (jsonDecode(jsonEncode(j.toJson())) as Map).cast<String, Object?>(),
        );
        expect(copia.estado, e);
        expect(copia.conectado, isFalse, reason: 'la conexión es aparte');
        expect(
          copia.participa,
          e != EstadoJugador.concedio && e != EstadoJugador.abandono,
        );
      }
    });

    test('un estado desconocido se rechaza', () {
      expect(() => EstadoJugador.desde('activo'), throwsFormatException);
    });
  });
}
