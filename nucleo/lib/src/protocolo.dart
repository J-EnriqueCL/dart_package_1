import 'dart_package_1_base.dart';
import 'mapas.dart';

/// Nombres de los mensajes del protocolo WebSocket (`/ws`).
///
/// Cada mensaje es un JSON `{"tipo": ..., ...}`. El cliente habla con
/// [MsgCliente] y el servidor responde con [MsgServidor].
abstract final class MsgCliente {
  /// `{token}`: debe ser el primer mensaje de la conexión.
  static const auth = 'auth';
  static const ping = 'ping';

  /// `{mapa}`
  static const crearSala = 'crear_sala';

  /// `{codigo}`
  static const unirse = 'unirse';

  /// `{mapa}` (solo anfitrión, en el lobby)
  static const elegirMapa = 'elegir_mapa';

  /// `{id}` (solo anfitrión, en el lobby)
  static const expulsar = 'expulsar';
  static const empezar = 'empezar';

  /// En el lobby sale de la sala; en partida equivale a rendirse y salir.
  static const salirSala = 'salir_sala';
  static const tirar = 'tirar';

  /// `{indice, ancla}`: `ancla` es la posición (0 o 1) del dado ancla.
  static const colocar = 'colocar';
  static const pasar = 'pasar';
  static const conceder = 'conceder';

  /// Solo con la partida terminada: la sala vuelve al lobby.
  static const volverAlLobby = 'volver_al_lobby';
}

abstract final class MsgServidor {
  /// `{yo, sala}`: foto completa de la sala; se reenvía tras cada cambio.
  static const estado = 'estado';

  /// El usuario no está en ninguna sala.
  static const sinSala = 'sin_sala';

  /// `{codigo, mensaje, fatal?}`
  static const error = 'error';

  /// Un anfitrión te sacó de la sala.
  static const expulsado = 'expulsado';

  /// Otra conexión de la misma cuenta tomó tu lugar.
  static const sesionReemplazada = 'sesion_reemplazada';
  static const pong = 'pong';
}

/// Códigos de [MsgServidor.error] que el cliente trata de forma especial.
abstract final class CodigoError {
  static const autenticacion = 'autenticacion';
  static const noAutenticado = 'no_autenticado';
  static const limite = 'limite';
  static const generico = 'error';
}

enum FaseSala {
  lobby,
  jugando,
  terminada;

  static FaseSala desde(Object? v) => FaseSala.values.firstWhere(
    (f) => f.name == v,
    orElse: () => throw FormatException('Fase inválida: $v'),
  );
}

enum EstadoJugador {
  activo,
  concedio,
  abandono;

  static EstadoJugador desde(Object? v) => EstadoJugador.values.firstWhere(
    (f) => f.name == v,
    orElse: () => throw FormatException('Estado de jugador inválido: $v'),
  );
}

enum MotivoFin {
  tableroCompleto,
  sinMovimientos,

  /// Solo queda un jugador porque los demás se rindieron.
  rendicion,

  /// Solo queda un jugador porque los demás se desconectaron o no jugaron.
  abandono;

  static MotivoFin desde(Object? v) => MotivoFin.values.firstWhere(
    (f) => f.name == v,
    orElse: () => throw FormatException('Motivo inválido: $v'),
  );
}

class JugadorSala {
  const JugadorSala({
    required this.id,
    required this.nombre,
    required this.conectado,
    this.puntos = 0,
    this.estado = EstadoJugador.activo,
    this.graciaRestante,
  });

  final String id;
  final String nombre;
  final bool conectado;
  final int puntos;
  final EstadoJugador estado;

  /// Segundos que le quedan para reconectarse antes de perder su sitio.
  final int? graciaRestante;

  bool get activo => estado == EstadoJugador.activo;

  Map<String, Object?> toJson() => {
    'id': id,
    'nombre': nombre,
    'conectado': conectado,
    'puntos': puntos,
    'estado': estado.name,
    if (graciaRestante != null) 'graciaRestante': graciaRestante,
  };

  factory JugadorSala.fromJson(Map<String, Object?> j) => JugadorSala(
    id: j['id'] as String,
    nombre: j['nombre'] as String,
    conectado: j['conectado'] as bool,
    puntos: j['puntos'] as int,
    estado: EstadoJugador.desde(j['estado']),
    graciaRestante: j['graciaRestante'] as int?,
  );
}

class ResultadoPartida {
  const ResultadoPartida({required this.ganadores, required this.motivo});

  /// Más de uno en caso de empate.
  final List<String> ganadores;
  final MotivoFin motivo;

