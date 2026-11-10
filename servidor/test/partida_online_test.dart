import 'dart:math';

import 'package:brilliant_nucleo/brilliant_nucleo.dart';
import 'package:servidor_brilliant/servidor_brilliant.dart';
import 'package:test/test.dart';

import 'ayudas.dart';

PartidaOnline crear(
  List<int> dados, {
  int jugadores = 2,
  int mapa = 0,
  int maxTurnosAgotados = 3,
}) => PartidaOnline(
  mapa: mapa,
  jugadores: [
    for (var i = 0; i < jugadores; i++) (id: 'j$i', nombre: 'Jugador$i'),
  ],
  azar: GuionAzar([...guionInicio, ...dados]),
  maxTurnosAgotados: maxTurnosAgotados,
);

void main() {
  group('Inicio', () {
    test('reparte 1..6 en las casillas iniciales y empieza el jugador 0', () {
      final p = crear([]);
      final iniciales = mapasOficiales.first.indicesIniciales;
      expect([for (final i in iniciales) p.tablero[i]], [1, 2, 3, 4, 5, 6]);
      expect(p.tablero.where((v) => v != null), hasLength(6));
      expect(p.turnoDe, 'j0');
      expect(p.numTurno, 1);
      expect(p.terminada, isFalse);
    });

    test('con azar real los números iniciales son una permutación de 1..6', () {
      for (var s = 0; s < 20; s++) {
        final p = PartidaOnline(
          mapa: 1,
          jugadores: [(id: 'a', nombre: 'A'), (id: 'b', nombre: 'B')],
          azar: Random(s),
        );
        final iniciales = mapasOficiales[1].indicesIniciales;
        expect([for (final i in iniciales) p.tablero[i]!]..sort(), [
          1,
          2,
          3,
          4,
          5,
          6,
        ]);
      }
    });
  });

  group('Turnos', () {
    test('solo juega quien tiene el turno', () {
      final p = crear([0, 1]);
      expect(() => p.tirar('j1'), throwsA(isA<ErrorJuego>()));
      expect(() => p.tirar('desconocido'), throwsA(isA<ErrorJuego>()));
      p.tirar('j0');
      expect(p.dados, [1, 2]);
    });

    test('no se pueden tirar los dados dos veces', () {
      final p = crear([0, 1]);
      p.tirar('j0');
      expect(() => p.tirar('j0'), throwsA(isA<ErrorJuego>()));
      expect(p.dados, [1, 2]);
    });

    test('colocar sin tirar o en una casilla inválida falla sin cambios', () {
      final p = crear([0, 1]);
      expect(() => p.colocar('j0', 1, 0), throwsA(isA<ErrorJuego>()));
      p.tirar('j0');
      // Ancla 1 (pos 0): destino válido es 1 o 3; 9 repetiría el 1 en el azul.
      expect(() => p.colocar('j0', 9, 0), throwsA(isA<ErrorJuego>()));
      expect(() => p.colocar('j0', 1, 2), throwsA(isA<ErrorJuego>()));
      expect(() => p.colocar('j0', -1, 0), throwsA(isA<ErrorJuego>()));
      expect(() => p.colocar('j0', 999, 0), throwsA(isA<ErrorJuego>()));
      expect(() => p.colocar('j1', 1, 0), throwsA(isA<ErrorJuego>()));
      expect(p.tablero[1], isNull);
      expect(p.turnoDe, 'j0');
      expect(p.dados, [1, 2]);
    });

    test('colocar pone el número del otro dado y pasa el turno', () {
      final p = crear([0, 1]);
      p.tirar('j0');
      p.colocar('j0', 1, 0); // ancla = dado 1, se coloca el 2
      expect(p.tablero[1], 2);
      expect(p.turnoDe, 'j1');
      expect(p.numTurno, 2);
      expect(p.dados, isNull);
    });

    test('no se puede pasar si los dados dejan algún movimiento', () {
      final p = crear([0, 1]);
      p.tirar('j0');
      expect(() => p.pasar('j0'), throwsA(isA<ErrorJuego>()));
      expect(p.turnoDe, 'j0');
    });

    test('quien completa un área se lleva sus puntos', () {
      // Área azul {2, 9, 10, 17}: exige todos iguales y el 2 ya tiene un 1.
      final p = crear([0, 0, 0, 0, 0, 0]);
      p.tirar('j0');
      p.colocar('j0', 9, 0);
      p.tirar('j1');
      p.colocar('j1', 10, 0);
      p.tirar('j0');
      p.colocar('j0', 17, 0);
      expect(p.jugador('j0')!.puntos, 7);
      expect(p.jugador('j1')!.puntos, 0);
      expect(p.mensaje, contains('7 puntos'));
      expect(p.turnoDe, 'j1');
    });
  });

  group('Tiempo agotado', () {
    test('pasa el turno y descarta los dados', () {
      final p = crear([0, 1]);
      p.tirar('j0');
      p.tiempoAgotado();
      expect(p.turnoDe, 'j1');
      expect(p.dados, isNull);
      expect(p.mensaje, contains('Se agotó el tiempo'));
      expect(p.terminada, isFalse);
    });

    test('tras demasiados turnos agotados seguidos se da por abandonado', () {
      final p = crear([], maxTurnosAgotados: 2);
      p.tiempoAgotado(); // j0 (1)
      p.tiempoAgotado(); // j1 (1)
      p.tiempoAgotado(); // j0 (2) -> abandona
      expect(p.jugador('j0')!.estado, EstadoJugador.abandono);
      expect(p.terminada, isTrue);
      expect(p.resultado!.motivo, MotivoFin.abandono);
      expect(p.resultado!.ganadores, ['j1']);
    });

    test('jugar de verdad reinicia la cuenta de turnos agotados', () {
      final p = crear([0, 1, 0, 1], maxTurnosAgotados: 2);
      p.tiempoAgotado(); // j0 (1)
      p.tiempoAgotado(); // j1 (1)
      p.tirar('j0'); // reinicia j0
      p.pasarOcolocar();
      p.tiempoAgotado(); // j1 (2) -> abandona
      expect(p.jugador('j1')!.estado, EstadoJugador.abandono);
      expect(p.jugador('j0')!.activo, isTrue);
    });
  });

  group('Rendición y abandono', () {
    test('con dos jugadores, rendirse da la victoria al otro', () {
      final p = crear([]);
      p.conceder('j1'); // no hace falta tener el turno
      expect(p.terminada, isTrue);
      expect(p.jugador('j1')!.estado, EstadoJugador.concedio);
      expect(p.resultado!.motivo, MotivoFin.rendicion);
      expect(p.resultado!.ganadores, ['j0']);
      expect(p.mensaje, contains('Gana Jugador0'));
    });

    test('con tres jugadores la partida sigue y se salta al que se rindió', () {
      final p = crear([], jugadores: 3);
      expect(p.turnoDe, 'j0');
      p.conceder('j0'); // se rinde quien tiene el turno
      expect(p.terminada, isFalse);
      expect(p.turnoDe, 'j1');
      p.tiempoAgotado(); // j1 -> j2, sin pasar por j0
      expect(p.turnoDe, 'j2');
      p.tiempoAgotado(); // j2 -> j1
      expect(p.turnoDe, 'j1');
      p.conceder('j1');
      expect(p.terminada, isTrue);
      expect(p.resultado!.ganadores, ['j2']);
    });

    test('quien ya no participa no puede actuar ni volver a rendirse', () {
      final p = crear([0, 1], jugadores: 3);
      p.conceder('j2');
      expect(() => p.conceder('j2'), throwsA(isA<ErrorJuego>()));
      expect(() => p.tirar('j2'), throwsA(isA<ErrorJuego>()));
    });

    test('abandonar es idempotente y no falla con la partida terminada', () {
      final p = crear([]);
      p.abandonar('j0');
      p.abandonar('j0');
      p.abandonar('j1');
      expect(p.resultado!.ganadores, ['j1']);
      expect(() => p.tirar('j1'), throwsA(isA<ErrorJuego>()));
      expect(() => p.conceder('j1'), throwsA(isA<ErrorJuego>()));
    });
  });

  group('Partidas completas simuladas', () {
    for (var mapa = 0; mapa < mapasOficiales.length; mapa++) {
      for (final n in [2, 3, 4]) {
        test('mapa $mapa con $n jugadores termina de forma coherente', () {
          for (var semilla = 0; semilla < 8; semilla++) {
            final azar = Random(semilla * 31 + n);
            final p = PartidaOnline(
              mapa: mapa,
              jugadores: [
                for (var i = 0; i < n; i++) (id: 'j$i', nombre: 'J$i'),
              ],
              azar: azar,
            );
            // Áreas que nacen completas (casillas iniciales aisladas): sus
            // puntos no son de ningún jugador.
            final base = p.controlador.puntuacionTotal;
            var pasos = 0;
            while (!p.terminada) {
              expect(++pasos, lessThan(20000), reason: 'no termina');
              final id = p.turnoDe;
              p.tirar(id);
              final opciones = [
                for (var pos = 0; pos < 2; pos++)
                  for (final c in p.destinos(pos)) (pos, c),
              ];
              if (opciones.isEmpty) {
                p.pasar(id);
              } else {
                final (pos, c) = opciones[azar.nextInt(opciones.length)];
                p.colocar(id, c, pos);
              }
            }
            final r = p.resultado!;
            expect(r.ganadores, isNotEmpty);
            final suma = p.jugadores.fold<int>(0, (s, j) => s + j.puntos);
            expect(suma + base, p.controlador.puntuacionTotal);
            final mejor = p.jugadores.map((j) => j.puntos).reduce(max);
            for (final g in r.ganadores) {
              expect(p.jugador(g)!.puntos, mejor);
            }
            expect(
              r.motivo,
              anyOf(MotivoFin.tableroCompleto, MotivoFin.sinMovimientos),
            );
            if (r.motivo == MotivoFin.tableroCompleto) {
              expect(p.tablero.every((v) => v != null), isTrue);
            } else {
              expect(p.quedanMovimientos, isFalse);
            }
          }
        });
      }
    }
  });
}

extension on PartidaOnline {
  /// Termina el turno actual: coloca si hay movimiento y si no, pasa.
  void pasarOcolocar() {
    final id = turnoDe;
    for (var pos = 0; pos < 2; pos++) {
      final d = destinos(pos);
      if (d.isNotEmpty) {
        colocar(id, d.first, pos);
        return;
      }
    }
    pasar(id);
  }
}
