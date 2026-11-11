import 'dart:convert';

import 'package:brilliant_nucleo/brilliant_nucleo.dart';
import 'package:test/test.dart';

EstadoSala ejemplo({FaseSala fase = FaseSala.jugando}) {
  final tablero = List<int?>.filled(49, null);
  var n = 1;
  for (final i in mapasOficiales.first.indicesIniciales) {
    tablero[i] = n++;
  }
  return EstadoSala(
    yo: 'a',
    codigo: 'ABC234',
    fase: fase,
    mapa: 0,
    maxJugadores: 4,
    anfitrion: 'a',
    jugadores: const [
      JugadorSala(id: 'a', nombre: 'Ana', conectado: true, puntos: 7),
      JugadorSala(
        id: 'b',
        nombre: 'Beto',
        conectado: false,
        estado: EstadoJugador.concedio,
        graciaRestante: 12,
      ),
    ],
    ronda: const RondaSala(
      id: 3,
      fase: FaseRonda.resolviendo,
      dados: [2, 5],
      resoluciones: {'a': Resolucion.pendiente, 'b': Resolucion.confirmo},
      segundos: 40,
    ),
    tablero: tablero,
    mensaje: 'Hola',
    resultado: const ResultadoPartida(
      ganadores: ['a'],
      motivo: MotivoFin.rendicion,
    ),
  );
}

void main() {
  test('el estado de una sala sobrevive a ir y volver por JSON', () {
    final e = ejemplo();
    final copia = EstadoSala.fromJson(
      (jsonDecode(jsonEncode(e.toJson())) as Map).cast<String, Object?>(),
    );
    expect(jsonEncode(copia.toJson()), jsonEncode(e.toJson()));
    expect(copia.dados, [2, 5]);
    expect(copia.ronda!.id, 3);
    expect(copia.ronda!.segundos, 40);
    expect(copia.estoyPendiente, isTrue);
    expect(copia.ronda!.pendientes, ['a']);
    expect(copia.miResolucion, Resolucion.pendiente);
    expect(copia.puedoTirar, isFalse);
    expect(copia.soyAnfitrion, isTrue);
    expect(copia.jugador('b')!.graciaRestante, 12);
    expect(copia.resultado!.motivo, MotivoFin.rendicion);
  });

  test('un lobby (sin tablero ni dados) también viaja bien', () {
    final e = EstadoSala(
      yo: 'a',
      codigo: 'ZZZ999',
      fase: FaseSala.lobby,
      mapa: 2,
      maxJugadores: 4,
      anfitrion: 'a',
      jugadores: const [JugadorSala(id: 'a', nombre: 'Ana', conectado: true)],
    );
    final copia = EstadoSala.fromJson(
      (jsonDecode(jsonEncode(e.toJson())) as Map).cast<String, Object?>(),
    );
    expect(copia.tablero, isEmpty);
    expect(copia.dados, isNull);
    expect(copia.estoyPendiente, isFalse);
    expect(copia.puedoTirar, isFalse);
    expect(copia.ronda, isNull);
  });

  test('crearControlador refleja las casillas ocupadas', () {
    final e = ejemplo();
    final tablero = [...e.tablero];
    tablero[1] = 2;
    final ctl = EstadoSala.fromJson({...e.toJson(), 'tablero': tablero})
        .crearControlador();
    expect(ctl.matriz[1].valor, 2);
    expect(ctl.matriz[2].valor, 1);
    expect(ctl.destinosPosibles(ancla: 1, colocar: 2), contains(3));
  });

  group('rechaza datos mal formados', () {
    final base = ejemplo().toJson();
    for (final cambio in <String, Object?>{
      'mapa': 99,
      'fase': 'otra',
      'tablero': [1, 2, 3],
      'ronda': {
        'id': 1,
        'fase': 'resolviendo',
        'dados': [1, 2, 3],
        'resoluciones': {},
      },
      'jugadores': 'no es una lista',
    }.entries) {
      test('${cambio.key} inválido', () {
        expect(
          () => EstadoSala.fromJson({...base, cambio.key: cambio.value}),
          throwsFormatException,
        );
      });
    }
    test('ronda con id inválido', () {
      expect(
        () => EstadoSala.fromJson({
          ...base,
          'ronda': {'id': 'uno', 'fase': 'esperandoTirada', 'resoluciones': {}},
        }),
        throwsFormatException,
      );
    });
    test('falta un campo', () {
      expect(
        () => EstadoSala.fromJson({...base}..remove('codigo')),
        throwsFormatException,
      );
    });
  });
  group('Ronda', () {
    EstadoSala conRonda(
      RondaSala? r, {
      EstadoJugador yo = EstadoJugador.jugando,
    }) => EstadoSala(
      yo: 'a',
      codigo: 'ABC234',
      fase: FaseSala.jugando,
      mapa: 0,
      maxJugadores: 4,
      anfitrion: 'a',
      jugadores: [
        JugadorSala(id: 'a', nombre: 'Ana', conectado: true, estado: yo),
        const JugadorSala(
          id: 'b',
          nombre: 'Beto',
          conectado: true,
          estado: EstadoJugador.jugando,
        ),
      ],
      ronda: r,
    );

    test('esperando tirada: pueden lanzar los que siguen jugando', () {
      const r = RondaSala(id: 2, fase: FaseRonda.esperandoTirada);
      expect(conRonda(r).puedoTirar, isTrue);
      expect(conRonda(r).dados, isNull);
      expect(conRonda(r).estoyPendiente, isFalse);
      for (final e in [
        EstadoJugador.terminado,
        EstadoJugador.concedio,
        EstadoJugador.abandono,
      ]) {
        expect(conRonda(r, yo: e).puedoTirar, isFalse, reason: '$e');
      }
    });

    test('con dados nadie lanza y quien no resolvió está pendiente', () {
      const r = RondaSala(
        id: 1,
        fase: FaseRonda.resolviendo,
        dados: [3, 4],
        resoluciones: {'a': Resolucion.pendiente, 'b': Resolucion.paso},
      );
      final e = conRonda(r);
      expect(e.puedoTirar, isFalse);
      expect(e.estoyPendiente, isTrue);
      expect(r.pendientes, ['a']);
      const hecho = RondaSala(
        id: 1,
        fase: FaseRonda.resolviendo,
        dados: [3, 4],
        resoluciones: {'a': Resolucion.confirmo, 'b': Resolucion.paso},
      );
      expect(conRonda(hecho).estoyPendiente, isFalse);
      expect(hecho.pendientes, isEmpty);
    });

    test('la ronda viaja por JSON con sus resoluciones', () {
      const r = RondaSala(
        id: 5,
        fase: FaseRonda.resolviendo,
        dados: [1, 6],
        resoluciones: {'a': Resolucion.confirmo, 'b': Resolucion.pendiente},
        segundos: 12,
      );
      final copia = RondaSala.fromJson(
        (jsonDecode(jsonEncode(r.toJson())) as Map).cast<String, Object?>(),
      );
      expect(jsonEncode(copia.toJson()), jsonEncode(r.toJson()));
      expect(() => Resolucion.desde('sinRespuesta'), throwsFormatException);
      expect(() => FaseRonda.desde('x'), throwsFormatException);
    });
  });
}
