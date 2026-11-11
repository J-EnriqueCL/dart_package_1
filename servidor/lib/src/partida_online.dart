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

  /// Rondas seguidas que se agotó el plazo sin que respondiera (ni jugando ni
  /// pasando). Responder, aunque sea pasando, lo reinicia.
  int sinRespuestaSeguidas = 0;

  /// Sigue en la partida y puede ganar (no se rindió ni abandonó).
  bool get participa =>
      estado != EstadoJugador.concedio && estado != EstadoJugador.abandono;

  /// Puntos **adjudicados** por el servidor al liquidar premios (no se
  /// calculan del tablero: dependen del orden en que se completan los grupos).
  int puntos = 0;

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

/// Partida por rondas con un tablero independiente por jugador.
///
/// Fases: **preparación** (cada jugador reparte el 1..6 en las seis posiciones
/// iniciales de su tablero y lo confirma), **partida** y **terminada**.
///
/// En la partida cada **ronda** tiene una única tirada de dos dados que
/// comparten todos. Un jugador pide la tirada (cualquiera que siga jugando,
/// la primera solicitud válida gana) y a partir de ahí **todos resuelven a la
/// vez**, sin orden: cada uno confirma una jugada en su propio tablero (elige
/// un dado como ancla y coloca el otro número en una casilla vecina a un
/// número igual al ancla) o pasa, aunque tenga jugadas. La ronda se cierra
/// cuando no queda ningún participante pendiente, o al vencer el plazo común;
/// la siguiente espera una nueva tirada manual.
///
/// Toda la lógica es autoritativa y se comprueba al procesar cada acción
/// (fase, id de ronda y resolución del jugador); el cliente solo pide
/// acciones.
class PartidaOnline {
  PartidaOnline({
    required this.mapa,
    required List<({String id, String nombre})> jugadores,
    Random? azar,
    this.maxSinRespuesta = 3,
    List<GrupoPremio>? grupos,
  }) : assert(jugadores.length >= 2),
       _azar = azar ?? Random.secure(),
       jugadores = [
         for (final j in jugadores)
           JugadorPartida(j.id, j.nombre, mapasOficiales[mapa]),
       ],
       libro = LibroPremios(grupos ?? mapasOficiales[mapa].gruposPremio) {
    mensaje =
        'Coloca los números del 1 al 6 en las seis posiciones iniciales de '
        'tu tablero.';
  }

  /// Índice en [mapasOficiales].
  final int mapa;
  final List<JugadorPartida> jugadores;

  /// Rondas seguidas sin respuesta que provocan el abandono.
  final int maxSinRespuesta;
  final Random _azar;

  /// Historial competitivo de premios (por grupo y nivel).
  final LibroPremios libro;

  /// Meta de puntos, fijada al empezar según los participantes; null antes.
  int? meta;

  /// Finalizaciones de la ronda abierta aún sin liquidar: grupo -> jugadores.
  /// No dan prioridad por orden de llegada: se agrupan al cerrar la ronda.
  final Map<String, Set<String>> _completadasRonda = {};

  /// Última liquidación realizada (al cerrar una ronda o terminar la
  /// preparación).
  List<Adjudicacion> liquidacion = const [];

  FasePartida fase = FasePartida.preparacion;

  /// Identificador de la ronda actual (empieza en 1). Sube al cerrarse.
  int rondaId = 1;
  FaseRonda faseRonda = FaseRonda.esperandoTirada;

  /// Dados compartidos de la ronda abierta; null mientras se espera la tirada.
  List<int>? dados;

  /// Participantes de la ronda abierta y su resolución.
  final Map<String, Resolucion> resoluciones = {};
  ResultadoPartida? resultado;
  late String mensaje;

  bool get terminada => fase == FasePartida.terminada;
  MapaOficial get mapaOficial => mapasOficiales[mapa];

