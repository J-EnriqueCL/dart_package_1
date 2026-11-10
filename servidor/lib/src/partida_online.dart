import 'dart:math';

import 'package:brilliant_nucleo/brilliant_nucleo.dart';

/// Jugada o petición inválida; el mensaje se muestra tal cual al jugador.
class ErrorJuego implements Exception {
  ErrorJuego(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}

class JugadorPartida {
  JugadorPartida(this.id, this.nombre);

  final String id;
  final String nombre;
  int puntos = 0;
  EstadoJugador estado = EstadoJugador.activo;

  /// Turnos seguidos que se agotó el tiempo sin que jugara.
  int turnosAgotados = 0;

  bool get activo => estado == EstadoJugador.activo;
}

/// Partida por turnos sobre un único tablero compartido.
///
/// Cada turno: el jugador tira dos dados, elige uno como ancla y coloca el
/// otro número en una casilla vecina a un número igual al ancla. Quien
/// completa un área se lleva sus puntos. Toda la lógica es autoritativa: el
/// cliente solo pide acciones y aquí se validan.
class PartidaOnline {
  PartidaOnline({
    required this.mapa,
    required List<({String id, String nombre})> jugadores,
    Random? azar,
    this.maxTurnosAgotados = 3,
  }) : assert(jugadores.length >= 2),
       _azar = azar ?? Random.secure(),
       jugadores = [for (final j in jugadores) JugadorPartida(j.id, j.nombre)],
       controlador = ControladorPartida(
         gruposConectados: mapasOficiales[mapa].gruposConectados,
       ) {
    final celdas = mapasOficiales[mapa].crearTablero();
    final numeros = [1, 2, 3, 4, 5, 6]..shuffle(_azar);
    final iniciales = mapasOficiales[mapa].indicesIniciales;
    for (var k = 0; k < iniciales.length; k++) {
      celdas[iniciales[k]] = celdas[iniciales[k]].copiarCon(valor: numeros[k]);
    }
    controlador.establecerValoresIniciales(celdas);
    _turnoIdx = _azar.nextInt(this.jugadores.length);
    mensaje = '¡Empieza la partida! Juega ${this.jugadores[_turnoIdx].nombre}.';
  }

  /// Índice en [mapasOficiales].
  final int mapa;
  final List<JugadorPartida> jugadores;
  final ControladorPartida controlador;
  final int maxTurnosAgotados;
  final Random _azar;

  int _turnoIdx = 0;

  /// Contador global de turnos (empieza en 1).
  int numTurno = 1;
  List<int>? dados;
  bool terminada = false;
  ResultadoPartida? resultado;
  late String mensaje;

  String get turnoDe => jugadores[_turnoIdx].id;

  JugadorPartida? jugador(String id) {
    for (final j in jugadores) {
      if (j.id == id) return j;
    }
    return null;
  }

  List<int?> get tablero => [for (final c in controlador.matriz) c.valor];

  /// Casillas donde se puede colocar con el dado [posAncla] como ancla.
  Set<int> destinos(int posAncla) {
    final d = dados;
    if (d == null) return {};
    return controlador.destinosPosibles(
      ancla: d[posAncla],
      colocar: d[1 - posAncla],
    );
  }

  bool get hayMovimientosConLosDados =>
      dados != null && (destinos(0).isNotEmpty || destinos(1).isNotEmpty);

  /// Si existe alguna pareja de dados que permita jugar en este tablero.
  bool get quedanMovimientos {
    for (var a = 1; a <= 6; a++) {
      for (var c = 1; c <= 6; c++) {
        if (controlador.destinosPosibles(ancla: a, colocar: c).isNotEmpty) {
          return true;
        }
      }
    }
    return false;
  }

  JugadorPartida _jugadorEnTurno(String id) {
    if (terminada) throw ErrorJuego('La partida ya terminó.');
    final j = jugador(id);
    if (j == null || !j.activo) {
      throw ErrorJuego('Ya no participas en la partida.');
    }
    if (turnoDe != id) throw ErrorJuego('No es tu turno.');
    return j;
  }

  void tirar(String id) {
    final j = _jugadorEnTurno(id);
    if (dados != null) throw ErrorJuego('Ya tiraste los dados.');
    j.turnosAgotados = 0;
    final d = [_azar.nextInt(6) + 1, _azar.nextInt(6) + 1];
    dados = d;
    mensaje = hayMovimientosConLosDados
        ? '${j.nombre} sacó ${d[0]} y ${d[1]}.'
        : '${j.nombre} sacó ${d[0]} y ${d[1]} y no tiene movimientos.';
  }

