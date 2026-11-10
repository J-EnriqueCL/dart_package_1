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
    turnoDe: 'a',
    turno: 3,
    dados: const [2, 5],
    tablero: tablero,
    mensaje: 'Hola',
    segundosTurno: 40,
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
    expect(copia.esMiTurno, isTrue);
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
    expect(copia.esMiTurno, isFalse);
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
      'dados': [1, 2, 3],
      'jugadores': 'no es una lista',
      'turno': 'tres',
    }.entries) {
      test('${cambio.key} inválido', () {
        expect(
          () => EstadoSala.fromJson({...base, cambio.key: cambio.value}),
          throwsFormatException,
        );
      });
    }
    test('falta un campo', () {
      expect(
        () => EstadoSala.fromJson({...base}..remove('codigo')),
        throwsFormatException,
      );
    });
  });
}
