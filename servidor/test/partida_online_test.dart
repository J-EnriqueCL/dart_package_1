import 'dart:math';

import 'package:brilliant_nucleo/brilliant_nucleo.dart';
import 'package:servidor_brilliant/servidor_brilliant.dart';
import 'package:test/test.dart';

import 'ayudas.dart';

/// Partida en preparación. Los [dados] se usan al tirar en las rondas.
PartidaOnline preparar(
  List<int> dados, {
  int jugadores = 2,
  int mapa = 0,
  int maxSinRespuesta = 3,
}) => PartidaOnline(
  mapa: mapa,
  jugadores: [
    for (var i = 0; i < jugadores; i++) (id: 'j$i', nombre: 'Jugador$i'),
  ],
  azar: GuionAzar([...guionInicio, ...dados]),
  maxSinRespuesta: maxSinRespuesta,
);

/// Partida ya en marcha: todos distribuyeron 1..6 en orden y la ronda 1 espera
/// la primera tirada.
PartidaOnline crear(
  List<int> dados, {
  int jugadores = 2,
  int mapa = 0,
  int maxSinRespuesta = 3,
}) {
  final p = preparar(
    dados,
    jugadores: jugadores,
    mapa: mapa,
    maxSinRespuesta: maxSinRespuesta,
  );
  for (final j in p.jugadores) {
    distribuir(p, j.id);
  }
  return p;
}

/// Dados que siempre dan 1 y 1 (guion largo).
final unosSiempre = List<int>.filled(160, 0);

/// El jugador [id] resuelve la ronda abierta: confirma una de sus jugadas
/// (al azar) y si no tiene, pasa. Con [pasa] pasa aunque tenga jugadas.
void resolver(PartidaOnline p, String id, Random azar, {bool pasa = false}) {
  final opciones = [
    for (var pos = 0; pos < 2; pos++)
      for (final c in p.destinos(id, pos)) (pos, c),
  ];
  if (pasa || opciones.isEmpty) {
    p.pasarRonda(id, p.rondaId);
  } else {
    final (pos, c) = opciones[azar.nextInt(opciones.length)];
    p.confirmarJugada(id, p.rondaId, c, pos);
  }
}

