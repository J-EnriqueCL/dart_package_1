import 'dart:math';

import 'package:brilliant_nucleo/brilliant_nucleo.dart';
import 'package:servidor_brilliant/servidor_brilliant.dart';
import 'package:test/test.dart';

import 'ayudas.dart';

/// Partida en preparación. Los [dados] se usan cuando empiece la partida.
PartidaOnline preparar(
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

/// Partida ya en marcha: todos distribuyeron 1..6 en orden y empieza `j0`.
PartidaOnline crear(
  List<int> dados, {
  int jugadores = 2,
  int mapa = 0,
  int maxTurnosAgotados = 3,
}) {
  final p = preparar(
    dados,
    jugadores: jugadores,
    mapa: mapa,
    maxTurnosAgotados: maxTurnosAgotados,
  );
  for (final j in p.jugadores) {
    distribuir(p, j.id);
  }
  return p;
}

/// Dados que siempre dan 1 y 1 (guion largo).
final unosSiempre = List<int>.filled(120, 0);

/// Juega un turno al azar: coloca si hay movimiento y si no, pasa.
void jugarTurno(PartidaOnline p, Random azar) {
  final id = p.turnoDe;
  p.tirar(id);
  final opciones = [
    for (var pos = 0; pos < 2; pos++)
      for (final c in p.destinos(id, pos)) (pos, c),
  ];
  if (opciones.isEmpty) {
    p.pasar(id);
  } else {
    final (pos, c) = opciones[azar.nextInt(opciones.length)];
    p.colocar(id, c, pos);
  }
}

PartidaOnline azarosa(int mapa, int n, int semilla) {
  final azar = Random(semilla);
  final p = PartidaOnline(
    mapa: mapa,
    jugadores: [for (var i = 0; i < n; i++) (id: 'j$i', nombre: 'J$i')],
    azar: azar,
  );
  for (final j in p.jugadores) {
    final orden = [1, 2, 3, 4, 5, 6]..shuffle(azar);
    distribuir(p, j.id, orden: orden);
  }
  return p;
}

void main() {
  final iniciales = mapasOficiales.first.indicesIniciales; // [2,12,22,25,37,46]

  group('Preparación', () {
    test(
      'al empezar no hay números iniciales ni turno: hay que colocarlos',
      () {
        final p = preparar([]);
        expect(p.fase, FasePartida.preparacion);
        for (final j in p.jugadores) {
          expect(j.tablero.where((v) => v != null), isEmpty);
          expect(j.estado, EstadoJugador.preparando);
          expect(j.puntos, 0);
        }
        expect(p.dados, isNull);
      },
    );

    test(
      'cada jugador puede repartir el 1..6 libremente (todos los mapas)',
      () {
        for (var m = 0; m < mapasOficiales.length; m++) {
          final ini = mapasOficiales[m].indicesIniciales;
          final azar = Random(m);
          for (var rep = 0; rep < 10; rep++) {
            final p = preparar([], mapa: m);
            final orden = [1, 2, 3, 4, 5, 6]..shuffle(azar);
            distribuir(p, 'j0', orden: orden);
            final t = p.tableroDe('j0');
            expect([for (final i in ini) t[i]], orden);
            expect(t.where((v) => v != null), hasLength(6));
          }
        }
      },
    );

    test('dos jugadores confirman distribuciones distintas', () {
      final p = preparar([]);
      distribuir(p, 'j0', orden: [1, 2, 3, 4, 5, 6]);
      distribuir(p, 'j1', orden: [6, 5, 4, 3, 2, 1]);
      expect(
        [for (final i in iniciales) p.tableroDe('j0')[i]],
        [1, 2, 3, 4, 5, 6],
      );
      expect(
        [for (final i in iniciales) p.tableroDe('j1')[i]],
        [6, 5, 4, 3, 2, 1],
      );
      expect(p.fase, FasePartida.jugando);
    });

    test('rechaza valores fuera de rango', () {
      final p = preparar([]);
      for (final v in [0, 7, -1, 100]) {
        expect(
          () => p.colocarInicial('j0', iniciales[0], v),
          throwsA(isA<ErrorJuego>()),
          reason: 'valor $v',
        );
      }
      expect(p.tableroDe('j0').where((v) => v != null), isEmpty);
    });

    test('rechaza posiciones que no son de las seis iniciales', () {
      final p = preparar([]);
      for (final i in [0, 1, 3, 48, -1, 49, 999]) {
        expect(
          () => p.colocarInicial('j0', i, 1),
          throwsA(isA<ErrorJuego>()),
          reason: 'posición $i',
        );
        expect(() => p.quitarInicial('j0', i), throwsA(isA<ErrorJuego>()));
      }
      expect(p.tableroDe('j0').where((v) => v != null), isEmpty);
    });

    test('rechaza números duplicados y posiciones ya ocupadas', () {
      final p = preparar([]);
      p.colocarInicial('j0', iniciales[0], 3);
      // El 3 ya está en otra posición.
      expect(
        () => p.colocarInicial('j0', iniciales[1], 3),
        throwsA(isA<ErrorJuego>()),
      );
      // La posición ya tiene otro número.
      expect(
        () => p.colocarInicial('j0', iniciales[0], 4),
        throwsA(isA<ErrorJuego>()),
      );
      expect(p.tableroDe('j0')[iniciales[0]], 3);
      expect(p.tableroDe('j0')[iniciales[1]], isNull);
    });

    test('no se confirma una distribución incompleta', () {
      final p = preparar([]);
      expect(() => p.confirmarDistribucion('j0'), throwsA(isA<ErrorJuego>()));
      for (var k = 0; k < 5; k++) {
        p.colocarInicial('j0', iniciales[k], k + 1);
      }
      expect(() => p.confirmarDistribucion('j0'), throwsA(isA<ErrorJuego>()));
      expect(p.jugador('j0')!.estado, EstadoJugador.preparando);
    });

    test('se puede corregir antes de confirmar', () {
      final p = preparar([]);
      colocarTodos(p, 'j0');
      p.quitarInicial('j0', iniciales[0]); // quita el 1
      p.quitarInicial('j0', iniciales[1]); // quita el 2
      expect(p.tableroDe('j0')[iniciales[0]], isNull);
      p.colocarInicial('j0', iniciales[0], 2);
      p.colocarInicial('j0', iniciales[1], 1);
      p.confirmarDistribucion('j0');
      expect(p.tableroDe('j0')[iniciales[0]], 2);
      expect(p.tableroDe('j0')[iniciales[1]], 1);
      expect(p.jugador('j0')!.estado, EstadoJugador.listo);
    });

    test('tras confirmar no se puede modificar', () {
      final p = preparar([]);
      distribuir(p, 'j0');
      final antes = p.tableroDe('j0');
      expect(
        () => p.quitarInicial('j0', iniciales[0]),
        throwsA(isA<ErrorJuego>()),
      );
      expect(
        () => p.colocarInicial('j0', iniciales[0], 1),
        throwsA(isA<ErrorJuego>()),
      );
      expect(p.tableroDe('j0'), antes);
      expect(p.jugador('j0')!.estado, EstadoJugador.listo);
    });

    test('no se aceptan jugadas normales durante la preparación', () {
      final p = preparar([0, 1]);
      distribuir(p, 'j0'); // listo, espera a j1
      for (final id in ['j0', 'j1']) {
        expect(() => p.tirar(id), throwsA(isA<ErrorJuego>()));
        expect(() => p.colocar(id, 9, 0), throwsA(isA<ErrorJuego>()));
        expect(() => p.pasar(id), throwsA(isA<ErrorJuego>()));
      }
      expect(p.dados, isNull);
      expect(p.fase, FasePartida.preparacion);
    });

    test('un jugador listo espera a los demás', () {
      final p = preparar([]);
      distribuir(p, 'j0');
      expect(p.fase, FasePartida.preparacion);
      expect(p.jugador('j0')!.estado, EstadoJugador.listo);
      expect(p.jugador('j1')!.estado, EstadoJugador.preparando);
    });

    test('la partida empieza una sola vez, cuando todos están listos', () {
      // El guion solo tiene el valor del primer turno: si algo intentara
      // empezar dos veces, consumiría azar de más y fallaría.
      final p = PartidaOnline(
        mapa: 0,
        jugadores: [
          (id: 'j0', nombre: 'A'),
          (id: 'j1', nombre: 'B'),
          (id: 'j2', nombre: 'C'),
        ],
        azar: GuionAzar([2]),
      );
      distribuir(p, 'j0');
      distribuir(p, 'j1');
      expect(p.fase, FasePartida.preparacion);
      distribuir(p, 'j2');
      expect(p.fase, FasePartida.jugando);
      expect(p.turnoDe, 'j2');
      expect(p.numTurno, 1);
      expect([
        for (final j in p.jugadores) j.estado,
      ], everyElement(EstadoJugador.jugando));
      // Confirmaciones repetidas: no reinician nada.
      p.confirmarDistribucion('j0');
      p.confirmarDistribucion('j2');
      expect(p.turnoDe, 'j2');
      expect(p.numTurno, 1);
    });

    test(
      'los mensajes repetidos no duplican colocaciones ni confirmaciones',
      () {
        final p = preparar([]);
        p.colocarInicial('j0', iniciales[0], 4);
        p.colocarInicial('j0', iniciales[0], 4);
        expect(p.tableroDe('j0').where((v) => v != null), hasLength(1));
        p.quitarInicial('j0', iniciales[3]); // vacía: no hace nada
        expect(p.tableroDe('j0').where((v) => v != null), hasLength(1));
        colocarTodos(p, 'j0', orden: [4, 1, 2, 3, 5, 6]);
        p.confirmarDistribucion('j0');
        p.confirmarDistribucion('j0');
        expect(p.jugador('j0')!.estado, EstadoJugador.listo);
        expect(p.fase, FasePartida.preparacion);
      },
    );

    test('quien no participa o no existe no puede preparar', () {
      final p = preparar([], jugadores: 3);
      expect(
        () => p.colocarInicial('x', iniciales[0], 1),
        throwsA(isA<ErrorJuego>()),
      );
      p.conceder('j2');
      expect(
        () => p.colocarInicial('j2', iniciales[0], 1),
        throwsA(isA<ErrorJuego>()),
      );
      expect(() => p.confirmarDistribucion('j2'), throwsA(isA<ErrorJuego>()));
    });
  });

  group('Tableros independientes', () {
    test('cada jugador tiene su propio estado de tablero', () {
      final p = crear([0, 1]);
      p.jugador('j1')!.controlador; // existe y es distinto
      expect(
        identical(p.jugador('j0')!.controlador, p.jugador('j1')!.controlador),
        isFalse,
      );
    });

    test('una jugada solo modifica el tablero de quien juega', () {
      final p = crear([0, 1]);
      final rival = p.tableroDe('j1');
      p.tirar('j0');
      p.colocar('j0', 1, 0);
      expect(p.tableroDe('j0')[1], 2);
      expect(p.tableroDe('j1'), rival);
      expect(p.tableroDe('j1')[1], isNull);
    });

    test('un jugador no puede tocar un tablero ajeno', () {
      final p = crear([0, 1]);
      final antes0 = p.tableroDe('j0');
      // j1 no tiene el turno: no puede tirar ni colocar (ni en su tablero ni
      // en el de j0).
      expect(() => p.tirar('j1'), throwsA(isA<ErrorJuego>()));
      p.tirar('j0');
      expect(() => p.colocar('j1', 1, 0), throwsA(isA<ErrorJuego>()));
      expect(p.tableroDe('j0'), antes0);
      expect(p.tableroDe('j1').where((v) => v != null), hasLength(6));
    });

    test('en la preparación cada confirmación afecta solo a su dueño', () {
      final p = preparar([]);
      colocarTodos(p, 'j1', orden: [6, 5, 4, 3, 2, 1]);
      expect(p.tableroDe('j0').where((v) => v != null), isEmpty);
      p.confirmarDistribucion('j1');
      expect(p.jugador('j0')!.estado, EstadoJugador.preparando);
      expect(p.jugador('j1')!.estado, EstadoJugador.listo);
    });
  });

  group('Puntuación', () {
    test('quien completa un área se lleva sus puntos en su tablero', () {
      // Área azul {2, 9, 10, 17}: exige todos iguales y el 2 ya tiene un 1.
      final p = crear([0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
      p.tirar('j0');
      p.colocar('j0', 9, 0);
      p.tirar('j1');
      p.colocar('j1', 9, 0);
      p.tirar('j0');
      p.colocar('j0', 10, 0);
      p.tirar('j1');
      p.colocar('j1', 10, 0);
      p.tirar('j0');
      p.colocar('j0', 17, 0);
      expect(p.jugador('j0')!.puntos, 7);
      expect(p.jugador('j1')!.puntos, 0);
      expect(p.mensaje, contains('7 puntos'));
      expect(p.turnoDe, 'j1');
    });

    test(
      'los puntos salen del tablero y coinciden con las reglas del núcleo',
      () {
        final p = azarosa(2, 3, 5);
        final azar = Random(9);
        while (!p.terminada) {
          jugarTurno(p, azar);
          for (final j in p.jugadores) {
            final c = ControladorPartida(
              gruposConectados: p.mapaOficial.gruposConectados,
            );
            final celdas = p.mapaOficial.crearTablero();
            final t = j.tablero;
            for (var i = 0; i < 49; i++) {
              if (t[i] != null) celdas[i] = celdas[i].copiarCon(valor: t[i]);
            }
            c.establecerValoresIniciales(celdas);
            expect(j.puntos, c.puntuacionTotal);
          }
        }
      },
    );

    test('un área puntúa una sola vez aunque se sigan haciendo jugadas', () {
      final p = crear(unosSiempre);
      for (final c in [9, 10, 17]) {
        p.tirar('j0');
        p.colocar('j0', c, 0);
        p.tirar('j1');
        p.pasarOcolocar();
      }
      expect(p.jugador('j0')!.puntos, 7);
      p.tirar('j0');
      p.pasarOcolocar();
      expect(p.jugador('j0')!.puntos, 7);
    });

    test('mapa con áreas completas desde el inicio: puntos sin duplicar', () {
      // Nivel 3: dos áreas blancas de una casilla son iniciales (4 + 4).
      final p = preparar([], mapa: 2);
      final ini = mapasOficiales[2].indicesIniciales;
      colocarTodos(p, 'j0', orden: [1, 2, 3, 4, 5, 6]);
      expect(p.jugador('j0')!.puntos, 0, reason: 'sin confirmar no hay puntos');
      // Editar: quitar y volver a poner no acumula nada.
      p.quitarInicial('j0', ini[0]);
      p.colocarInicial('j0', ini[0], 1);
      expect(p.jugador('j0')!.puntos, 0);
      p.confirmarDistribucion('j0');
      expect(p.jugador('j0')!.puntos, 8);
      p.confirmarDistribucion('j0'); // repetida
      expect(p.jugador('j0')!.puntos, 8);
      expect(p.jugador('j1')!.puntos, 0, reason: 'cada tablero es de su dueño');
      distribuir(p, 'j1', orden: [6, 5, 4, 3, 2, 1]);
      expect(p.jugador('j1')!.puntos, 8);
      expect(p.jugador('j0')!.puntos, 8);
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
      expect(p.tableroDe('j0')[1], isNull);
      expect(p.turnoDe, 'j0');
      expect(p.dados, [1, 2]);
    });

    test('colocar pone el número del otro dado y pasa el turno', () {
      final p = crear([0, 1]);
      p.tirar('j0');
      p.colocar('j0', 1, 0); // ancla = dado 1, se coloca el 2
      expect(p.tableroDe('j0')[1], 2);
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
      expect(p.jugador('j0')!.participa, isTrue);
    });
  });

  group('Rendición y abandono en partida', () {
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

    test('quien se rinde conserva su puntuación y no puede ganar', () {
      final p = crear(unosSiempre, jugadores: 3);
      // j0 completa el área azul (7 puntos) y luego se rinde.
      for (final c in [9, 10, 17]) {
        p.tirar('j0');
        p.colocar('j0', c, 0);
        while (p.turnoDe != 'j0') {
          p.tirar(p.turnoDe);
          p.pasarOcolocar();
        }
      }
      expect(p.jugador('j0')!.puntos, 7);
      p.conceder('j0');
      expect(p.jugador('j0')!.puntos, 7);
      expect(p.jugador('j0')!.estado, EstadoJugador.concedio);
      expect(p.terminada, isFalse, reason: 'quedan dos jugadores elegibles');
    });
  });

  group('Rendición, abandono y desconexión en la preparación', () {
    test('si se rinde alguien y quedan dos o más, la preparación sigue', () {
      final p = preparar([], jugadores: 3);
      p.conceder('j2');
      expect(p.terminada, isFalse);
      expect(p.fase, FasePartida.preparacion);
      expect(p.jugador('j2')!.estado, EstadoJugador.concedio);
    });

    test('si quedan dos y ya confirmaron, empieza sin esperar al ausente', () {
      final p = preparar([], jugadores: 3);
      distribuir(p, 'j0');
      distribuir(p, 'j1');
      expect(p.fase, FasePartida.preparacion);
      p.abandonar('j2');
      expect(p.fase, FasePartida.jugando);
      expect(p.jugador('j2')!.estado, EstadoJugador.abandono);
      expect(p.turnoDe, anyOf('j0', 'j1'));
      // El que abandonó no recibe turnos.
      for (var i = 0; i < 6; i++) {
        expect(p.turnoDe, isNot('j2'));
        p.tiempoAgotado();
        if (p.terminada) break;
      }
    });

    test('con un único participante restante termina y gana ese', () {
      final p = preparar([]);
      distribuir(p, 'j0');
      p.abandonar('j1');
      expect(p.terminada, isTrue);
      expect(p.resultado!.ganadores, ['j0']);
      expect(p.resultado!.motivo, MotivoFin.abandono);
      p.abandonar('j1'); // repetido: sin efecto
      expect(p.resultado!.ganadores, ['j0']);
    });

    test('rendirse en la preparación deja ganar al único restante', () {
      final p = preparar([]);
      p.conceder('j0');
      expect(p.terminada, isTrue);
      expect(p.resultado!.motivo, MotivoFin.rendicion);
      expect(p.resultado!.ganadores, ['j1']);
    });

    test(
      'quien abandona antes de confirmar conserva 0 puntos y no puede ganar',
      () {
        final p = preparar([], mapa: 2, jugadores: 3);
        colocarTodos(p, 'j2');
        p.abandonar('j2');
        expect(p.jugador('j2')!.puntos, 0);
        distribuir(p, 'j0');
        distribuir(p, 'j1');
        expect(p.fase, FasePartida.jugando);
        expect(p.jugador('j0')!.puntos, 8);
      },
    );

    test('retiros uno a uno: al quedar un solo participante gana ese', () {
      // Aquí los retiros llegan en eventos distintos, así que nunca se llega a
      // cero elegibles. El caso "todos a la vez" (cero elegibles, sin ganador)
      // está en el grupo 'Abandono simultáneo'.
      final p = preparar([], jugadores: 3);
      p.abandonar('j0');
      expect(p.terminada, isFalse);
      p.abandonar('j1');
      expect(p.terminada, isTrue);
      expect(p.resultado!.ganadores, ['j2']);
      p.abandonar('j2');
      expect(p.resultado!.ganadores, ['j2']);
    });
  });

  group('Abandono simultáneo', () {
    test('todos los participantes abandonan a la vez: final sin ganador', () {
      final p = crear([]);
      p.abandonarVarios(['j0', 'j1']);
      expect(p.terminada, isTrue);
      expect(p.resultado!.ganadores, isEmpty);
      expect(p.resultado!.motivo, MotivoFin.abandono);
      expect(p.mensaje, contains('Nadie gana'));
      for (final j in p.jugadores) {
        expect(j.estado, EstadoJugador.abandono);
      }
    });

    test('el resultado no depende del orden de la lista', () {
      String resumen(List<String> ids) {
        final p = crear([], jugadores: 3);
        p.abandonarVarios(ids);
        return '${p.resultado!.ganadores}|${p.resultado!.motivo}|'
            '${[for (final j in p.jugadores) j.estado]}';
      }

      expect(resumen(['j0', 'j1']), resumen(['j1', 'j0']));
      expect(resumen(['j0', 'j1']), contains('[j2]'));
    });

    test('con tres, si abandonan dos a la vez gana el que queda', () {
      final p = crear([], jugadores: 3);
      p.abandonarVarios(['j1', 'j2']);
      expect(p.terminada, isTrue);
      expect(p.resultado!.ganadores, ['j0']);
    });

    test('con cuatro, si abandonan dos la partida sigue entre los otros', () {
      final p = crear([], jugadores: 4);
      p.abandonarVarios(['j0', 'j1']); // j0 tenía el turno
      expect(p.terminada, isFalse);
      expect(p.turnoDe, anyOf('j2', 'j3'));
      expect(p.dados, isNull);
    });

    test(
      'quien ya no participa o no existe se ignora; repetir no cambia nada',
      () {
        final p = crear([], jugadores: 3);
        p.conceder('j2');
        p.abandonarVarios(['j2', 'nadie']);
        expect(p.jugador('j2')!.estado, EstadoJugador.concedio);
        expect(p.terminada, isFalse);
        p.abandonarVarios(['j0', 'j1']);
        expect(p.resultado!.ganadores, isEmpty);
        final antes = p.mensaje;
        p.abandonarVarios(['j0', 'j1']);
        expect(p.mensaje, antes);
      },
    );

    test('también sin ganador si todos abandonan en la preparación', () {
      final p = preparar([]);
      distribuir(p, 'j0');
      p.abandonarVarios(['j0', 'j1']);
      expect(p.terminada, isTrue);
      expect(p.resultado!.ganadores, isEmpty);
    });

    test('rendido y abandonado a la vez, sin nadie más: sin ganador', () {
      final p = crear([], jugadores: 3);
      p.conceder('j2');
      p.abandonarVarios(['j0', 'j1']);
      expect(p.resultado!.ganadores, isEmpty);
    });
  });

  group('Jugadores que terminan su tablero', () {
    test('si el terminado y el último empatan, comparten la victoria', () {
      final p = crear(unosSiempre);
      final j0 = p.jugador('j0')!;
      final j1 = p.jugador('j1')!;
      bloquear(j0, Random(1));
      p.tiempoAgotado();
      expect(j0.estado, EstadoJugador.terminado);
      expect(p.terminada, isFalse);
      bloquear(j1, Random(2));
      expect(j1.puntos, j0.puntos);
      p.tirar('j1');
      p.pasar('j1');
      expect(p.terminada, isTrue);
      expect(p.resultado!.ganadores.toSet(), {'j0', 'j1'});
    });

    test('el terminado con menos puntos no gana aunque el último le gane', () {
      final p = crear(unosSiempre);
      final j0 = p.jugador('j0')!;
      final j1 = p.jugador('j1')!;
      bloquearIncompleto(j0, Random(1));
      p.tiempoAgotado();
      expect(j0.estado, EstadoJugador.terminado);
      bloquear(j1, Random(2));
      expect(j1.puntos, greaterThan(j0.puntos));
      p.tirar('j1');
      p.pasar('j1');
      expect(p.resultado!.ganadores, ['j1']);
    });

    test('una tirada sin movimientos no termina el tablero', () {
      // Mapa 1 (Nivel 2) con 1..6 en orden: con 3 y 3 no hay jugada, pero con
      // otras parejas de dados sí.
      final p = crear([2, 2, 0, 1], mapa: 1);
      p.tirar('j0');
      expect(p.dados, [3, 3]);
      expect(p.hayMovimientosConLosDados('j0'), isFalse);
      expect(p.jugador('j0')!.quedanMovimientos, isTrue);
      p.pasar('j0');
      expect(p.jugador('j0')!.estado, EstadoJugador.jugando);
      expect(p.terminada, isFalse);
      expect(p.turnoDe, 'j1');
      p.tirar('j1');
      p.pasarOcolocar();
      expect(p.turnoDe, 'j0', reason: 'j0 sigue recibiendo turnos');
    });

    test('terminado con más puntos gana aunque el otro termine después', () {
      final p = crear(unosSiempre);
      final j0 = p.jugador('j0')!;
      final j1 = p.jugador('j1')!;

      // j0 llena su tablero entero: sin jugadas posibles y con todos los puntos.
      bloquear(j0, Random(1));
      final puntosJ0 = j0.puntos;
      expect(j0.quedanMovimientos, isFalse);

      // Termina el turno de j0: al dar el siguiente se ve que no puede jugar.
      // j1 sigue en juego.
      p.tiempoAgotado();
      expect(j0.estado, EstadoJugador.terminado);
      expect(j0.participa, isTrue);
      expect(j1.estado, EstadoJugador.jugando);
      expect(p.terminada, isFalse);
      expect(p.turnoDe, 'j1');
      expect(() => p.tirar('j0'), throwsA(isA<ErrorJuego>()));

      // Después j1 también se queda sin jugadas, pero con un área sin
      // completar: tiene menos puntos.
      bloquearIncompleto(j1, Random(2));
      expect(j1.quedanMovimientos, isFalse);
      expect(j1.puntos, lessThan(puntosJ0));
      p.tirar('j1');
      p.pasar('j1');
      expect(j1.estado, EstadoJugador.terminado);
      expect(p.terminada, isTrue);
      expect(p.resultado!.motivo, MotivoFin.todosTerminaron);
      // El último en jugar no gana automáticamente: gana quien más puntos tiene.
      expect(p.resultado!.ganadores, ['j0']);
      expect(j0.puntos, puntosJ0);
    });

    test('quien termina primero se salta y conserva sus puntos (simulado)', () {
      var vistos = 0;
      for (var mapa = 0; mapa < mapasOficiales.length; mapa++) {
        for (var semilla = 0; semilla < 40; semilla++) {
          final azar = Random(semilla * 7 + mapa);
          final p = azarosa(mapa, 2, semilla);
          JugadorPartida? primero;
          var puntosAlTerminar = 0;
          var pasos = 0;
          while (!p.terminada) {
            expect(++pasos, lessThan(20000));
            jugarTurno(p, azar);
            if (primero == null) {
              final t = p.jugadores
                  .where((j) => j.estado == EstadoJugador.terminado)
                  .firstOrNull;
              if (t != null && !p.terminada) {
                primero = t;
                puntosAlTerminar = t.puntos;
                vistos++;
                // No está retirado, y la partida sigue para el otro.
                expect(t.participa, isTrue);
              }
            } else {
              // Ya no recibe turnos ni cambia su puntuación.
              expect(p.turnoDe, isNot(primero.id));
              expect(primero.puntos, puntosAlTerminar);
              expect(primero.estado, EstadoJugador.terminado);
            }
          }
          final r = p.resultado!;
          expect(r.motivo, MotivoFin.todosTerminaron);
          final mejor = p.jugadores.map((j) => j.puntos).reduce(max);
          expect(r.ganadores.toSet(), {
            for (final j in p.jugadores)
              if (j.puntos == mejor) j.id,
          });
          for (final j in p.jugadores) {
            expect(j.estado, EstadoJugador.terminado);
          }
        }
      }
      expect(
        vistos,
        greaterThan(0),
        reason: 'hubo jugadores que terminaron antes',
      );
    });

    test('se rinde el único que sigue jugando: gana el que ya terminó', () {
      for (var semilla = 0; semilla < 200; semilla++) {
        final azar = Random(semilla);
        final p = azarosa(3, 3, semilla);
        var pasos = 0;
        while (!p.terminada) {
          expect(++pasos, lessThan(20000));
          jugarTurno(p, azar);
          final terminados = p.jugadores
              .where((j) => j.estado == EstadoJugador.terminado)
              .toList();
          final jugando = p.jugadores
              .where((j) => j.estado == EstadoJugador.jugando)
              .toList();
          if (!p.terminada && terminados.length == 1 && jugando.length == 2) {
            // Se rinde uno de los dos que juegan: quedan dos elegibles.
            p.conceder(jugando.first.id);
            expect(p.terminada, isFalse);
            // Y se rinde el otro: queda solo el terminado, que gana.
            p.conceder(jugando.last.id);
            expect(p.terminada, isTrue);
            expect(p.resultado!.ganadores, [terminados.single.id]);
            expect(p.resultado!.motivo, MotivoFin.rendicion);
            return;
          }
        }
      }
      fail('no se encontró la situación buscada');
    });

    test('rendirse no termina la partida si quedan dos elegibles', () {
      final p = crear([], jugadores: 3);
      p.conceder('j2');
      expect(p.terminada, isFalse);
      expect(p.jugador('j2')!.puntos, 0);
    });

    test('empate en la puntuación máxima: comparten la victoria', () {
      var empates = 0;
      for (var semilla = 0; semilla < 300 && empates == 0; semilla++) {
        final azar = Random(semilla);
        final p = azarosa(0, 2, semilla);
        while (!p.terminada) {
          jugarTurno(p, azar);
        }
        if (p.jugadores[0].puntos == p.jugadores[1].puntos) {
          empates++;
          expect(p.resultado!.ganadores, hasLength(2));
          expect(p.mensaje, contains('Empate'));
        }
      }
      expect(empates, greaterThan(0), reason: 'se encontró un empate');
    });
  });

  group('Partidas completas simuladas', () {
    for (var mapa = 0; mapa < mapasOficiales.length; mapa++) {
      for (final n in [2, 3, 4]) {
        test('mapa $mapa con $n jugadores termina de forma coherente', () {
          for (var semilla = 0; semilla < 8; semilla++) {
            final azar = Random(semilla * 31 + n);
            final p = azarosa(mapa, n, semilla);
            var pasos = 0;
            while (!p.terminada) {
              expect(++pasos, lessThan(20000), reason: 'no termina');
              jugarTurno(p, azar);
            }
            final r = p.resultado!;
            expect(r.motivo, MotivoFin.todosTerminaron);
            final mejor = p.jugadores.map((j) => j.puntos).reduce(max);
            expect(r.ganadores, isNotEmpty);
            for (final g in r.ganadores) {
              expect(p.jugador(g)!.puntos, mejor);
            }
            for (final j in p.jugadores) {
              expect(j.estado, EstadoJugador.terminado);
              expect(j.quedanMovimientos, isFalse);
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
      final d = destinos(id, pos);
      if (d.isNotEmpty) {
        colocar(id, d.first, pos);
        return;
      }
    }
    pasar(id);
  }
}
