import 'dart:async';
import 'dart:math';

import 'package:brilliant_nucleo/brilliant_nucleo.dart';

import 'almacen.dart';
import 'partida_online.dart';

/// Extremo de una conexión de un jugador. Permite probar la lógica sin red.
abstract class Canal {
  void enviar(Map<String, Object?> mensaje);
  void cerrar([int? codigo, String? motivo]);
}

class ConfigSalas {
  const ConfigSalas({
    this.tiempoTurno = const Duration(seconds: 60),
    this.graciaPartida = const Duration(seconds: 60),
    this.graciaLobby = const Duration(seconds: 20),
    this.maxTurnosAgotados = 3,
    this.minJugadores = 2,
    this.maxJugadores = 4,
    this.maxSalas = 500,
    this.maxFallosUnirse = 8,
    this.ventanaFallosUnirse = const Duration(minutes: 1),
  });

  /// Tiempo máximo para tirar y colocar en un turno.
  final Duration tiempoTurno;

  /// Tiempo que se espera a un jugador desconectado durante la partida.
  final Duration graciaPartida;

  /// Ídem en el lobby o con la partida ya terminada.
  final Duration graciaLobby;
  final int maxTurnosAgotados;
  final int minJugadores;
  final int maxJugadores;
  final int maxSalas;

  /// Códigos de sala erróneos tolerados por usuario en [ventanaFallosUnirse].
  final int maxFallosUnirse;
  final Duration ventanaFallosUnirse;
}

class Miembro {
  Miembro(this.id, this.nombre);

  final String id;
  String nombre;
  Canal? canal;
  DateTime? limiteGracia;
  Timer? _timerGracia;

  /// false si salió (o se le dio por perdido) con la partida en marcha; su
  /// puntuación se sigue mostrando pero ya no cuenta como miembro.
  bool presente = true;

  bool get conectado => canal != null;

  void cancelarGracia() {
    _timerGracia?.cancel();
    _timerGracia = null;
    limiteGracia = null;
  }
}

class Sala {
  Sala({
    required this.codigo,
    required this.config,
    required Miembro anfitrion,
    required this.mapa,
  }) : anfitrionId = anfitrion.id {
    miembros.add(anfitrion);
  }

  final String codigo;
  final ConfigSalas config;
  final List<Miembro> miembros = [];
  String anfitrionId;
  int mapa;
  PartidaOnline? partida;
  String mensajeLobby = '';
  Timer? _timerTurno;
  DateTime? limiteTurno;

  FaseSala get fase => switch (partida?.fase) {
    null => FaseSala.lobby,
    FasePartida.preparacion => FaseSala.preparacion,
    FasePartida.jugando => FaseSala.jugando,
    FasePartida.terminada => FaseSala.terminada,
  };

  /// Cambia al cambiar de fase y cuando empieza o termina un turno; sirve para
  /// reprogramar el reloj.
  String get claveTurno =>
      partida == null ? 'lobby' : '${partida!.fase.name}:${partida!.numTurno}';

  Iterable<Miembro> get presentes => miembros.where((m) => m.presente);

