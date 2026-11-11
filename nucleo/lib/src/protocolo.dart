import 'dart_package_1_base.dart';
import 'mapas.dart';
import 'preparacion.dart';
import 'premios.dart';

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

  /// `{ronda}`: lanza los dados compartidos de la ronda (solo con la ronda en
  /// `esperandoTirada`; la primera solicitud válida genera la única tirada).
  static const tirar = 'tirar';

  /// `{indice, numero}`: pone un número del 1 al 6 en una de las seis
  /// posiciones iniciales de tu tablero (solo en la preparación).
  static const colocarInicial = 'colocar_inicial';

  /// `{indice}`: retira el número de una posición inicial (solo antes de
  /// confirmar).
  static const quitarInicial = 'quitar_inicial';

  /// Confirma la distribución inicial; después ya no se puede cambiar.
  static const confirmarDistribucion = 'confirmar_distribucion';

  /// `{ronda, indice, ancla}`: confirma la jugada de la ronda en tu propio
  /// tablero. `ancla` es la posición (0 o 1) del dado ancla.
  static const confirmarJugada = 'confirmar_jugada';

  /// `{ronda}`: no colocas nada en esta ronda (se puede aunque haya jugadas).
  static const pasarRonda = 'pasar_ronda';
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

  /// Cada jugador reparte el 1..6 en las posiciones iniciales de su tablero.
  preparacion,
  jugando,
  terminada;

  static FaseSala desde(Object? v) => FaseSala.values.firstWhere(
    (f) => f.name == v,
    orElse: () => throw FormatException('Fase inválida: $v'),
  );
}

/// Situación de un jugador en la partida. La conexión temporal es aparte
/// ([JugadorSala.conectado]): perder la red no cambia este estado.
/// Fase de una ronda.
enum FaseRonda {
  /// Nadie ha tirado: cualquier jugador que siga jugando puede hacerlo.
  esperandoTirada,

  /// Hay dados compartidos y los participantes resuelven a la vez.
  resolviendo;

  static FaseRonda desde(Object? v) => FaseRonda.values.firstWhere(
    (f) => f.name == v,
    orElse: () => throw FormatException('Fase de ronda inválida: $v'),
  );
}

/// Cómo ha resuelto un jugador la ronda abierta. Quien no responde en plazo no
/// aparece aquí: se anota en el mensaje y la ronda se cierra.
enum Resolucion {
  pendiente,
  confirmo,
  paso;

  static Resolucion desde(Object? v) => Resolucion.values.firstWhere(
    (f) => f.name == v,
    orElse: () => throw FormatException('Resolución inválida: $v'),
  );
}

class RondaSala {
  const RondaSala({
    required this.id,
    required this.fase,
    this.dados,
    this.resoluciones = const {},
    this.segundos,
  });

  /// Identificador de la ronda. Sube al cerrarse; las acciones lo incluyen.
  final int id;
  final FaseRonda fase;

  /// Los dos dados compartidos, o null en `esperandoTirada`.
  final List<int>? dados;

  /// Participantes que deben resolver la ronda y cómo van. Vacío si no hay
  /// ronda abierta.
  final Map<String, Resolucion> resoluciones;

  /// Segundos que quedan del plazo común cuando se tomó la foto.
  final int? segundos;

  bool get abierta => fase == FaseRonda.resolviendo;

  List<String> get pendientes => [
    for (final e in resoluciones.entries)
      if (e.value == Resolucion.pendiente) e.key,
  ];

  Map<String, Object?> toJson() => {
    'id': id,
    'fase': fase.name,
    'dados': dados,
    'resoluciones': {for (final e in resoluciones.entries) e.key: e.value.name},
    'segundos': segundos,
  };

  factory RondaSala.fromJson(Map<String, Object?> j) {
    final dados = (j['dados'] as List?)?.cast<int>();
    if (dados != null && dados.length != 2) {
      throw const FormatException('Deben ser dos dados.');
    }
    return RondaSala(
      id: j['id'] as int,
      fase: FaseRonda.desde(j['fase']),
      dados: dados,
      resoluciones: {
        for (final e in (j['resoluciones'] as Map).entries)
          e.key as String: Resolucion.desde(e.value),
      },
      segundos: j['segundos'] as int?,
    );
  }
}

enum EstadoJugador {
  /// Preparación: todavía coloca sus números iniciales.
  preparando,

  /// Preparación: distribución confirmada, espera a los demás.
  listo,

  /// Partida: tiene jugadas posibles.
  jugando,

  /// Partida: llenó su tablero o ya no existe ninguna jugada legal. Conserva
  /// sus puntos y sigue siendo candidato a ganar.
  terminado,

  /// Se rindió: conserva su puntuación pero no puede ganar.
  concedio,

  /// Se fue o no volvió: conserva su puntuación pero no puede ganar.
  abandono;

  static EstadoJugador desde(Object? v) => EstadoJugador.values.firstWhere(
    (f) => f.name == v,
    orElse: () => throw FormatException('Estado de jugador inválido: $v'),
  );
}

enum MotivoFin {
  /// Al cerrar una ronda (y liquidar sus premios), algún jugador elegible
  /// alcanzó o superó la meta: gana el de más puntos.
  meta,

  /// Todos los jugadores que no se rindieron ni abandonaron terminaron su
  /// tablero: gana quien tenga más puntos.
  todosTerminaron,

  /// Queda como máximo un jugador porque los demás se rindieron.
  rendicion,