  /// Cambia al cambiar de fase y al abrirse o cerrarse una ronda, nunca al
  /// confirmar o pasar: sirve para programar el plazo común una sola vez.
  String get claveRonda => '${fase.name}:$rondaId:${faseRonda.name}';

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

  /// Grupos que [id] completó en la ronda abierta y aún no están liquidados.
  List<String> pendientesDe(String id) => [
    for (final e in _completadasRonda.entries)
      if (e.value.contains(id)) e.key,
  ]..sort();

  /// Registra los grupos recién completos del tablero de [j]. No se adjudica
  /// nada aquí: el premio se decide al cerrar la ronda con todas las jugadas.
  void registrarGruposCompletos(JugadorPartida j) {
    for (final g in libro.gruposCompletos(j.tablero)) {
      if (libro.yaReclamo(g, j.id)) continue;
      (_completadasRonda[g] ??= {}).add(j.id);
    }
  }

  /// Liquida lo pendiente: agrupa las finalizaciones por grupo, aplica los
  /// niveles de premio (con empates compartidos) y suma los puntos.
  List<Adjudicacion> _liquidar(int ronda) {
    final adj = libro.liquidar(ronda, _completadasRonda);
    _completadasRonda.clear();
    for (final a in adj) {
      jugador(a.jugador)!.puntos += a.puntos;
    }
    liquidacion = adj;
    if (adj.isNotEmpty) {
      final texto = [
        for (final a in adj)
          '${jugador(a.jugador)!.nombre} '
              '${a.nivel == 0 ? 'sin premio' : '+${a.puntos} (${a.nivel}.º)'} '
              'en ${mapaOficial.etiquetaDe(libro.grupo(a.grupo)!)}',
      ].join('; ');
      mensaje = '$mensaje Premios: $texto.';
    }
    return adj;
  }