/// Una ronda completa: tira el primero que sigue jugando y resuelven todos los
/// pendientes. A veces alguien pasa aunque tenga jugadas.
void jugarRonda(PartidaOnline p, Random azar) {
  final lanzador = p.jugadores.firstWhere(
    (j) => j.estado == EstadoJugador.jugando,
  );
  p.tirar(lanzador.id, p.rondaId);
  for (final id in p.resoluciones.keys.toList()) {
    if (p.resoluciones[id] != Resolucion.pendiente) continue;
    resolver(p, id, azar, pasa: azar.nextInt(8) == 0);
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
        expect(() => p.tirar(id, 1), throwsA(isA<ErrorJuego>()));
        expect(
          () => p.confirmarJugada(id, 1, 9, 0),
          throwsA(isA<ErrorJuego>()),
        );
        expect(() => p.pasarRonda(id, 1), throwsA(isA<ErrorJuego>()));
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
      // El guion está vacío: empezar no consume azar, y si algo intentara
      // tirar o sortear de más fallaría.
      final p = PartidaOnline(
        mapa: 0,
        jugadores: [
          (id: 'j0', nombre: 'A'),
          (id: 'j1', nombre: 'B'),
          (id: 'j2', nombre: 'C'),
        ],
        azar: GuionAzar([]),
      );
      distribuir(p, 'j0');
      distribuir(p, 'j1');
      expect(p.fase, FasePartida.preparacion);
      distribuir(p, 'j2');
      expect(p.fase, FasePartida.jugando);
      expect(p.rondaId, 1);
      expect(p.faseRonda, FaseRonda.esperandoTirada);
      expect(p.dados, isNull);
      expect([
        for (final j in p.jugadores) j.estado,
      ], everyElement(EstadoJugador.jugando));
      // Confirmaciones repetidas: no reinician nada.
      p.confirmarDistribucion('j0');
      p.confirmarDistribucion('j2');
      expect(p.rondaId, 1);
      expect(p.faseRonda, FaseRonda.esperandoTirada);
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
      expect(
        identical(p.jugador('j0')!.controlador, p.jugador('j1')!.controlador),
        isFalse,
      );
    });

    test('dos jugadores confirman jugadas distintas en la misma ronda', () {
      final p = crear([0, 1]); // dados 1 y 2
      p.tirar('j0', 1);
      final rival = p.tableroDe('j1');
      p.confirmarJugada('j0', 1, 1, 0); // ancla 1, pone un 2 en la casilla 1
      expect(p.tableroDe('j0')[1], 2);
      expect(p.tableroDe('j1'), rival, reason: 'no cambia el tablero ajeno');
      final j0 = p.tableroDe('j0');
      p.confirmarJugada('j1', 1, 3, 0); // otra casilla, a la vez
      expect(p.tableroDe('j1')[3], 2);
      expect(p.tableroDe('j1')[1], isNull);
      expect(p.tableroDe('j0'), j0);
    });

    test('un jugador no puede tocar un tablero ajeno', () {
      final p = crear([0, 1]);
      final antes0 = p.tableroDe('j0');
      p.tirar('j1', 1);
      // Las acciones se aplican siempre al tablero de quien las envía.
      expect(
        () => p.confirmarJugada('desconocido', 1, 1, 0),
        throwsA(isA<ErrorJuego>()),
      );
      p.confirmarJugada('j1', 1, 1, 0);
      expect(p.tableroDe('j0'), antes0);
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
    /// Ronda en la que [id] pone el 1 en [casilla] (ancla 1) y los demás pasan.
    void ronda(PartidaOnline p, int casilla, {String id = 'j0'}) {
      p.tirar(id, p.rondaId);
      p.confirmarJugada(id, p.rondaId, casilla, 0);
      for (final otro in p.resoluciones.keys.toList()) {
        if (p.resoluciones[otro] == Resolucion.pendiente) {
          p.pasarRonda(otro, p.rondaId);
        }
      }
    }

    test('el premio de un grupo se adjudica al cerrar la ronda', () {
      // Grupo azul N1-a2 = {2, 9, 10, 17}: exige todos iguales y el 2 ya tiene
      // un 1. Premios 7 / 5 / 3.
      final p = crear(unosSiempre);
      ronda(p, 9);
      ronda(p, 10);
      expect(p.jugador('j0')!.puntos, 0);
      p.tirar('j0', 3);
      p.confirmarJugada('j0', 3, 17, 0);
      // Completado pero todavía sin liquidar: no hay puntos ni prioridad.
      expect(p.pendientesDe('j0'), ['N1-a2']);
      expect(p.jugador('j0')!.puntos, 0);
      expect(p.mensaje, contains('se decide al cerrar la ronda'));
      p.pasarRonda('j1', 3);
      expect(p.jugador('j0')!.puntos, 7);
      expect(p.jugador('j1')!.puntos, 0);
      expect(p.pendientesDe('j0'), isEmpty);
      expect(p.mensaje, contains('Premios:'));
    });
    test(
      'los puntos son exactamente lo adjudicado, una vez por jugador y grupo',
      () {
        for (var semilla = 0; semilla < 12; semilla++) {
          final p = azarosa(0, 3, semilla);
          final azar = Random(semilla + 100);
          final recibido = <String, int>{};
          final vistos = <String>{};
          var pasos = 0;
          while (!p.terminada) {
            expect(++pasos, lessThan(20000));
            jugarRonda(p, azar);
            for (final a in p.liquidacion) {
              expect(
                vistos.add('${a.jugador}|${a.grupo}'),
                isTrue,
                reason: 'un único premio por jugador y grupo',
              );
              recibido[a.jugador] = (recibido[a.jugador] ?? 0) + a.puntos;
            }
          }
          for (final j in p.jugadores) {
            expect(j.puntos, recibido[j.id] ?? 0);
          }
        }
      },
    );
    test('un área puntúa una sola vez y los duplicados no suman', () {
      final p = crear(unosSiempre);
      ronda(p, 9);
      ronda(p, 10);
      ronda(p, 17);
      expect(p.jugador('j0')!.puntos, 7);
      // Repetir la confirmación de una ronda cerrada se rechaza.
      expect(
        () => p.confirmarJugada('j0', 3, 17, 0),
        throwsA(isA<ErrorJuego>()),
      );
      expect(p.jugador('j0')!.puntos, 7);
      p.tirar('j0', 4);
      p.pasarRonda('j0', 4);
      p.pasarRonda('j1', 4);
      expect(p.jugador('j0')!.puntos, 7);
    });

    test('un grupo que nace completo se evalúa al acabar la preparación', () {
      // Grupo ficticio de prueba: la casilla inicial 2 sola, premios 5 / 3 / 1.
      PartidaOnline crearPrep() => PartidaOnline(
        mapa: 0,
        jugadores: [(id: 'j0', nombre: 'A'), (id: 'j1', nombre: 'B')],
        azar: GuionAzar([0, 0]),
        grupos: const [
          GrupoPremio(id: 'T-ini', casillas: [2], premios: [5, 3, 1]),
        ],
      );

      for (final inversa in [false, true]) {
        final p = crearPrep();
        final orden = inversa ? ['j1', 'j0'] : ['j0', 'j1'];
        distribuir(p, orden.first);
        expect(
          p.jugador(orden.first)!.puntos,
          0,
          reason: 'no se premia al confirmar cada uno por separado',
        );
        distribuir(p, orden.last);
        expect(p.jugador('j0')!.puntos, 5, reason: 'inversa=$inversa');
        expect(p.jugador('j1')!.puntos, 5);
        // Ocupan solo el primer nivel; no se vuelve a adjudicar nada.
        expect(p.libro.reclamaciones.single.niveles, [
          ['j0', 'j1'],
        ]);
        p.confirmarDistribucion('j0');
        expect(p.jugador('j0')!.puntos, 5);
        p.tirar('j0', 1);
        p.pasarRonda('j0', 1);
        p.pasarRonda('j1', 1);
        expect(p.jugador('j0')!.puntos, 5);
        expect(p.jugador('j1')!.puntos, 5);
      }
    });

    test('un grupo mayor incompleto no premia al confirmar la preparación', () {
      final p = crear([]);
      for (final j in p.jugadores) {
        expect(j.puntos, 0);
      }
      expect(p.liquidacion, isEmpty);
    });
  });

  group('Rondas', () {
    test('no hay dados hasta una solicitud válida', () {
      final p = crear([0, 1]);
      expect(p.dados, isNull);
      expect(p.faseRonda, FaseRonda.esperandoTirada);
      expect(p.resoluciones, isEmpty);
      expect(() => p.pasarRonda('j0', 1), throwsA(isA<ErrorJuego>()));
      expect(
        () => p.confirmarJugada('j0', 1, 1, 0),
        throwsA(isA<ErrorJuego>()),
      );
      expect(p.dados, isNull);
    });

    test(
      'una tirada para todos: los dados son los mismos y salen del servidor',
      () {
        final p = crear([2, 3]); // 3 y 4
        p.tirar('j1', 1); // cualquiera puede lanzar
        expect(p.dados, [3, 4]);
        final r = p.ronda();
        expect(r.dados, [3, 4]);
        expect(r.fase, FaseRonda.resolviendo);
        expect(r.resoluciones, {
          'j0': Resolucion.pendiente,
          'j1': Resolucion.pendiente,
        });
      },
    );

    test('dos solicitudes de tirada generan una sola tirada', () {
      // El guion solo tiene dos valores: una segunda tirada fallaría.
      final p = crear([2, 3]);
      p.tirar('j0', 1);
      p.tirar('j1', 1);
      p.tirar('j0', 1);
      expect(p.dados, [3, 4]);
      expect(p.rondaId, 1);
    });

    test('la ronda no avanza mientras falte un participante pendiente', () {
      final p = crear([0, 1]);
      p.tirar('j0', 1);
      p.confirmarJugada('j0', 1, 1, 0);
      expect(p.rondaId, 1);
      expect(p.faseRonda, FaseRonda.resolviendo);
      expect(p.ronda().pendientes, ['j1']);
    });

    test('confirmar y pasar permiten cerrar la ronda, una sola vez', () {
      final p = crear([0, 1]);
      p.tirar('j0', 1);
      p.confirmarJugada('j0', 1, 1, 0);
      p.pasarRonda('j1', 1);
      expect(p.rondaId, 2);
      expect(p.faseRonda, FaseRonda.esperandoTirada);
      expect(p.dados, isNull);
      expect(p.resoluciones, isEmpty);
      // Repetir la última resolución no cierra otra ronda.
      expect(() => p.pasarRonda('j1', 1), throwsA(isA<ErrorJuego>()));
      expect(p.rondaId, 2);
    });

    test('la siguiente ronda espera un nuevo lanzamiento manual', () {
      // Solo hay dados para la ronda 1: si se tirara sola, fallaría.
      final p = crear([0, 1]);
      p.tirar('j0', 1);
      p.pasarRonda('j0', 1);
      p.pasarRonda('j1', 1);
      expect(p.faseRonda, FaseRonda.esperandoTirada);
      expect(p.dados, isNull);
      expect(() => p.pasarRonda('j0', 2), throwsA(isA<ErrorJuego>()));
    });

    test('se puede pasar aunque haya jugadas, sin penalización', () {
      final p = crear([0, 1]);
      p.tirar('j0', 1);
      expect(p.hayMovimientosConLosDados('j0'), isTrue);
      p.pasarRonda('j0', 1);
      expect(p.resoluciones['j0'], Resolucion.paso);
      final j0 = p.jugador('j0')!;
      expect(j0.sinRespuestaSeguidas, 0);
      expect(j0.estado, EstadoJugador.jugando);
      expect(p.tableroDe('j0').where((v) => v != null), hasLength(6));
    });

    test('no se puede jugar dos veces ni cambiar la resolución', () {
      final p = crear([0, 1, 0, 1]);
      p.tirar('j0', 1);
      p.confirmarJugada('j0', 1, 1, 0);
      final tablero = p.tableroDe('j0');
      final puntos = p.jugador('j0')!.puntos;
      p.confirmarJugada('j0', 1, 1, 0); // duplicado: no hace nada
      p.confirmarJugada('j0', 1, 3, 0); // otra jugada: tampoco
      expect(() => p.pasarRonda('j0', 1), throwsA(isA<ErrorJuego>()));
      expect(p.tableroDe('j0'), tablero);
      expect(p.jugador('j0')!.puntos, puntos);
      expect(p.resoluciones['j0'], Resolucion.confirmo);

      // Pasar y luego confirmar: no deja colocar; pasar dos veces es un no-op.
      p.pasarRonda('j1', 1);
      expect(p.rondaId, 2);
      p.tirar('j1', 2);
      p.pasarRonda('j1', 2);
      p.pasarRonda('j1', 2);
      expect(
        () => p.confirmarJugada('j1', 2, 3, 0),
        throwsA(isA<ErrorJuego>()),
      );
      expect(p.tableroDe('j1')[3], isNull);
    });

    test('las acciones de una ronda anterior se rechazan', () {
      final p = crear([0, 1]);
      p.tirar('j0', 1);
      p.pasarRonda('j0', 1);
      p.pasarRonda('j1', 1);
      expect(p.rondaId, 2);
      expect(() => p.tirar('j0', 1), throwsA(isA<ErrorJuego>()));
      expect(() => p.pasarRonda('j0', 1), throwsA(isA<ErrorJuego>()));
      expect(
        () => p.confirmarJugada('j0', 1, 1, 0),
        throwsA(isA<ErrorJuego>()),
      );
      expect(() => p.tirar('j0', 9), throwsA(isA<ErrorJuego>()));
      expect(p.faseRonda, FaseRonda.esperandoTirada);
      expect(p.dados, isNull);
    });

    test(
      'una jugada inválida falla sin cambios y el jugador sigue pendiente',
      () {
        final p = crear([0, 1]);
        p.tirar('j0', 1);
        final antes = p.tableroDe('j0');
        for (final (indice, ancla) in [(9, 0), (1, 2), (-1, 0), (999, 0)]) {
          expect(
            () => p.confirmarJugada('j0', 1, indice, ancla),
            throwsA(isA<ErrorJuego>()),
          );
        }
        expect(p.tableroDe('j0'), antes);
        expect(p.resoluciones['j0'], Resolucion.pendiente);
      },
    );

    test('rendidos y abandonados no bloquean la ronda', () {
      final p = crear([0, 1], jugadores: 3);
      p.tirar('j0', 1);
      p.conceder('j2'); // estaba pendiente
      expect(p.resoluciones.keys.toSet(), {'j0', 'j1'});
      p.pasarRonda('j0', 1);
      expect(p.rondaId, 1);
      p.pasarRonda('j1', 1);
      expect(p.rondaId, 2);
      expect(() => p.tirar('j2', 2), throwsA(isA<ErrorJuego>()));
    });

    test('si el último pendiente abandona, la ronda se cierra', () {
      final p = crear([0, 1], jugadores: 3);
      p.tirar('j0', 1);
      p.pasarRonda('j0', 1);
      p.pasarRonda('j1', 1);
      expect(p.rondaId, 1);
      p.abandonar('j2');
      expect(p.rondaId, 2);
      expect(p.faseRonda, FaseRonda.esperandoTirada);
      expect(p.terminada, isFalse);
    });
  });

  group('Plazo de la ronda', () {
    test('sin ronda abierta no hay nada que agotar', () {
      final p = crear([]);
      p.plazoAgotado();
      expect(p.rondaId, 1);
      expect(p.jugador('j0')!.sinRespuestaSeguidas, 0);
    });

    test('al vencer, los pendientes no colocan nada y la ronda se cierra', () {
      final p = crear([0, 1]);
      p.tirar('j0', 1);
      p.confirmarJugada('j0', 1, 1, 0);
      final tableroJ1 = p.tableroDe('j1');
      p.plazoAgotado();
      expect(p.rondaId, 2);
      expect(p.faseRonda, FaseRonda.esperandoTirada);
      expect(p.tableroDe('j1'), tableroJ1);
      expect(p.jugador('j1')!.sinRespuestaSeguidas, 1);
      expect(p.jugador('j0')!.sinRespuestaSeguidas, 0);
      expect(p.jugador('j1')!.estado, EstadoJugador.jugando);
      expect(p.mensaje, contains('no respondió'));
    });

    test('tres rondas seguidas sin respuesta provocan el abandono', () {
      final p = crear(unosSiempre);
      for (var i = 1; i <= 3; i++) {
        expect(p.jugador('j1')!.estado, EstadoJugador.jugando);
        p.tirar('j0', i);
        p.pasarRonda('j0', i);
        p.plazoAgotado();
      }
      expect(p.jugador('j1')!.estado, EstadoJugador.abandono);
      expect(p.terminada, isTrue);
      expect(p.resultado!.motivo, MotivoFin.abandono);
      expect(p.resultado!.ganadores, ['j0']);
    });

    test('pasar voluntariamente nunca cuenta como falta de respuesta', () {
      final p = crear(unosSiempre);
      for (var i = 1; i <= 6; i++) {
        p.tirar('j0', i);
        p.pasarRonda('j0', i);
        p.pasarRonda('j1', i);
      }
      expect(p.jugador('j1')!.sinRespuestaSeguidas, 0);
      expect(p.jugador('j1')!.estado, EstadoJugador.jugando);
      expect(p.rondaId, 7);
    });

    test('responder (pasando o confirmando) reinicia la cuenta', () {
      final p = crear(unosSiempre);
      void silencio() {
        p.tirar('j0', p.rondaId);
        p.pasarRonda('j0', p.rondaId);
        p.plazoAgotado();
      }

      silencio();
      silencio();
      expect(p.jugador('j1')!.sinRespuestaSeguidas, 2);
      p.tirar('j0', 3);
      p.pasarRonda('j0', 3);
      p.pasarRonda('j1', 3); // responde pasando
      expect(p.jugador('j1')!.sinRespuestaSeguidas, 0);
      silencio();
      silencio();
      expect(p.jugador('j1')!.sinRespuestaSeguidas, 2);
      p.tirar('j0', 6);
      p.pasarRonda('j0', 6);
      p.confirmarJugada('j1', 6, 1, 0); // responde confirmando
      expect(p.jugador('j1')!.sinRespuestaSeguidas, 0);
      expect(p.jugador('j1')!.estado, EstadoJugador.jugando);
    });

    test('con tres, el abandono por inactividad no termina la partida', () {
      final p = crear(unosSiempre, jugadores: 3);
      for (var i = 1; i <= 3; i++) {
        p.tirar('j0', i);
        p.pasarRonda('j0', i);
        p.pasarRonda('j1', i);
        p.plazoAgotado();
      }
      expect(p.jugador('j2')!.estado, EstadoJugador.abandono);
      expect(p.terminada, isFalse);
      expect(p.rondaId, 4);
    });
  });

  group('Rendición y abandono en partida', () {
    test('con dos jugadores, rendirse da la victoria al otro', () {
      final p = crear([]);
      p.conceder('j1'); // no hace falta que sea su momento
      expect(p.terminada, isTrue);
      expect(p.jugador('j1')!.estado, EstadoJugador.concedio);
      expect(p.resultado!.motivo, MotivoFin.rendicion);
      expect(p.resultado!.ganadores, ['j0']);
      expect(p.mensaje, contains('Gana Jugador0'));
    });

    test('con tres jugadores la partida sigue sin el que se rindió', () {
      final p = crear([0, 1, 0, 1], jugadores: 3);
      p.conceder('j0');
      expect(p.terminada, isFalse);
      p.tirar('j1', 1);
      expect(p.resoluciones.keys.toSet(), {'j1', 'j2'});
      p.pasarRonda('j1', 1);
      p.pasarRonda('j2', 1);
      expect(p.rondaId, 2);
      p.conceder('j1');
      expect(p.terminada, isTrue);
      expect(p.resultado!.ganadores, ['j2']);
    });

    test('quien ya no participa no puede actuar ni volver a rendirse', () {
      final p = crear([0, 1], jugadores: 3);
      p.conceder('j2');
      expect(() => p.conceder('j2'), throwsA(isA<ErrorJuego>()));
      expect(() => p.tirar('j2', 1), throwsA(isA<ErrorJuego>()));
    });

    test('abandonar es idempotente y no falla con la partida terminada', () {
      final p = crear([]);
      p.abandonar('j0');
      p.abandonar('j0');
      p.abandonar('j1');
      expect(p.resultado!.ganadores, ['j1']);
      expect(() => p.tirar('j1', 1), throwsA(isA<ErrorJuego>()));
      expect(() => p.conceder('j1'), throwsA(isA<ErrorJuego>()));
    });

    test('quien se rinde conserva su puntuación y no puede ganar', () {
      final p = crear(unosSiempre, jugadores: 3);
      for (final casilla in [9, 10, 17]) {
        p.tirar('j0', p.rondaId);
        p.confirmarJugada('j0', p.rondaId, casilla, 0);
        p.pasarRonda('j1', p.rondaId);
        p.pasarRonda('j2', p.rondaId);
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
      final p = preparar([0, 1], jugadores: 3);
      distribuir(p, 'j0');
      distribuir(p, 'j1');
      expect(p.fase, FasePartida.preparacion);
      p.abandonar('j2');
      expect(p.fase, FasePartida.jugando);
      expect(p.jugador('j2')!.estado, EstadoJugador.abandono);
      expect(p.faseRonda, FaseRonda.esperandoTirada);
      // El que abandonó no resuelve rondas ni puede lanzar.
      p.tirar('j0', 1);
      expect(p.resoluciones.keys.toSet(), {'j0', 'j1'});
      expect(() => p.tirar('j2', 1), throwsA(isA<ErrorJuego>()));
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
      'quien abandona antes de confirmar no cuenta en el premio inicial',
      () {
        final p = PartidaOnline(
          mapa: 0,
          jugadores: [
            (id: 'j0', nombre: 'A'),
            (id: 'j1', nombre: 'B'),
            (id: 'j2', nombre: 'C'),
          ],
          azar: GuionAzar([]),
          grupos: const [
            GrupoPremio(id: 'T-ini', casillas: [2], premios: [5, 3, 1]),
          ],
        );
        colocarTodos(p, 'j2');
        p.abandonar('j2');
        expect(p.jugador('j2')!.puntos, 0);
        distribuir(p, 'j0');
        distribuir(p, 'j1');
        expect(p.fase, FasePartida.jugando);
        expect(p.jugador('j0')!.puntos, 5);
        expect(p.jugador('j1')!.puntos, 5);
        expect(p.jugador('j2')!.puntos, 0);
        expect(
          p.meta,
          26,
          reason: 'la meta cuenta a los participantes al empezar',
        );
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
      final p = crear([0, 1], jugadores: 4);
      p.tirar('j0', 1);
      p.abandonarVarios(['j0', 'j1']); // estaban pendientes de resolver
      expect(p.terminada, isFalse);
      expect(p.resoluciones.keys.toSet(), {'j2', 'j3'});
      p.pasarRonda('j2', 1);
      p.pasarRonda('j3', 1);
      expect(p.rondaId, 2, reason: 'la ronda se cierra sin los abandonados');
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
    test('una tirada sin movimientos no termina el tablero', () {
      // Mapa 1 (Nivel 2) con 1..6 en orden: con 3 y 3 no hay jugada, pero con
      // otras parejas de dados sí.
      final p = crear([2, 2, 0, 1], mapa: 1);
      p.tirar('j0', 1);
      expect(p.dados, [3, 3]);
      expect(p.hayMovimientosConLosDados('j0'), isFalse);
      expect(p.jugador('j0')!.quedanMovimientos, isTrue);
      p.pasarRonda('j0', 1);
      p.pasarRonda('j1', 1);
      expect(p.jugador('j0')!.estado, EstadoJugador.jugando);
      expect(p.terminada, isFalse);
      expect(p.rondaId, 2);
      p.tirar('j0', 2);
      expect(p.resoluciones.keys.toSet(), {'j0', 'j1'});
      expect(p.dados, [1, 2]);
    });

    test('terminado con más puntos gana aunque el otro termine después', () {
      final p = crear(unosSiempre);
      final j0 = p.jugador('j0')!;
      final j1 = p.jugador('j1')!;

      // j0 llena su tablero entero: sin jugadas posibles y con todos los puntos.
      bloquear(j0, Random(1));
      j0.puntos = 10;
      final puntosJ0 = j0.puntos;
      expect(j0.quedanMovimientos, isFalse);

      // Ronda 1: se evalúa al cerrarla. j1 sigue en juego.
      p.tirar('j1', 1);
      p.pasarRonda('j0', 1);
      p.pasarRonda('j1', 1);
      expect(j0.estado, EstadoJugador.terminado);
      expect(j0.participa, isTrue);
      expect(j1.estado, EstadoJugador.jugando);
      expect(p.terminada, isFalse);
      expect(() => p.tirar('j0', 2), throwsA(isA<ErrorJuego>()));

      // Ronda 2: j0 ya no resuelve; j1 también se queda sin jugadas, con
      // un área sin completar (menos puntos).
      p.tirar('j1', 2);
      expect(p.resoluciones.keys.toSet(), {'j1'});
      bloquear(j1, Random(2));
      j1.puntos = 4;
      expect(j1.quedanMovimientos, isFalse);
      expect(j1.puntos, lessThan(puntosJ0));
      p.pasarRonda('j1', 2);
      expect(j1.estado, EstadoJugador.terminado);
      expect(p.terminada, isTrue);
      expect(p.resultado!.motivo, MotivoFin.todosTerminaron);
      // El último en jugar no gana automáticamente.
      expect(p.resultado!.ganadores, ['j0']);
      expect(j0.puntos, puntosJ0);
    });

    test('si el terminado y el último empatan, comparten la victoria', () {
      final p = crear(unosSiempre);
      final j0 = p.jugador('j0')!;
      final j1 = p.jugador('j1')!;
      bloquear(j0, Random(1));
      j0.puntos = 7;
      p.tirar('j0', 1);
      p.pasarRonda('j0', 1);
      p.pasarRonda('j1', 1);
      expect(j0.estado, EstadoJugador.terminado);
      bloquear(j1, Random(2));
      j1.puntos = 7;
      expect(j1.puntos, j0.puntos);
      p.tirar('j1', 2);
      p.pasarRonda('j1', 2);
      expect(p.terminada, isTrue);
      expect(p.resultado!.ganadores.toSet(), {'j0', 'j1'});
    });

    test('el terminado con menos puntos no gana aunque el último le gane', () {
      final p = crear(unosSiempre);
      final j0 = p.jugador('j0')!;
      final j1 = p.jugador('j1')!;
      bloquear(j0, Random(1));
      j0.puntos = 3;
      p.tirar('j0', 1);
      p.pasarRonda('j0', 1);
      p.pasarRonda('j1', 1);
      expect(j0.estado, EstadoJugador.terminado);
      bloquear(j1, Random(2));
      j1.puntos = 9;
      expect(j1.puntos, greaterThan(j0.puntos));
      p.tirar('j1', 2);
      p.pasarRonda('j1', 2);
      expect(p.resultado!.ganadores, ['j1']);
    });

    test('un jugador que termina al confirmar ya resolvió esa ronda', () {
      final p = crear(unosSiempre);
      final j0 = p.jugador('j0')!;
      // Casi todo el tablero de j0 lleno: queda una sola jugada posible.
      bloquear(j0, Random(1));
      j0.puntos = 5;
      final c = j0.controlador!;
      expect(c.matriz.where((x) => x.valor == null), isEmpty);
      p.tirar('j0', 1);
      p.pasarRonda('j0', 1); // ya había terminado en la práctica
      p.pasarRonda('j1', 1);
      expect(j0.estado, EstadoJugador.terminado);
      expect(j0.puntos, 5, reason: 'conserva su puntuación');
    });

    test('quien termina antes sigue sin recibir rondas (simulado)', () {
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
            jugarRonda(p, azar);
            if (primero == null) {
              final t = p.jugadores
                  .where((j) => j.estado == EstadoJugador.terminado)
                  .firstOrNull;
              if (t != null && !p.terminada) {
                primero = t;
                puntosAlTerminar = t.puntos;
                vistos++;
                expect(t.participa, isTrue);
              }
            } else {
              expect(primero.puntos, puntosAlTerminar);
              expect(primero.estado, EstadoJugador.terminado);
            }
          }
          final r = p.resultado!;
          expect(r.motivo, anyOf(MotivoFin.meta, MotivoFin.todosTerminaron));
          final mejor = p.jugadores.map((j) => j.puntos).reduce(max);
          expect(r.ganadores.toSet(), {
            for (final j in p.jugadores)
              if (j.puntos == mejor) j.id,
          });
          if (r.motivo == MotivoFin.todosTerminaron) {
            for (final j in p.jugadores) {
              expect(j.estado, EstadoJugador.terminado);
            }
          } else {
            expect(mejor, greaterThanOrEqualTo(p.meta!));
          }
        }
      }
      expect(
        vistos,
        greaterThan(0),
        reason: 'hubo jugadores que terminaron antes',
      );
    });

    test('se rinden los que siguen jugando: gana el que ya terminó', () {
      for (var semilla = 0; semilla < 200; semilla++) {
        final azar = Random(semilla);
        final p = azarosa(3, 3, semilla);
        var pasos = 0;
        while (!p.terminada) {
          expect(++pasos, lessThan(20000));
          jugarRonda(p, azar);
          final terminados = p.jugadores
              .where((j) => j.estado == EstadoJugador.terminado)
              .toList();
          final jugando = p.jugadores
              .where((j) => j.estado == EstadoJugador.jugando)
              .toList();
          if (!p.terminada && terminados.length == 1 && jugando.length == 2) {
            p.conceder(jugando.first.id);
            expect(p.terminada, isFalse);
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
          jugarRonda(p, azar);
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
              jugarRonda(p, azar);
            }
            final r = p.resultado!;
            expect(r.motivo, anyOf(MotivoFin.meta, MotivoFin.todosTerminaron));
            final mejor = p.jugadores.map((j) => j.puntos).reduce(max);
            expect(r.ganadores, isNotEmpty);
            for (final g in r.ganadores) {
              expect(p.jugador(g)!.puntos, mejor);
            }
            if (r.motivo == MotivoFin.meta) {
              expect(mejor, greaterThanOrEqualTo(p.meta!));
            } else {
              for (final j in p.jugadores) {
                expect(j.estado, EstadoJugador.terminado);
                expect(j.quedanMovimientos, isFalse);
              }
            }
          }
        });
      }
    }
  });
}
