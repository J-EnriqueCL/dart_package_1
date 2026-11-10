import 'dart:async';
import 'dart:convert';

import 'package:dart_package_1/dart_package_1.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Una conexión falsa: lo que el cliente envía queda en [enviados] y el
/// "servidor" responde con [servidorEnvia].
class CanalWsFalso extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  CanalWsFalso({this.fallaAlConectar = false}) {
    if (fallaAlConectar) {
      _ready.future.ignore();
      _ready.completeError(
        WebSocketChannelException('No se pudo conectar (prueba)'),
      );
    } else {
      _ready.complete();
    }
  }

  final bool fallaAlConectar;
  final _ready = Completer<void>();
  final _entrante = StreamController<dynamic>();
  final enviados = <Map<String, Object?>>[];
  bool cerradoPorCliente = false;
  late final WebSocketSink _sink = _SinkFalso(this);

  @override
  Stream<dynamic> get stream => _entrante.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  Future<void> get ready => _ready.future;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  List<String> get tiposEnviados => [
    for (final m in enviados) m['tipo']! as String,
  ];

  Map<String, Object?>? ultimoDe(String tipo) {
    for (final m in enviados.reversed) {
      if (m['tipo'] == tipo) return m;
    }
    return null;
  }

  void servidorEnvia(Map<String, Object?> mensaje) {
    if (!_entrante.isClosed) _entrante.add(jsonEncode(mensaje));
  }

  void servidorEnviaTexto(String texto) {
    if (!_entrante.isClosed) _entrante.add(texto);
  }

  void servidorEstado(EstadoSala e) =>
      servidorEnvia({'tipo': MsgServidor.estado, 'sala': e.toJson()});

  /// El servidor (o la red) corta la conexión.
  void servidorCierra() {
    if (!_entrante.isClosed) unawaited(_entrante.close());
  }
}

class _SinkFalso implements WebSocketSink {
  _SinkFalso(this._canal);
  final CanalWsFalso _canal;
  final _hecho = Completer<void>();

  @override
  void add(dynamic dato) {
    _canal.enviados.add((jsonDecode(dato as String) as Map).cast());
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) => stream.drain<void>();

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _canal.cerradoPorCliente = true;
    if (!_hecho.isCompleted) _hecho.complete();
  }

  @override
  Future<void> get done => _hecho.future;
}

/// Fábrica de conexiones para el cliente; guarda todas las que se abrieron.
class ServidorFalso {
  final conexiones = <CanalWsFalso>[];

  /// Cuántas conexiones próximas fallarán al abrirse.
  int fallos = 0;

  CanalWsFalso get ultima => conexiones.last;

  WebSocketChannel fabrica(Uri url) {
    final c = CanalWsFalso(fallaAlConectar: fallos > 0);
    if (fallos > 0) fallos--;
    conexiones.add(c);
    return c;
  }
}

/// Casillas del nivel uno con 1..6 en las seis iniciales y lo demás vacío.
List<int?> tableroInicial() {
  final t = List<int?>.filled(49, null);
  var n = 1;
  for (final i in mapasOficiales.first.indicesIniciales) {
    t[i] = n++;
  }
  return t;
}

JugadorSala jugadorSala(
  String id, {
  bool conectado = true,
  int puntos = 0,
  EstadoJugador estado = EstadoJugador.jugando,
  int? gracia,
}) => JugadorSala(
  id: id,
  nombre: id.toUpperCase(),
  conectado: conectado,
  puntos: puntos,
  estado: estado,
  graciaRestante: gracia,
);

EstadoSala estadoSala({
  String yo = 'a',
  FaseSala fase = FaseSala.lobby,
  List<JugadorSala>? jugadores,
  String anfitrion = 'a',
  String? turnoDe,
  int turno = 1,
  List<int>? dados,
  List<int?>? tablero,
  int mapa = 0,
  String mensaje = '',
  ResultadoPartida? resultado,
}) => EstadoSala(
  yo: yo,
  codigo: 'ABC234',
  fase: fase,
  mapa: mapa,
  maxJugadores: 4,
  anfitrion: anfitrion,
  jugadores: jugadores ?? [jugadorSala('a'), jugadorSala('b')],
  turnoDe: turnoDe,
  turno: turno,
  dados: dados,
  tablero: tablero ?? (fase == FaseSala.lobby ? const [] : tableroInicial()),
  mensaje: mensaje,
  segundosTurno: fase == FaseSala.jugando ? 45 : null,
  resultado: resultado,
);
