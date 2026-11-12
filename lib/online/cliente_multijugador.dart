import 'dart:async';
import 'dart:convert';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../auth/config_servidor.dart' show urlWebSocketDe;
import '../dart_package_1.dart';

typedef FabricaCanal = WebSocketChannel Function(Uri url);

enum EstadoConexion {
  /// Aún no se intentó o se cerró a propósito.
  desconectado,

  /// Primera conexión en curso.
  conectando,
  conectado,

  /// Se perdió la conexión y se está reintentando.
  reconectando,
}

/// Dirección del WebSocket a partir de la del servidor HTTP (`http` → `ws`,
/// `https` → `wss`), conservando el prefijo de ruta y añadiendo `/ws`.
Uri urlWebSocket(Uri base) => urlWebSocketDe(base);

/// Conexión con el servidor para jugar en línea.
///
/// Se encarga de autenticarse, de enviar las acciones y de **recuperarse de
/// los cortes**: si la conexión se cae (o el servidor deja de responder) se
/// reintenta sola con espera creciente. Al volver, el servidor reenvía el
/// estado de la sala, así que el jugador sigue donde estaba.
class ClienteMultijugador extends ChangeNotifier {
  ClienteMultijugador({
    required this.url,
    required this.token,
    FabricaCanal? fabrica,
    this.intervaloPing = const Duration(seconds: 10),
    this.silencioMaximo = const Duration(seconds: 30),
    this.esperaRespuesta = const Duration(seconds: 10),
    this.esperasReintento = const [
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
      Duration(seconds: 8),
    ],
    this.maxIntentos = 10,
    this.umbralSegundoPlano = const Duration(seconds: 2),
  }) : _fabrica = fabrica ?? WebSocketChannel.connect;

  final Uri url;

  /// Devuelve el JWT vigente; null si ya no hay sesión.
  final String? Function() token;
  final FabricaCanal _fabrica;
  final Duration intervaloPing;
  final Duration silencioMaximo;
  final Duration esperaRespuesta;
  final List<Duration> esperasReintento;
  final int maxIntentos;

  /// Si la app estuvo en segundo plano al menos este tiempo, al volver se
  /// reconecta sin esperar (el sistema pudo haber matado el socket).
  final Duration umbralSegundoPlano;

  WebSocketChannel? _canal;
  StreamSubscription<dynamic>? _suscripcion;
  Timer? _timerPing;
  Timer? _timerReintento;
  Timer? _timerEspera;
  // Relojes monotónicos: no les afecta que el usuario o la red cambien la hora
  // del dispositivo. Nunca se usa la hora del dispositivo para decidir nada
  // sobre la partida; el servidor es quien manda en los tiempos.
  final Stopwatch _silencio = Stopwatch()..start();
  final Stopwatch _desdeEstado = Stopwatch();
  final Stopwatch _enSegundoPlano = Stopwatch();
  bool _segundoPlano = false;
  bool _cerrado = false;
  bool _autenticado = false;

  EstadoConexion _conexion = EstadoConexion.desconectado;
  int _intento = 0;
  EstadoSala? _sala;
  String? _errorFatal;
  bool _sesionInvalida = false;
  bool _esperando = false;

  /// El jugador pidió salir de la sala (para no avisar de una pérdida ajena).
  bool _salidaPedida = false;
  final _avisos = StreamController<String>.broadcast();

  EstadoConexion get conexion => _conexion;

  /// Intento de reconexión en curso (1 es el primero).
  int get intento => _intento;

  /// El servidor ya respondió a la autenticación en esta conexión.
  bool get autenticado => _autenticado;

  /// Sala en la que está el jugador; null si no está en ninguna.
  EstadoSala? get sala => _sala;

  /// Tiempo transcurrido desde la última foto de la sala. Se resta a los
  /// segundos que mandó el servidor para mostrar los cuentas atrás.
  Duration get desdeUltimoEstado => _desdeEstado.elapsed;

  /// Motivo por el que ya no se puede seguir jugando; null si todo bien.
  String? get errorFatal => _errorFatal;

  /// El fallo fatal se debe a que la sesión caducó o es inválida.
  bool get sesionInvalida => _sesionInvalida;

  /// Hay una acción enviada pendiente de respuesta.
  bool get esperando => _esperando;

  /// Mensajes para mostrar al usuario (errores de juego, expulsión...).
  Stream<String> get avisos => _avisos.stream;

  // ---------------------------------------------------------------------
  // Conexión

  /// Abre la conexión (o la reabre tras un fallo fatal).
  void conectar() {
    if (_cerrado) return;
    _timerReintento?.cancel();
    _errorFatal = null;
    _sesionInvalida = false;
    _intento = 0;
    _conexion = EstadoConexion.conectando;
    notifyListeners();
    _abrir();
  }