  Miembro? miembro(String id) {
    for (final m in miembros) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Evita dos jugadores con el mismo nombre en la sala.
  String nombreLibre(String base) {
    var nombre = base;
    var n = 2;
    while (miembros.any((m) => m.nombre == nombre)) {
      nombre = '$base ($n)';
      n++;
    }
    return nombre;
  }

  static int? _segundos(DateTime? limite, DateTime ahora) {
    if (limite == null) return null;
    final ms = limite.difference(ahora).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  EstadoSala estadoPara(String id, DateTime ahora) {
    final p = partida;
    JugadorSala deMiembro(Miembro m, {int puntos = 0, EstadoJugador? estado}) {
      final conectado = m.presente && m.conectado;
      return JugadorSala(
        id: m.id,
        nombre: m.nombre,
        conectado: conectado,
        puntos: puntos,
        estado: estado ?? EstadoJugador.preparando,
        graciaRestante: conectado || !m.presente
            ? null
            : _segundos(m.limiteGracia, ahora),
      );
    }

    return EstadoSala(
      yo: id,
      codigo: codigo,
      fase: fase,
      mapa: p?.mapa ?? mapa,
      maxJugadores: config.maxJugadores,
      anfitrion: anfitrionId,
      jugadores: p == null
          ? [for (final m in miembros) deMiembro(m)]
          : [
              for (final j in p.jugadores)
                if (miembro(j.id) case final m?)
                  deMiembro(m, puntos: j.puntos, estado: j.estado),
            ],
      turnoDe: fase == FaseSala.jugando ? p!.turnoDe : null,
      turno: p?.numTurno ?? 1,
      dados: p?.dados == null ? null : List<int>.of(p!.dados!),
      // Cada jugador recibe solo su propio tablero.
      tablero: p?.tableroDe(id) ?? const [],
      mensaje: p?.mensaje ?? mensajeLobby,
      segundosTurno: fase == FaseSala.jugando
          ? _segundos(limiteTurno, ahora)
          : null,
      resultado: p?.resultado,
    );
  }

  void cancelarTemporizadores() {
    _timerTurno?.cancel();
    _timerTurno = null;
    limiteTurno = null;
    for (final m in miembros) {
      m.cancelarGracia();
    }
  }
}

/// Salas, lobby, códigos de invitación y control de conexiones.
///
/// Todo corre en un solo hilo, así que los mensajes de los jugadores se
/// procesan de uno en uno y no hay carreras entre ellos.
class GestorSalas {
  GestorSalas({
    this.config = const ConfigSalas(),
    Random? azar,
    DateTime Function()? ahora,
  }) : _azar = azar ?? Random.secure(),
       _ahora = ahora ?? DateTime.now;

  final ConfigSalas config;
  final Random _azar;
  final DateTime Function() _ahora;

  final Map<String, Sala> _salas = {};
  final Map<String, Sala> _salaDe = {};
  final Map<String, Canal> _canales = {};
  final Map<String, List<DateTime>> _fallosUnirse = {};

  /// Nombre público (parte local del correo) de cada usuario conectado.
  final Map<String, String> _nombres = {};

  // Sin 0/O/1/I/L para que el código se dicte sin confusiones.
  static const _alfabeto = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const longitudCodigo = 6;

  int get totalSalas => _salas.length;
  Sala? salaDeUsuario(String id) => _salaDe[id];
  Sala? sala(String codigo) => _salas[codigo];

  static String normalizarCodigo(String c) =>
      c.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');

  String _nuevoCodigo() {
    for (;;) {
      final c = String.fromCharCodes([
        for (var i = 0; i < longitudCodigo; i++)
          _alfabeto.codeUnitAt(_azar.nextInt(_alfabeto.length)),
      ]);
      if (!_salas.containsKey(c)) return c;
    }
  }

  static String _nombreDe(Usuario u) {
    final n = u.correo.split('@').first;
    return n.length > 16 ? n.substring(0, 16) : n;
  }

  // ---------------------------------------------------------------------
  // Conexiones

  /// Registra la conexión autenticada de [u]. Si ya tenía otra, la sustituye
  /// y, si estaba en una sala, vuelve a ella tal como la dejó.
  void conectar(Usuario u, Canal canal) {
    final previo = _canales[u.id];
    _canales[u.id] = canal;
    _nombres[u.id] = _nombreDe(u);
    if (previo != null && !identical(previo, canal)) {
      previo.enviar({'tipo': MsgServidor.sesionReemplazada});
      previo.cerrar(4003, 'Sesión abierta en otro lugar');
    }
    final sala = _salaDe[u.id];
    final m = sala?.miembro(u.id);
    if (sala == null || m == null) {
      canal.enviar({'tipo': MsgServidor.sinSala});
      return;
    }
    m.canal = canal;
    m.cancelarGracia();
    _difundir(sala);
  }

  /// La conexión [canal] de [id] se cerró. Se le da un plazo para volver.
  void desconectar(String id, Canal canal) {
    if (!identical(_canales[id], canal)) return; // ya fue reemplazada
    _canales.remove(id);
    final sala = _salaDe[id];
    final m = sala?.miembro(id);
    if (sala == null || m == null) {
      _nombres.remove(id);
      return;
    }
    m.canal = null;
    final gracia =
        sala.fase == FaseSala.preparacion || sala.fase == FaseSala.jugando
        ? config.graciaPartida
        : config.graciaLobby;
    m.cancelarGracia();
    m.limiteGracia = _ahora().add(gracia);
    m._timerGracia = Timer(gracia, () => _graciaAgotada(sala, m));
    _difundir(sala);
  }

  void _graciaAgotada(Sala sala, Miembro m) {
    m._timerGracia = null;
    m.limiteGracia = null;
    if (m.conectado || !m.presente || !identical(_salaDe[m.id], sala)) {
      return;
    }
    // Abandono confirmado: venció su plazo. Se miran, con este mismo instante
    // de referencia, los demás desconectados cuyo plazo también venció, para
    // resolverlos juntos: así el resultado (ganador o ninguno) no depende de
    // qué temporizador se ejecute primero. Quien aún está dentro de su plazo no
    // se toca.
    final ahora = _ahora();
    // (En el orden de la sala, no en el de los temporizadores.)
    final vencidos = [
      for (final o in sala.miembros)
        if (o == m ||
            (o.presente &&
                !o.conectado &&
                o.limiteGracia != null &&
                !o.limiteGracia!.isAfter(ahora)))
          o,
    ];
    _sacarVarios(sala, vencidos, voluntario: false);
  }

  // ---------------------------------------------------------------------
  // Mensajes de los jugadores

  /// Procesa un mensaje de [id] recibido por [canal]. Los errores de juego
  /// se devuelven al propio jugador y no afectan a los demás.
  void manejar(String id, Canal canal, Map<String, Object?> msg) {
    if (!identical(_canales[id], canal)) return; // conexión obsoleta
    try {
      _despachar(id, canal, msg);
    } on ErrorJuego catch (e) {
      canal.enviar({
        'tipo': MsgServidor.error,
        'codigo': CodigoError.generico,
        'mensaje': e.mensaje,
      });
    }
  }

  void _despachar(String id, Canal canal, Map<String, Object?> msg) {
    final tipo = msg['tipo'];
    switch (tipo) {
      case MsgCliente.ping:
        canal.enviar({'tipo': MsgServidor.pong});
      case MsgCliente.crearSala:
        _crearSala(id, canal, _entero(msg, 'mapa', porDefecto: 0));
      case MsgCliente.unirse:
        _unirse(id, canal, _texto(msg, 'codigo'));
      case MsgCliente.salirSala:
        final sala = _salaDe[id];
        if (sala == null) {
          canal.enviar({'tipo': MsgServidor.sinSala});
        } else {
          _sacar(sala, sala.miembro(id)!, voluntario: true);
        }
      default:
        final sala = _salaDe[id];
        if (sala == null) throw ErrorJuego('No estás en ninguna sala.');
        _accionDeSala(sala, sala.miembro(id)!, tipo, msg);
    }
  }

  void _accionDeSala(
    Sala sala,
    Miembro yo,
    Object? tipo,
    Map<String, Object?> msg,
  ) {
    final claveAntes = sala.claveTurno;
    switch (tipo) {
      case MsgCliente.elegirMapa:
        _soloLobby(sala);
        _soloAnfitrion(sala, yo);
        sala.mapa = _mapaValido(_entero(msg, 'mapa'));
      case MsgCliente.expulsar:
        _soloLobby(sala);
        _soloAnfitrion(sala, yo);
        final objetivo = sala.miembro(_texto(msg, 'id'));
        if (objetivo == null || objetivo == yo) {
          throw ErrorJuego('Jugador no encontrado.');
        }
        objetivo.canal?.enviar({'tipo': MsgServidor.expulsado});
        _sacar(sala, objetivo, voluntario: true, avisar: false);
        return;
      case MsgCliente.empezar:
        _empezar(sala, yo);
      case MsgCliente.colocarInicial:
        _partidaEnCurso(
          sala,
        ).colocarInicial(yo.id, _entero(msg, 'indice'), _entero(msg, 'numero'));
      case MsgCliente.quitarInicial:
        _partidaEnCurso(sala).quitarInicial(yo.id, _entero(msg, 'indice'));
      case MsgCliente.confirmarDistribucion:
        _partidaEnCurso(sala).confirmarDistribucion(yo.id);
      case MsgCliente.tirar:
        _partidaEnCurso(sala).tirar(yo.id);
      case MsgCliente.colocar:
        _partidaEnCurso(sala)
            .colocar(yo.id, _entero(msg, 'indice'), _entero(msg, 'ancla'));
      case MsgCliente.pasar:
        _partidaEnCurso(sala).pasar(yo.id);
      case MsgCliente.conceder:
        _partidaEnCurso(sala).conceder(yo.id);
      case MsgCliente.volverAlLobby:
        _volverAlLobby(sala, yo);
      default:
        throw ErrorJuego('Mensaje desconocido.');
    }
    _tras(sala, claveAntes);
  }

  // ---------------------------------------------------------------------
  // Acciones

  void _crearSala(String id, Canal canal, int mapa) {
    if (_salaDe.containsKey(id)) throw ErrorJuego('Ya estás en una sala.');
    if (_salas.length >= config.maxSalas) {
      throw ErrorJuego('El servidor está lleno. Inténtalo más tarde.');
    }
    final nombre = _nombreGuardado(id);
    final yo = Miembro(id, nombre)..canal = canal;
    final sala = Sala(
      codigo: _nuevoCodigo(),
      config: config,
      anfitrion: yo,
      mapa: _mapaValido(mapa),
    )..mensajeLobby = 'Comparte el código para invitar a otros jugadores.';
    _salas[sala.codigo] = sala;
    _salaDe[id] = sala;
    _difundir(sala);
  }

  void _unirse(String id, Canal canal, String codigoCrudo) {
    final codigo = normalizarCodigo(codigoCrudo);
    final existente = _salaDe[id];
    if (existente != null) {
      if (existente.codigo == codigo) {
        _difundir(existente);
        return;
      }
      throw ErrorJuego('Ya estás en otra sala. Sal de ella primero.');
    }
    _revisarFallos(id);
    final sala = _salas[codigo];
    if (sala == null) {
      _registrarFallo(id);
      throw ErrorJuego('No existe ninguna sala con ese código.');
    }
    if (sala.fase != FaseSala.lobby) {
      throw ErrorJuego('Esa partida ya empezó.');
    }
    if (sala.miembros.length >= config.maxJugadores) {
      throw ErrorJuego('La sala está llena.');
    }
    final yo = Miembro(id, sala.nombreLibre(_nombreGuardado(id)))
      ..canal = canal;
    sala.miembros.add(yo);
    _salaDe[id] = sala;
    sala.mensajeLobby = '${yo.nombre} se unió.';
    _difundir(sala);
  }

  void _empezar(Sala sala, Miembro yo) {
    _soloLobby(sala);
    _soloAnfitrion(sala, yo);
    if (sala.miembros.length < config.minJugadores) {
      throw ErrorJuego(
        'Se necesitan al menos ${config.minJugadores} jugadores.',
      );
    }
    final ausente = sala.miembros.where((m) => !m.conectado);
    if (ausente.isNotEmpty) {
      throw ErrorJuego(
        'Hay jugadores desconectados (${ausente.map((m) => m.nombre).join(', ')}).',
      );
    }
    sala.partida = PartidaOnline(
      mapa: sala.mapa,
      jugadores: [for (final m in sala.miembros) (id: m.id, nombre: m.nombre)],
      azar: _azar,
      maxTurnosAgotados: config.maxTurnosAgotados,
    );
  }

  void _volverAlLobby(Sala sala, Miembro yo) {
    final p = sala.partida;
    if (p == null || !p.terminada) {
      throw ErrorJuego('La partida aún no terminó.');
    }
    _soloAnfitrion(sala, yo);
    sala.partida = null;
    for (final m in sala.miembros.where((m) => !m.presente).toList()) {
      sala.miembros.remove(m);
    }
    sala.mensajeLobby = 'Nueva partida: elige mapa y empieza cuando quieras.';
  }

  /// Quita a [m] de la sala: la abandona él ([voluntario]) o se agotó su
  /// plazo de reconexión. Con la partida en marcha cuenta como rendición o
  /// abandono respectivamente.
  void _sacar(
    Sala sala,
    Miembro m, {
    required bool voluntario,
    bool avisar = true,
  }) => _sacarVarios(sala, [m], voluntario: voluntario, avisar: avisar);

  /// Como [_sacar] para varios miembros a la vez: primero se les saca a todos
  /// y después se decide el estado de la partida una sola vez.
  void _sacarVarios(
    Sala sala,
    List<Miembro> salen, {
    required bool voluntario,
    bool avisar = true,
  }) {
    final claveAntes = sala.claveTurno;
    final canales = [for (final m in salen) m.canal];
    for (final m in salen) {
      m.cancelarGracia();
      m.canal = null;
      _salaDe.remove(m.id);
    }

    if (sala.partida == null) {
      for (final m in salen) {
        sala.miembros.remove(m);
      }
      sala.mensajeLobby = salen.length == 1
          ? '${salen.single.nombre} salió.'
          : '${salen.map((m) => m.nombre).join(' y ')} salieron.';
    } else {
      final p = sala.partida!;
      for (final m in salen) {
        m.presente = false;
      }
      if (voluntario) {
        for (final m in salen) {
          if (!p.terminada && p.jugador(m.id)?.participa == true) {
            p.conceder(m.id);
          }
        }
      } else {
        p.abandonarVarios(
          [for (final m in salen) m.id],
          motivo: 'se desconectó y no volvió',
          motivoPlural: 'se desconectaron y no volvieron',
        );
      }
    }
    if (avisar) {
      for (final c in canales) {
        c?.enviar({'tipo': MsgServidor.sinSala});
      }
    }
    for (final m in salen) {
      if (!_canales.containsKey(m.id)) _nombres.remove(m.id);
    }

    if (sala.presentes.isEmpty) {
      _eliminar(sala);
      return;
    }
    _tras(sala, claveAntes);
  }

  /// El anfitrión debe seguir en la sala (y en la partida, si hay una).
  void _reasignarAnfitrion(Sala sala) {
    final p = sala.partida;
    bool apto(Miembro m) =>
        m.presente &&
        (p == null || p.terminada || p.jugador(m.id)?.participa == true);
    final actual = sala.miembro(sala.anfitrionId);
    if (actual != null && apto(actual)) return;
    final nuevo =
        sala.miembros.where(apto).firstOrNull ?? sala.presentes.firstOrNull;
    if (nuevo != null) sala.anfitrionId = nuevo.id;
  }

  void _eliminar(Sala sala) {
    sala.cancelarTemporizadores();
    _salas.remove(sala.codigo);
    for (final m in sala.miembros) {
      if (identical(_salaDe[m.id], sala)) _salaDe.remove(m.id);
    }
  }

  // ---------------------------------------------------------------------
  // Reloj de turno

  /// Tras cualquier cambio: reprograma el reloj si cambió el turno y avisa
  /// a todos. Los cambios ajenos al turno (conexiones, chat...) no lo tocan,
  /// para que nadie pueda alargar un turno ajeno.
  void _tras(Sala sala, String claveAntes) {
    _reasignarAnfitrion(sala);
    if (sala.claveTurno != claveAntes) _programarTurno(sala);
    _difundir(sala);
  }

  void _programarTurno(Sala sala) {
    sala._timerTurno?.cancel();
    sala._timerTurno = null;
    sala.limiteTurno = null;
    if (sala.fase != FaseSala.jugando) return;
    sala.limiteTurno = _ahora().add(config.tiempoTurno);
    sala._timerTurno = Timer(config.tiempoTurno, () => _turnoAgotado(sala));
  }

  void _turnoAgotado(Sala sala) {
    if (_salas[sala.codigo] != sala || sala.fase != FaseSala.jugando) return;
    final claveAntes = sala.claveTurno;
    sala.partida!.tiempoAgotado();
    _tras(sala, claveAntes);
  }

  // ---------------------------------------------------------------------
  // Envío

  void _difundir(Sala sala) {
    final ahora = _ahora();
    for (final m in sala.miembros) {
      final canal = m.canal;
      if (canal == null) continue;
      try {
        canal.enviar({
          'tipo': MsgServidor.estado,
          'sala': sala.estadoPara(m.id, ahora).toJson(),
        });
      } catch (_) {
        // Un canal roto no debe impedir avisar a los demás; su cierre
        // llegará por desconectar().
      }
    }
  }

  /// Apaga todos los temporizadores (al parar el servidor o en pruebas).
  void cerrar() {
    for (final s in _salas.values.toList()) {
      s.cancelarTemporizadores();
    }
    _salas.clear();
    _salaDe.clear();
    _canales.clear();
  }

  // ---------------------------------------------------------------------
  // Validaciones

  String _nombreGuardado(String id) => _nombres[id] ?? id;

  void _revisarFallos(String id) {
    final lista = _fallosUnirse[id];
    if (lista == null) return;
    final desde = _ahora().subtract(config.ventanaFallosUnirse);
    lista.removeWhere((t) => t.isBefore(desde));
    if (lista.length >= config.maxFallosUnirse) {
      throw ErrorJuego('Demasiados códigos incorrectos. Espera un momento.');
    }
  }

  void _registrarFallo(String id) => (_fallosUnirse[id] ??= []).add(_ahora());

  PartidaOnline _partidaEnCurso(Sala sala) {
    final p = sala.partida;
    if (p == null) throw ErrorJuego('La partida aún no empezó.');
    return p;
  }

  static void _soloLobby(Sala sala) {
    if (sala.fase != FaseSala.lobby) {
      throw ErrorJuego('Solo se puede hacer en el lobby.');
    }
  }

  static void _soloAnfitrion(Sala sala, Miembro yo) {
    if (sala.anfitrionId != yo.id) {
      throw ErrorJuego('Solo el anfitrión puede hacer eso.');
    }
  }

  int _mapaValido(int mapa) {
    if (mapa < 0 || mapa >= mapasOficiales.length) {
      throw ErrorJuego('Mapa inválido.');
    }
    return mapa;
  }

  static int _entero(Map<String, Object?> m, String k, {int? porDefecto}) {
    final v = m[k];
    if (v is int) return v;
    if (v == null && porDefecto != null) return porDefecto;
    throw ErrorJuego('Falta el campo "$k".');
  }

  static String _texto(Map<String, Object?> m, String k) {
    final v = m[k];
    if (v is String && v.length <= 64) return v;
    throw ErrorJuego('Falta el campo "$k".');
  }
}
