import 'dart:math';

import 'package:brilliant_nucleo/brilliant_nucleo.dart';

/// Jugada o petición inválida; el mensaje se muestra tal cual al jugador.
class ErrorJuego implements Exception {
  ErrorJuego(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Fases de una partida (la sala añade el lobby, antes de que exista).
enum FasePartida { preparacion, jugando, terminada }

/// Un participante con su tablero propio.
class JugadorPartida {
  JugadorPartida(this.id, this.nombre, this.mapa)
    : valores = List<int?>.filled(49, null);

  final String id;
  final String nombre;
  final MapaOficial mapa;

  /// Borrador de la distribución inicial (hasta confirmarla).
  final List<int?> valores;

  /// Tablero de juego; existe solo desde que se confirma la distribución.
  ControladorPartida? controlador;

  EstadoJugador estado = EstadoJugador.preparando;

  /// Turnos seguidos que se agotó el tiempo sin que jugara.
  int turnosAgotados = 0;

  /// Sigue en la partida y puede ganar (no se rindió ni abandonó).
  bool get participa =>
      estado != EstadoJugador.concedio && estado != EstadoJugador.abandono;

  /// Puntos del tablero. Se calculan siempre a partir de las casillas, así que
  /// no se acumulan ni se duplican; valen 0 hasta confirmar la distribución.
  int get puntos => controlador?.puntuacionTotal ?? 0;

  List<int?> get tablero => controlador == null
      ? List<int?>.of(valores)
      : [for (final c in controlador!.matriz) c.valor];

  /// ¿Queda alguna jugada legal con alguna pareja de dados posible?
  bool get quedanMovimientos {
    final c = controlador;
    if (c == null) return false;
    if (!c.matriz.any((x) => x.valor == null)) return false;
    for (var a = 1; a <= 6; a++) {
      for (var n = 1; n <= 6; n++) {
        if (c.destinosPosibles(ancla: a, colocar: n).isNotEmpty) return true;
      }
    }
    return false;
  }
}

/// Partida por turnos con un tablero independiente por jugador.
///
/// Fases: **preparación** (cada jugador reparte el 1..6 en las seis posiciones
/// iniciales de su tablero y lo confirma), **partida** y **terminada**. Cada
/// turno: el jugador tira dos dados, elige uno como ancla y coloca el otro
/// número en una casilla vecina a un número igual al ancla, siempre en su
/// propio tablero. Toda la lógica es autoritativa: el cliente solo pide
/// acciones y aquí se validan.
class PartidaOnline {
  PartidaOnline({
    required this.mapa,
    required List<({String id, String nombre})> jugadores,
    Random? azar,
    this.maxTurnosAgotados = 3,
  }) : assert(jugadores.length >= 2),
       _azar = azar ?? Random.secure(),
       jugadores = [
         for (final j in jugadores)
           JugadorPartida(j.id, j.nombre, mapasOficiales[mapa]),
       ] {
    mensaje =
        'Coloca los números del 1 al 6 en las seis posiciones iniciales de '
        'tu tablero.';
  }

  /// Índice en [mapasOficiales].
  final int mapa;
  final List<JugadorPartida> jugadores;
  final int maxTurnosAgotados;
  final Random _azar;

  FasePartida fase = FasePartida.preparacion;
  int _turnoIdx = 0;

  /// Contador global de turnos (empieza en 1).
  int numTurno = 1;
  List<int>? dados;
  ResultadoPartida? resultado;
  late String mensaje;

  bool get terminada => fase == FasePartida.terminada;
  MapaOficial get mapaOficial => mapasOficiales[mapa];

  /// Quién debe jugar; solo tiene sentido en la fase de partida.
  String get turnoDe => jugadores[_turnoIdx].id;

  JugadorPartida? jugador(String id) {
    for (final j in jugadores) {
      if (j.id == id) return j;
    }
    return null;
  }

  /// Tablero de [id] (vacío si no participa).
  List<int?> tableroDe(String id) =>
      jugador(id)?.tablero ?? List<int?>.filled(49, null);

  /// Casillas del tablero de [id] donde puede colocar con el dado [posAncla]
  /// como ancla.
  Set<int> destinos(String id, int posAncla) {
    final d = dados;
    final c = jugador(id)?.controlador;
    if (d == null || c == null) return {};
    return c.destinosPosibles(ancla: d[posAncla], colocar: d[1 - posAncla]);
  }

  bool hayMovimientosConLosDados(String id) =>
      dados != null &&
      (destinos(id, 0).isNotEmpty || destinos(id, 1).isNotEmpty);

  // ---------------------------------------------------------------------
  // Preparación

  JugadorPartida _enPreparacion(String id) {
    if (terminada) throw ErrorJuego('La partida ya terminó.');
    final j = jugador(id);
    if (j == null || !j.participa) {
      throw ErrorJuego('Ya no participas en la partida.');
    }
    if (fase != FasePartida.preparacion) {
      throw ErrorJuego('La preparación ya terminó.');
    }
    if (j.estado != EstadoJugador.preparando) {
      throw ErrorJuego('Tu distribución ya está confirmada.');
    }
    return j;
  }

  /// Pone [numero] en la posición inicial [indice] del tablero de [id].
  /// Repetir exactamente la misma colocación no cambia nada.
  void colocarInicial(String id, int indice, int numero) {
    final j = _enPreparacion(id);
    final error = errorColocarInicial(mapaOficial, j.valores, indice, numero);
    if (error != null) throw ErrorJuego(error);
    j.valores[indice] = numero;
    mensaje = 'Colocando números iniciales.';
  }

  /// Retira el número de la posición inicial [indice] del tablero de [id].
  void quitarInicial(String id, int indice) {
    final j = _enPreparacion(id);
    final error = errorQuitarInicial(mapaOficial, indice);
    if (error != null) throw ErrorJuego(error);
    j.valores[indice] = null;
  }

  /// Bloquea la distribución de [id]. Confirmar otra vez no hace nada. La
  /// partida empieza, una sola vez, cuando todos los que siguen en ella
  /// confirmaron.
  void confirmarDistribucion(String id) {
    if (terminada) throw ErrorJuego('La partida ya terminó.');
    final j = jugador(id);
    if (j == null || !j.participa) {
      throw ErrorJuego('Ya no participas en la partida.');
    }
    if (fase != FasePartida.preparacion) {
      if (j.controlador != null) return; // mensaje repetido
      throw ErrorJuego('La preparación ya terminó.');
    }
    if (j.estado == EstadoJugador.listo) return; // mensaje repetido
    final error = errorConfirmarDistribucion(mapaOficial, j.valores);
    if (error != null) throw ErrorJuego(error);

    final celdas = mapaOficial.crearTablero();
    for (final i in mapaOficial.indicesIniciales) {
      celdas[i] = celdas[i].copiarCon(valor: j.valores[i]);
    }
    j.controlador = ControladorPartida(
      gruposConectados: mapaOficial.gruposConectados,
    )..establecerValoresIniciales(celdas);
    j.estado = EstadoJugador.listo;
    mensaje = '${j.nombre} está listo.';
    _revisarFin();
  }

  void _comenzar() {
    fase = FasePartida.jugando;
    for (final j in jugadores) {
      if (j.participa) j.estado = EstadoJugador.jugando;
    }
    for (final j in jugadores) {
      _marcarTerminado(j);
    }
    final candidatos = [
      for (var i = 0; i < jugadores.length; i++)
        if (jugadores[i].estado == EstadoJugador.jugando) i,
    ];
    if (candidatos.isEmpty) {
      _terminar(MotivoFin.todosTerminaron);
      return;
    }
    _turnoIdx = candidatos[_azar.nextInt(candidatos.length)];
    numTurno = 1;
    mensaje = '¡Empieza la partida! Juega ${jugadores[_turnoIdx].nombre}.';
  }

  // ---------------------------------------------------------------------
  // Turnos

  JugadorPartida _jugadorEnTurno(String id) {
    if (terminada) throw ErrorJuego('La partida ya terminó.');
    final j = jugador(id);
    if (j == null || !j.participa) {
      throw ErrorJuego('Ya no participas en la partida.');
    }
    if (fase == FasePartida.preparacion) {
      throw ErrorJuego(
        'La partida aún no empezó: coloca tus números iniciales.',
      );
    }
    if (j.estado == EstadoJugador.terminado) {
      throw ErrorJuego('Ya terminaste tu tablero.');
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
    mensaje = hayMovimientosConLosDados(id)
        ? '${j.nombre} sacó ${d[0]} y ${d[1]}.'
        : '${j.nombre} sacó ${d[0]} y ${d[1]} y no tiene movimientos.';
  }

  /// [posAncla] es la posición (0 o 1) del dado que actúa de ancla. La jugada
  /// se aplica solo al tablero de [id].
  void colocar(String id, int indice, int posAncla) {
    final j = _jugadorEnTurno(id);
    final d = dados;
    if (d == null) throw ErrorJuego('Tira los dados primero.');
    if (posAncla != 0 && posAncla != 1) throw ErrorJuego('Dado inválido.');
    if (!destinos(id, posAncla).contains(indice)) {
      throw ErrorJuego('Esa casilla no es un destino válido.');
    }
    final numero = d[1 - posAncla];
    final antes = j.puntos;
    if (!j.controlador!.colocar(indice, numero)) {
      throw ErrorJuego('Ese número no cumple la regla del área.');
    }
    final ganados = j.puntos - antes;
    j.turnosAgotados = 0;
    mensaje = ganados > 0
        ? '${j.nombre} completó un área y suma $ganados puntos.'
        : '${j.nombre} colocó un $numero.';
    dados = null;
    _marcarTerminado(j);
    _avanzarTurno();
    _revisarFin();
  }

  /// Solo se puede pasar si los dados no dejan ningún movimiento. Pasar no
  /// termina el tablero: el jugador sigue participando en los turnos.
  void pasar(String id) {
    final j = _jugadorEnTurno(id);
    if (dados == null) throw ErrorJuego('Tira los dados primero.');
    if (hayMovimientosConLosDados(id)) {
      throw ErrorJuego('Tienes movimientos disponibles: no puedes pasar.');
    }
    j.turnosAgotados = 0;
    dados = null;
    mensaje = '${j.nombre} pasó el turno.';
    _avanzarTurno();
    _revisarFin();
  }

  /// Se acabó el tiempo del jugador en turno.
  void tiempoAgotado() {
    if (fase != FasePartida.jugando) return;
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
      _revisarFin();
    }
  }

  // ---------------------------------------------------------------------
  // Salidas

  void conceder(String id) {
    final j = jugador(id);
    if (terminada) throw ErrorJuego('La partida ya terminó.');
    if (j == null || !j.participa) {
      throw ErrorJuego('Ya no participas en la partida.');
    }
    _retirar(j, EstadoJugador.concedio, 'se rindió');
  }

  /// El jugador se fue (por ejemplo, no volvió tras desconectarse).
  void abandonar(String id, {String motivo = 'abandonó la partida'}) =>
      abandonarVarios([id], motivo: motivo, motivoPlural: motivo);

  /// Varios jugadores abandonan **a la vez** (por ejemplo, sus plazos de
  /// reconexión vencieron antes del mismo instante de referencia). Se marcan
  /// todos antes de decidir nada, así el resultado no depende del orden en que
  /// se procesen: con 0 jugadores elegibles no hay ganador y con 1 gana ese.
  void abandonarVarios(
    Iterable<String> ids, {
    String motivo = 'abandonó la partida',
    String motivoPlural = 'abandonaron la partida',
  }) {
    if (terminada) return;
    final salen = <JugadorPartida>[
      for (final id in ids.toSet())
        if (jugador(id) case final j? when j.participa) j,
    ];
    if (salen.isEmpty) return;
    final eraSuTurno =
        fase == FasePartida.jugando && salen.contains(jugadores[_turnoIdx]);
    for (final j in salen) {
      j.estado = EstadoJugador.abandono;
    }
    mensaje = salen.length == 1
        ? '${salen.single.nombre} $motivo.'
        : '${salen.map((j) => j.nombre).join(' y ')} $motivoPlural.';
    if (eraSuTurno) {
      dados = null;
      _avanzarTurno();
    }
    _revisarFin(retiro: MotivoFin.abandono);
  }

  void _retirar(JugadorPartida j, EstadoJugador estado, String texto) {
    final eraSuTurno = fase == FasePartida.jugando && jugadores[_turnoIdx] == j;
    j.estado = estado;
    mensaje = '${j.nombre} $texto.';
    if (eraSuTurno) {
      dados = null;
      _avanzarTurno();
    }
    _revisarFin(
      retiro: estado == EstadoJugador.concedio
          ? MotivoFin.rendicion
          : MotivoFin.abandono,
    );
  }

  // ---------------------------------------------------------------------
  // Fin de la preparación y de la partida

  /// Un jugador que llenó su tablero o ya no tiene ninguna jugada legal (con
  /// ninguna pareja de dados) queda como terminado: se salta su turno pero
  /// sigue siendo candidato a ganar.
  void _marcarTerminado(JugadorPartida j) {
    if (j.estado != EstadoJugador.jugando || j.quedanMovimientos) return;
    j.estado = EstadoJugador.terminado;
    final lleno = !j.controlador!.matriz.any((c) => c.valor == null);
    mensaje =
        '$mensaje ${j.nombre} ${lleno ? 'completó' : 'no puede seguir en'} '
        'su tablero.';
  }

  /// Pasa el turno al siguiente jugador que aún juega; si no queda ninguno,
  /// deja el turno como está (el fin lo decide [_revisarFin]). Antes de dar el
  /// turno comprueba que cada jugador tenga alguna jugada posible: si no,
  /// queda como terminado y se salta.
  void _avanzarTurno() {
    jugadores.forEach(_marcarTerminado);
    for (var paso = 1; paso <= jugadores.length; paso++) {
      final i = (_turnoIdx + paso) % jugadores.length;
      if (jugadores[i].estado == EstadoJugador.jugando) {
        _turnoIdx = i;
        numTurno++;
        return;
      }
    }
  }

  /// Decide si la preparación acaba, si empieza la partida o si esta termina.
  /// Se llama tras cualquier cambio que pueda afectarlo.
  void _revisarFin({MotivoFin retiro = MotivoFin.abandono}) {
    if (terminada) return;
    final quedan = jugadores.where((j) => j.participa).toList();
    if (quedan.length <= 1) {
      _terminar(retiro);
    } else if (fase == FasePartida.preparacion) {
      if (quedan.every((j) => j.estado == EstadoJugador.listo)) _comenzar();
    } else if (!quedan.any((j) => j.estado == EstadoJugador.jugando)) {
      _terminar(MotivoFin.todosTerminaron);
    }
  }

  void _terminar(MotivoFin motivo) {
    fase = FasePartida.terminada;
    dados = null;
    final elegibles = jugadores.where((j) => j.participa).toList();
    List<String> ganadores;
    if (motivo == MotivoFin.todosTerminaron) {
      final mejor = elegibles.fold<int>(0, (m, j) => max(m, j.puntos));
      ganadores = [
        for (final j in elegibles)
          if (j.puntos == mejor) j.id,
      ];
    } else {
      // Victoria automática: solo quedó uno (o nadie) porque los demás se
      // rindieron o abandonaron.
      ganadores = [for (final j in elegibles) j.id];
    }
    resultado = ResultadoPartida(ganadores: ganadores, motivo: motivo);
    final nombres = [for (final id in ganadores) jugador(id)!.nombre];
    final base = switch (motivo) {
      MotivoFin.todosTerminaron => 'Todos terminaron su tablero.',
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