  Map<String, Object?> toJson() => {
    'ganadores': ganadores,
    'motivo': motivo.name,
  };

  factory ResultadoPartida.fromJson(Map<String, Object?> j) =>
      ResultadoPartida(
        ganadores: (j['ganadores'] as List).cast<String>(),
        motivo: MotivoFin.desde(j['motivo']),
      );
}

/// Foto de una sala tal como la ve un jugador concreto ([yo]).
class EstadoSala {
  const EstadoSala({
    required this.yo,
    required this.codigo,
    required this.fase,
    required this.mapa,
    required this.maxJugadores,
    required this.anfitrion,
    required this.jugadores,
    this.turnoDe,
    this.turno = 1,
    this.dados,
    this.tablero = const [],
    this.mensaje = '',
    this.segundosTurno,
    this.resultado,
  });

  final String yo;
  final String codigo;
  final FaseSala fase;

  /// Índice en [mapasOficiales].
  final int mapa;
  final int maxJugadores;
  final String anfitrion;
  final List<JugadorSala> jugadores;

  /// Quién debe jugar; null fuera de la partida.
  final String? turnoDe;
  final int turno;

  /// Dados tirados en el turno actual, o null si aún no se tiraron.
  final List<int>? dados;

  /// Valor de cada una de las 49 casillas (null = vacía). Vacío en el lobby.
  final List<int?> tablero;

  /// Texto con lo último que pasó (para mostrar a todos).
  final String mensaje;

  /// Segundos que le quedan a [turnoDe] cuando se tomó la foto.
  final int? segundosTurno;
  final ResultadoPartida? resultado;

  bool get soyAnfitrion => anfitrion == yo;
  bool get esMiTurno => fase == FaseSala.jugando && turnoDe == yo;
  MapaOficial get mapaOficial => mapasOficiales[mapa];

  JugadorSala? jugador(String id) {
    for (final j in jugadores) {
      if (j.id == id) return j;
    }
    return null;
  }

  JugadorSala? get miJugador => jugador(yo);

  /// Controlador con el tablero actual, para calcular destinos y áreas.
  ControladorPartida crearControlador() {
    final celdas = mapaOficial.crearTablero();
    for (var i = 0; i < celdas.length && i < tablero.length; i++) {
      final v = tablero[i];
      if (v != null) celdas[i] = celdas[i].copiarCon(valor: v);
    }
    return ControladorPartida(gruposConectados: mapaOficial.gruposConectados)
      ..establecerValoresIniciales(celdas);
  }

  Map<String, Object?> toJson() => {
    'yo': yo,
    'codigo': codigo,
    'fase': fase.name,
    'mapa': mapa,
    'maxJugadores': maxJugadores,
    'anfitrion': anfitrion,
    'jugadores': [for (final j in jugadores) j.toJson()],
    'turnoDe': turnoDe,
    'turno': turno,
    'dados': dados,
    'tablero': tablero,
    'mensaje': mensaje,
    'segundosTurno': segundosTurno,
    'resultado': resultado?.toJson(),
  };

  /// Lanza [FormatException] si el JSON no tiene la forma esperada.
  factory EstadoSala.fromJson(Map<String, Object?> j) {
    try {
      final mapa = j['mapa'] as int;
      if (mapa < 0 || mapa >= mapasOficiales.length) {
        throw FormatException('Mapa inválido: $mapa');
      }
      final tablero = (j['tablero'] as List).cast<int?>();
      if (tablero.isNotEmpty && tablero.length != 49) {
        throw const FormatException('El tablero debe tener 49 casillas.');
      }
      final dados = (j['dados'] as List?)?.cast<int>();
      if (dados != null && dados.length != 2) {
        throw const FormatException('Deben ser dos dados.');
      }
      final res = j['resultado'];
      return EstadoSala(
        yo: j['yo'] as String,
        codigo: j['codigo'] as String,
        fase: FaseSala.desde(j['fase']),
        mapa: mapa,
        maxJugadores: j['maxJugadores'] as int,
        anfitrion: j['anfitrion'] as String,
        jugadores: [
          for (final e in j['jugadores'] as List)
            JugadorSala.fromJson((e as Map).cast<String, Object?>()),
        ],
        turnoDe: j['turnoDe'] as String?,
        turno: j['turno'] as int,
        dados: dados,
        tablero: tablero,
        mensaje: j['mensaje'] as String,
        segundosTurno: j['segundosTurno'] as int?,
        resultado: res == null
            ? null
            : ResultadoPartida.fromJson((res as Map).cast<String, Object?>()),
      );
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('Estado de sala inválido: $e');
    }
  }
}