  /// Foto de la ronda para el cliente (sin el plazo, que lo pone la sala).
  RondaSala ronda({int? segundos}) => RondaSala(
    id: rondaId,
    fase: faseRonda,
    dados: dados == null ? null : List<int>.of(dados!),
    resoluciones: Map<String, Resolucion>.of(resoluciones),
    segundos: segundos,
  );

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
    rondaId = 1;
    faseRonda = FaseRonda.esperandoTirada;
    // La meta queda fijada por los participantes al empezar.
    meta = metaPara(jugadores.where((j) => j.participa).length);
    // Grupos que ya nacen completos: se evalúan juntos al acabar la
    // preparación, sin importar quién confirmó antes; todos empatan en el
    // primer nivel.
    for (final j in jugadores) {
      if (j.participa) registrarGruposCompletos(j);
    }
    _liquidar(0);
    if (!jugadores.any((j) => j.estado == EstadoJugador.jugando)) {
      _terminar(MotivoFin.todosTerminaron);
      return;
    }
    mensaje =
        '¡Empieza la partida! Cualquiera puede tirar los dados de la '
        'ronda 1.';
  }

  // ---------------------------------------------------------------------
  // Rondas

  /// Comprueba lo común a las acciones de ronda y devuelve al jugador.
  JugadorPartida _paraRonda(String id, int ronda) {
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
    if (ronda != rondaId) {
      throw ErrorJuego('Esa ronda ya no está abierta.');
    }
    return j;
  }

  /// Lanza los dados compartidos. Solo la primera solicitud válida de la ronda
  /// genera tirada; una repetida (o simultánea) no cambia nada.
  void tirar(String id, int ronda) {
    final j = _paraRonda(id, ronda);
    if (j.estado != EstadoJugador.jugando) {
      throw ErrorJuego('Ya no puedes lanzar los dados.');
    }
    if (faseRonda == FaseRonda.resolviendo) return; // ya hay tirada
    final d = [_azar.nextInt(6) + 1, _azar.nextInt(6) + 1];
    dados = d;
    faseRonda = FaseRonda.resolviendo;
    resoluciones
      ..clear()
      ..addEntries([
        for (final x in jugadores)
          if (x.estado == EstadoJugador.jugando)
            MapEntry(x.id, Resolucion.pendiente),
      ]);
    mensaje = '${j.nombre} lanzó los dados: ${d[0]} y ${d[1]}.';
  }

  /// Valida que [id] tenga la ronda abierta y siga pendiente; devuelve la
  /// resolución que ya tuviera.
  Resolucion _resolucionDe(String id) {
    if (faseRonda != FaseRonda.resolviendo) {
      throw ErrorJuego('Todavía no se han tirado los dados.');
    }
    final r = resoluciones[id];
    if (r == null) throw ErrorJuego('No participas en esta ronda.');
    return r;
  }

  /// Confirma la jugada de [id] en su propio tablero: [posAncla] es la posición
  /// (0 o 1) del dado ancla. Solo se acepta una resolución por jugador y ronda:
  /// repetir la confirmación no hace nada y confirmar tras pasar se rechaza.
  void confirmarJugada(String id, int ronda, int indice, int posAncla) {
    final j = _paraRonda(id, ronda);
    final previa = _resolucionDe(id);
    if (previa == Resolucion.confirmo) return; // mensaje repetido
    if (previa == Resolucion.paso) {
      throw ErrorJuego('Ya pasaste esta ronda.');
    }
    final d = dados!;
    if (posAncla != 0 && posAncla != 1) throw ErrorJuego('Dado inválido.');
    if (!destinos(id, posAncla).contains(indice)) {
      throw ErrorJuego('Esa casilla no es un destino válido.');
    }
    final numero = d[1 - posAncla];
    if (!j.controlador!.colocar(indice, numero)) {
      throw ErrorJuego('Ese número no cumple la regla del área.');
    }
    j.sinRespuestaSeguidas = 0;
    resoluciones[id] = Resolucion.confirmo;
    final nuevos = libro
        .gruposCompletos(j.tablero)
        .where((g) => !libro.yaReclamo(g, id))
        .length;
    registrarGruposCompletos(j);
    mensaje = nuevos > 0
        ? '${j.nombre} completó un grupo (el premio se decide al cerrar la '
              'ronda).'
        : '${j.nombre} confirmó su jugada.';
    _revisarRonda();
  }

  /// [id] no coloca nada en esta ronda (se puede aunque haya jugadas). Pasar
  /// voluntariamente no cuenta como falta de respuesta. Repetirlo no hace nada
  /// y pasar tras confirmar se rechaza.
  void pasarRonda(String id, int ronda) {
    final j = _paraRonda(id, ronda);
    final previa = _resolucionDe(id);
    if (previa == Resolucion.paso) return; // mensaje repetido
    if (previa == Resolucion.confirmo) {
      throw ErrorJuego('Ya confirmaste tu jugada en esta ronda.');
    }
    j.sinRespuestaSeguidas = 0;
    resoluciones[id] = Resolucion.paso;
    mensaje = '${j.nombre} pasó la ronda.';
    _revisarRonda();
  }

  /// Venció el plazo común: los pendientes quedan sin respuesta (no colocan
  /// nada) y la ronda se cierra. Tras [maxSinRespuesta] seguidas, abandono.
  void plazoAgotado() {
    if (fase != FasePartida.jugando || faseRonda != FaseRonda.resolviendo) {
      return;
    }
    final callaron = [
      for (final e in resoluciones.entries)
        if (e.value == Resolucion.pendiente) jugador(e.key)!,
    ];
    if (callaron.isEmpty) return;
    mensaje =
        'Se agotó el tiempo: ${callaron.map((j) => j.nombre).join(', ')} '
        'no respondió.';
    final abandonan = <JugadorPartida>[];
    for (final j in callaron) {
      j.sinRespuestaSeguidas++;
      resoluciones.remove(j.id);
      if (j.sinRespuestaSeguidas >= maxSinRespuesta) abandonan.add(j);
    }
    if (abandonan.isNotEmpty) {
      _retirarVarios(
        abandonan,
        EstadoJugador.abandono,
        '${abandonan.map((j) => j.nombre).join(' y ')} '
        '${abandonan.length == 1 ? 'se quedó' : 'se quedaron'} sin responder '
        'demasiadas rondas.',
      );
    } else {
      _revisarRonda();
    }
  }

  /// Cierra la ronda abierta (una sola vez) cuando no queda nadie pendiente.
  void _revisarRonda() {
    if (fase != FasePartida.jugando || faseRonda != FaseRonda.resolviendo) {
      return;
    }
    if (resoluciones.values.contains(Resolucion.pendiente)) return;
    // Se evalúa quién terminó su tablero solo al cerrar la ronda.
    for (final j in jugadores) {
      _marcarTerminado(j);
    }
    final cerrada = rondaId;
    dados = null;
    resoluciones.clear();
    faseRonda = FaseRonda.esperandoTirada;
    rondaId++;
    mensaje = '$mensaje Fin de la ronda $cerrada.';
    // Liquidación con todas las jugadas de la ronda ya conocidas; después se
    // evalúa la meta con todos los premios de esta ronda adjudicados.
    _liquidar(cerrada);
    final alcanzada =
        meta != null && jugadores.any((j) => j.participa && j.puntos >= meta!);
    if (alcanzada) {
      _terminar(MotivoFin.meta);
      return;
    }
    _revisarFin();
  }

  // ---------------------------------------------------------------------
  // Salidas

  void conceder(String id) {
    final j = jugador(id);
    if (terminada) throw ErrorJuego('La partida ya terminó.');
    if (j == null || !j.participa) {
      throw ErrorJuego('Ya no participas en la partida.');
    }
    _retirarVarios([j], EstadoJugador.concedio, '${j.nombre} se rindió.');
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
    _retirarVarios(
      salen,
      EstadoJugador.abandono,
      salen.length == 1
          ? '${salen.single.nombre} $motivo.'
          : '${salen.map((j) => j.nombre).join(' y ')} $motivoPlural.',
    );
  }

  void _retirarVarios(
    List<JugadorPartida> salen,
    EstadoJugador estado,
    String texto,
  ) {
    for (final j in salen) {
      j.estado = estado;
      resoluciones.remove(j.id); // ya no se espera su respuesta
    }
    mensaje = texto;
    _revisarFin(
      retiro: estado == EstadoJugador.concedio
          ? MotivoFin.rendicion
          : MotivoFin.abandono,
    );
    _revisarRonda();
  }

  // ---------------------------------------------------------------------
  // Fin de la preparación y de la partida

  /// Un jugador que llenó su tablero o ya no tiene ninguna jugada legal (con
  /// ninguna pareja de dados) queda como terminado: deja de participar en las
  /// rondas pero **conserva sus puntos y sigue siendo candidato a ganar**.
  void _marcarTerminado(JugadorPartida j) {
    if (j.estado != EstadoJugador.jugando || j.quedanMovimientos) return;
    j.estado = EstadoJugador.terminado;
    final lleno = !j.controlador!.matriz.any((c) => c.valor == null);
    mensaje =
        '$mensaje ${j.nombre} ${lleno ? 'completó' : 'no puede seguir en'} '
        'su tablero.';
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
    // Lo que se completó en una ronda cortada (rendición o abandono) también
    // se liquida antes de dar el resultado.
    if (_completadasRonda.isNotEmpty) _liquidar(rondaId);
    fase = FasePartida.terminada;
    dados = null;
    resoluciones.clear();
    final elegibles = jugadores.where((j) => j.participa).toList();
    List<String> ganadores;
    if (motivo == MotivoFin.todosTerminaron || motivo == MotivoFin.meta) {
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
      MotivoFin.meta => 'Se alcanzó la meta de $meta puntos.',
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