  /// [posAncla] es la posición (0 o 1) del dado que actúa de ancla.
  void colocar(String id, int indice, int posAncla) {
    final j = _jugadorEnTurno(id);
    final d = dados;
    if (d == null) throw ErrorJuego('Tira los dados primero.');
    if (posAncla != 0 && posAncla != 1) throw ErrorJuego('Dado inválido.');
    if (!destinos(posAncla).contains(indice)) {
      throw ErrorJuego('Esa casilla no es un destino válido.');
    }
    final numero = d[1 - posAncla];
    final antes = controlador.puntuacionTotal;
    if (!controlador.colocar(indice, numero)) {
      throw ErrorJuego('Ese número no cumple la regla del área.');
    }
    final ganados = controlador.puntuacionTotal - antes;
    j.puntos += ganados;
    j.turnosAgotados = 0;
    mensaje = ganados > 0
        ? '${j.nombre} completó un área y suma $ganados puntos.'
        : '${j.nombre} colocó un $numero.';
    dados = null;

    final hayHuecos = controlador.matriz.any((c) => c.valor == null);
    if (!hayHuecos) {
      _terminar(MotivoFin.tableroCompleto);
    } else if (!quedanMovimientos) {
      _terminar(MotivoFin.sinMovimientos);
    } else {
      _avanzarTurno();
    }
  }

  /// Solo se puede pasar si los dados no dejan ningún movimiento.
  void pasar(String id) {
    final j = _jugadorEnTurno(id);
    if (dados == null) throw ErrorJuego('Tira los dados primero.');
    if (hayMovimientosConLosDados) {
      throw ErrorJuego('Tienes movimientos disponibles: no puedes pasar.');
    }
    j.turnosAgotados = 0;
    dados = null;
    mensaje = '${j.nombre} pasó el turno.';
    _avanzarTurno();
  }

  /// Se acabó el tiempo del jugador en turno.
  void tiempoAgotado() {
    if (terminada) return;
    final j = jugadores[_turnoIdx];
    j.turnosAgotados++;
    dados = null;
    if (j.turnosAgotados >= maxTurnosAgotados) {
      _retirar(
        j,
        EstadoJugador.abandono,
        'se quedó sin tiempo demasiadas veces',
      );
    } else {
      mensaje = 'Se agotó el tiempo de ${j.nombre}.';
      _avanzarTurno();
    }
  }

  void conceder(String id) {
    final j = jugador(id);
    if (terminada) throw ErrorJuego('La partida ya terminó.');
    if (j == null || !j.activo) {
      throw ErrorJuego('Ya no participas en la partida.');
    }
    _retirar(j, EstadoJugador.concedio, 'se rindió');
  }

  /// El jugador se fue (por ejemplo, no volvió tras desconectarse).
  void abandonar(String id, {String motivo = 'abandonó la partida'}) {
    final j = jugador(id);
    if (terminada || j == null || !j.activo) return;
    _retirar(j, EstadoJugador.abandono, motivo);
  }

  void _retirar(JugadorPartida j, EstadoJugador estado, String texto) {
    final eraSuTurno = jugadores[_turnoIdx] == j;
    j.estado = estado;
    mensaje = '${j.nombre} $texto.';
    final activos = jugadores.where((x) => x.activo).length;
    if (activos <= 1) {
      _terminar(
        estado == EstadoJugador.concedio
            ? MotivoFin.rendicion
            : MotivoFin.abandono,
      );
    } else if (eraSuTurno) {
      dados = null;
      _avanzarTurno();
    }
  }

  void _avanzarTurno() {
    do {
      _turnoIdx = (_turnoIdx + 1) % jugadores.length;
    } while (!jugadores[_turnoIdx].activo);
    numTurno++;
  }

  void _terminar(MotivoFin motivo) {
    terminada = true;
    dados = null;
    final activos = jugadores.where((j) => j.activo).toList();
    List<String> ganadores;
    if (motivo == MotivoFin.rendicion || motivo == MotivoFin.abandono) {
      ganadores = [for (final j in activos) j.id];
    } else {
      final mejor = activos.fold<int>(0, (m, j) => max(m, j.puntos));
      ganadores = [
        for (final j in activos)
          if (j.puntos == mejor) j.id,
      ];
    }
    resultado = ResultadoPartida(ganadores: ganadores, motivo: motivo);
    final nombres = [for (final id in ganadores) jugador(id)!.nombre];
    final base = switch (motivo) {
      MotivoFin.tableroCompleto => 'Tablero completo.',
      MotivoFin.sinMovimientos => 'Ya no quedan movimientos posibles.',
      MotivoFin.rendicion => mensaje,
      MotivoFin.abandono => mensaje,
    };
    mensaje = switch (nombres.length) {
      0 => '$base Nadie gana.',
      1 => '$base Gana ${nombres.first}.',
      _ => '$base Empate entre ${nombres.join(' y ')}.',
    };
  }
}