  void _abrir() {
    if (_cerrado) return;
    final jwt = token();
    if (jwt == null) {
      _fatal('Tu sesión terminó. Vuelve a iniciar sesión.', sesion: true);
      return;
    }
    _soltarCanal();
    _autenticado = false;
    final WebSocketChannel canal;
    try {
      canal = _fabrica(url);
    } catch (_) {
      _perdido();
      return;
    }
    _canal = canal;
    _silencio.reset();
    _suscripcion = canal.stream.listen(
      _alRecibir,
      onDone: () => _alCerrarCanal(canal),
      onError: (Object _) => _alCerrarCanal(canal),
      cancelOnError: true,
    );
    canal.ready.then((_) {
      if (!identical(canal, _canal) || _cerrado) return;
      _enviarCrudo({'tipo': MsgCliente.auth, 'token': jwt});
      _iniciarLatido();
    }, onError: (Object _) => _alCerrarCanal(canal));
  }

  void _soltarCanal() {
    _timerPing?.cancel();
    _timerPing = null;
    _suscripcion?.cancel();
    _suscripcion = null;
    final c = _canal;
    _canal = null;
    if (c != null) {
      unawaited(c.sink.close().catchError((Object _) {}));
    }
  }

  void _iniciarLatido() {
    _timerPing?.cancel();
    _timerPing = Timer.periodic(intervaloPing, (_) {
      if (_silencio.elapsed > silencioMaximo) {
        // El servidor no contesta: la conexión está muerta aunque no lo diga.
        final c = _canal;
        if (c != null) _alCerrarCanal(c);
        return;
      }
      _enviarCrudo({'tipo': MsgCliente.ping});
    });
  }

  void _alCerrarCanal(WebSocketChannel canal) {
    if (!identical(canal, _canal) || _cerrado) return;
    _perdido();
  }

  /// Se perdió la conexión: reintentar o rendirse.
  void _perdido() {
    _soltarCanal();
    _autenticado = false;
    _esperando = false;
    _timerEspera?.cancel();
    if (_errorFatal != null) return;
    if (_intento >= maxIntentos) {
      _fatal('No se pudo reconectar con el servidor.');
      return;
    }
    final espera =
        esperasReintento[_intento.clamp(0, esperasReintento.length - 1)];
    _intento++;
    _conexion = EstadoConexion.reconectando;
    notifyListeners();
    _timerReintento?.cancel();
    _timerReintento = Timer(espera, _abrir);
  }