  /// Queda como máximo un jugador porque los demás se desconectaron o no
  /// jugaron.
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
    this.estado = EstadoJugador.preparando,
    this.graciaRestante,
  });

  final String id;
  final String nombre;
  final bool conectado;
  final int puntos;
  final EstadoJugador estado;

  /// Segundos que le quedan para reconectarse antes de perder su sitio.
  final int? graciaRestante;

  /// Sigue en la partida y puede ganar (no se rindió ni abandonó).
  bool get participa =>
      estado != EstadoJugador.concedio && estado != EstadoJugador.abandono;

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

  factory ResultadoPartida.fromJson(Map<String, Object?> j) => ResultadoPartida(
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
    this.ronda,
    this.meta,
    this.reclamaciones = const [],
    this.misPendientes = const [],
    this.liquidacion = const [],
    this.tablero = const [],
    this.mensaje = '',
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

  /// Ronda en curso; null fuera de la partida (lobby, preparación, final).
  final RondaSala? ronda;

  /// Meta de puntos, fijada al empezar según los jugadores; null antes.
  final int? meta;

  /// Premios por grupo: quién ocupa cada nivel (solo lo ya liquidado).
  final List<ReclamacionGrupo> reclamaciones;

  /// Mis grupos completados en la ronda abierta, todavía sin liquidar: su
  /// premio se decide al cerrar la ronda y no cuenta como definitivo.
  final List<String> misPendientes;

  /// Última liquidación (al cerrar la ronda indicada en cada elemento).
  final List<Adjudicacion> liquidacion;

  /// Tablero **propio** de quien recibe el estado: valor de cada una de las 49
  /// casillas (null = vacía). Vacío en el lobby. Los tableros rivales no se
  /// envían; de ellos solo se ve el marcador.
  final List<int?> tablero;

  /// Texto con lo último que pasó (para mostrar a todos).
  final String mensaje;

  final ResultadoPartida? resultado;

  bool get soyAnfitrion => anfitrion == yo;

  /// Reclamación pública de un grupo, o una vacía si nadie lo ha liquidado.
  ReclamacionGrupo reclamacionDe(String grupo) {
    for (final r in reclamaciones) {
      if (r.grupo == grupo) return r;
    }
    return ReclamacionGrupo(grupo: grupo);
  }

  /// Dados compartidos de la ronda abierta, o null si aún no se tiraron.
  List<int>? get dados => ronda?.dados;

  /// Mi resolución en la ronda abierta; null si no participo en ella.
  Resolucion? get miResolucion => ronda?.resoluciones[yo];

  /// Estoy en la ronda abierta y aún no confirmé ni pasé.
  bool get estoyPendiente =>
      fase == FaseSala.jugando &&
      (ronda?.abierta ?? false) &&
      miResolucion == Resolucion.pendiente;

  /// Puedo pulsar "Tirar dados": ronda en espera y sigo jugando.
  bool get puedoTirar =>
      fase == FaseSala.jugando &&
      ronda?.fase == FaseRonda.esperandoTirada &&
      miJugador?.estado == EstadoJugador.jugando;
  MapaOficial get mapaOficial => mapasOficiales[mapa];

  JugadorSala? jugador(String id) {
    for (final j in jugadores) {
      if (j.id == id) return j;
    }
    return null;
  }

  JugadorSala? get miJugador => jugador(yo);

  /// Números del 1 al 6 que aún no están colocados en mi tablero.
  List<int> get numerosPorColocar => numerosPendientes(
    mapaOficial,
    tablero.isEmpty ? List<int?>.filled(49, null) : tablero,
  );

  /// Controlador con mi tablero actual, para calcular destinos y áreas. Admite
  /// una preparación incompleta.
  ControladorPartida crearControlador() {
    final celdas = mapaOficial.crearTablero();
    for (var i = 0; i < celdas.length && i < tablero.length; i++) {
      final v = tablero[i];
      if (v != null) celdas[i] = celdas[i].copiarCon(valor: v);
    }
    return ControladorPartida(gruposConectados: mapaOficial.gruposConectados)
      ..establecerTableroProvisional(celdas);
  }

  Map<String, Object?> toJson() => {
    'yo': yo,
    'codigo': codigo,
    'fase': fase.name,
    'mapa': mapa,
    'maxJugadores': maxJugadores,
    'anfitrion': anfitrion,
    'jugadores': [for (final j in jugadores) j.toJson()],
    'ronda': ronda?.toJson(),
    'meta': meta,
    'reclamaciones': [for (final r in reclamaciones) r.toJson()],
    'misPendientes': misPendientes,
    'liquidacion': [for (final a in liquidacion) a.toJson()],
    'tablero': tablero,
    'mensaje': mensaje,
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
      final ronda = j['ronda'];
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
        ronda: ronda == null
            ? null
            : RondaSala.fromJson((ronda as Map).cast<String, Object?>()),
        meta: j['meta'] as int?,
        reclamaciones: [
          for (final r in (j['reclamaciones'] as List? ?? const []))
            ReclamacionGrupo.fromJson((r as Map).cast<String, Object?>()),
        ],
        misPendientes: (j['misPendientes'] as List? ?? const []).cast<String>(),
        liquidacion: [
          for (final a in (j['liquidacion'] as List? ?? const []))
            Adjudicacion.fromJson((a as Map).cast<String, Object?>()),
        ],
        tablero: tablero,
        mensaje: j['mensaje'] as String,
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