  /// Avisa de que la app pasó a segundo plano o volvió.
  ///
  /// En segundo plano el sistema puede congelar o matar el socket sin que la
  /// app se entere. Al volver, si pasó el umbral, se abre una conexión nueva:
  /// el servidor la asocia a la misma cuenta y devuelve la sala si aún está
  /// dentro del plazo de reconexión.
  void cicloDeVida(AppLifecycleState estado) {
    if (_cerrado) return;
    switch (estado) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (!_segundoPlano) {
          _segundoPlano = true;
          _enSegundoPlano
            ..reset()
            ..start();
        }
      case AppLifecycleState.resumed:
        if (!_segundoPlano) return;
        _segundoPlano = false;
        final fuera = _enSegundoPlano.elapsed;
        _enSegundoPlano
          ..stop()
          ..reset();
        if (fuera >= umbralSegundoPlano) reconectarAhora();
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// Descarta la conexión actual y abre otra ya, sin esperar el reintento.
  void reconectarAhora() {
    if (_cerrado || _errorFatal != null) return;
    if (_conexion == EstadoConexion.desconectado) return;
    _timerReintento?.cancel();
    _timerEspera?.cancel();
    _soltarCanal();
    _autenticado = false;
    _esperando = false;
    _intento = 1;
    _conexion = EstadoConexion.reconectando;
    notifyListeners();
    _abrir();
  }

  void _fatal(String mensaje, {bool sesion = false}) {
    _soltarCanal();
    _timerReintento?.cancel();
    _timerEspera?.cancel();
    _autenticado = false;
    _esperando = false;
    _errorFatal = mensaje;
    _sesionInvalida = sesion;
    _conexion = EstadoConexion.desconectado;
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Mensajes del servidor

  void _alRecibir(dynamic dato) {
    _silencio.reset();
    Map<String, Object?> msg;
    try {
      final d = jsonDecode(dato as String);
      if (d is! Map) return;
      msg = d.cast<String, Object?>();
    } catch (_) {
      return;
    }

    switch (msg['tipo']) {
      case MsgServidor.estado:
        try {
          _sala = EstadoSala.fromJson(
            (msg['sala'] as Map).cast<String, Object?>(),
          );
        } catch (_) {
          _avisar('El servidor envió datos que no se entienden.');
          return;
        }
        _desdeEstado
          ..reset()
          ..start();
        _listo();
      case MsgServidor.sinSala:
        // Si estaba en una sala y no pidió salir, la perdió: por ejemplo, el
        // servidor se reinició o se agotó su plazo de reconexión.
        if (_sala != null && !_salidaPedida) {
          _avisar(
            'Ya no estás en la sala: se cerró o se agotó el tiempo para volver.',
          );
        }
        _salidaPedida = false;
        _sala = null;
        _listo();
      case MsgServidor.expulsado:
        _sala = null;
        _avisar('El anfitrión te sacó de la sala.');
        _listo();
      case MsgServidor.sesionReemplazada:
        _fatal('Abriste tu cuenta en otro lugar y esta conexión se cerró.');
      case MsgServidor.error:
        final texto = msg['mensaje'] as String? ?? 'Error inesperado.';
        if (msg['fatal'] == true) {
          _fatal(texto, sesion: msg['codigo'] == CodigoError.autenticacion);
        } else {
          _avisar(texto);
          _finEspera();
        }
      case MsgServidor.pong:
        break;
    }
  }

  /// La respuesta a la autenticación o a una acción llegó.
  void _listo() {
    _autenticado = true;
    _intento = 0;
    _conexion = EstadoConexion.conectado;
    _finEspera(notificar: false);
    notifyListeners();
  }

  void _finEspera({bool notificar = true}) {
    _timerEspera?.cancel();
    if (_esperando) {
      _esperando = false;
      if (notificar) notifyListeners();
    }
  }

  void _avisar(String texto) {
    if (!_avisos.isClosed) _avisos.add(texto);
  }

  // ---------------------------------------------------------------------
  // Acciones

  void _enviarCrudo(Map<String, Object?> msg) {
    try {
      _canal?.sink.add(jsonEncode(msg));
    } catch (_) {
      // El cierre se detecta por el stream.
    }
  }

  /// Envía una acción de juego. Devuelve false si no hay conexión.
  bool _accion(Map<String, Object?> msg) {
    if (_conexion != EstadoConexion.conectado || !_autenticado) {
      _avisar('Sin conexión con el servidor. Reintentando…');
      return false;
    }
    if (_esperando) return false;
    _esperando = true;
    _timerEspera?.cancel();
    _timerEspera = Timer(esperaRespuesta, () => _finEspera());
    notifyListeners();
    _enviarCrudo(msg);
    return true;
  }

  bool crearSala(int mapa) =>
      _accion({'tipo': MsgCliente.crearSala, 'mapa': mapa});
  bool unirse(String codigo) =>
      _accion({'tipo': MsgCliente.unirse, 'codigo': codigo});
  bool elegirMapa(int mapa) =>
      _accion({'tipo': MsgCliente.elegirMapa, 'mapa': mapa});
  bool expulsar(String id) => _accion({'tipo': MsgCliente.expulsar, 'id': id});
  bool empezar() => _accion({'tipo': MsgCliente.empezar});
  bool colocarInicial(int indice, int numero) => _accion({
    'tipo': MsgCliente.colocarInicial,
    'indice': indice,
    'numero': numero,
  });
  bool quitarInicial(int indice) =>
      _accion({'tipo': MsgCliente.quitarInicial, 'indice': indice});
  bool confirmarDistribucion() =>
      _accion({'tipo': MsgCliente.confirmarDistribucion});

  /// Pide lanzar los dados de la ronda [ronda]. El servidor los sortea.
  bool tirar(int ronda) => _accion({'tipo': MsgCliente.tirar, 'ronda': ronda});

  /// Confirma la jugada de la ronda [ronda] (envío y aplicación definitivos).
  bool confirmarJugada(int ronda, int indice, int ancla) => _accion({
    'tipo': MsgCliente.confirmarJugada,
    'ronda': ronda,
    'indice': indice,
    'ancla': ancla,
  });

  /// No colocar nada en la ronda [ronda].
  bool pasarRonda(int ronda) =>
      _accion({'tipo': MsgCliente.pasarRonda, 'ronda': ronda});
  bool conceder() => _accion({'tipo': MsgCliente.conceder});
  bool volverAlLobby() => _accion({'tipo': MsgCliente.volverAlLobby});
  bool salirSala() {
    final ok = _accion({'tipo': MsgCliente.salirSala});
    if (ok) _salidaPedida = true;
    return ok;
  }

  /// Cierra la conexión definitivamente. Si hay conexión y el jugador está en
  /// una sala, antes avisa de que se va (en partida cuenta como rendición);
  /// si no hay conexión, el servidor lo da por abandonado tras su plazo.
  void cerrar() {
    if (_cerrado) return;
    if (_sala != null && _autenticado) {
      _enviarCrudo({'tipo': MsgCliente.salirSala});
    }
    _cerrado = true;
    _timerReintento?.cancel();
    _timerEspera?.cancel();
    _soltarCanal();
    _conexion = EstadoConexion.desconectado;
    unawaited(_avisos.close());
  }

  @override
  void dispose() {
    cerrar();
    super.dispose();
  }
}
