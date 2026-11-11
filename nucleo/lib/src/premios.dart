/// Meta de puntos del multijugador según el número de jugadores al empezar.
const metasPorJugadores = <int, int>{2: 26, 3: 24, 4: 22, 5: 20};

/// Mínimo y máximo de jugadores de una sala en línea.
const minJugadoresEnLinea = 2;
const maxJugadoresEnLinea = 5;

/// Meta para [jugadores] participantes (null si el número no es válido).
int? metaPara(int jugadores) => metasPorJugadores[jugadores];

/// Unidad de puntuación competitiva: un conjunto de casillas (que puede tener
/// partes separadas) con tres premios, de primera, segunda y tercera posición.
///
/// No es lo mismo que una región de validación de las reglas de colocación ni
/// que una casilla: cada grupo es independiente aunque comparta color con otro.
class GrupoPremio {
  const GrupoPremio({
    required this.id,
    required this.casillas,
    required this.premios,
  });

  /// Identificador estable, p. ej. `N1-a0` (nivel y casilla de menor índice).
  final String id;
  final List<int> casillas;

  /// Puntos de la 1.ª, 2.ª y 3.ª posición.
  final List<int> premios;

  int get niveles => premios.length;

  /// ¿Están ocupadas todas las casillas en [tablero]?
  bool completo(List<int?> tablero) =>
      casillas.every((i) => i < tablero.length && tablero[i] != null);
}

/// Un premio (o su ausencia) adjudicado al liquidar una ronda.
class Adjudicacion {
  const Adjudicacion({
    required this.ronda,
    required this.jugador,
    required this.grupo,
    required this.nivel,
    required this.puntos,
  });

  /// Ronda cuyo cierre la liquidó (0 = al terminar la preparación).
  final int ronda;
  final String jugador;
  final String grupo;

  /// Posición obtenida (1, 2 o 3); 0 si completó el grupo sin premio porque ya
  /// se habían agotado.
  final int nivel;
  final int puntos;

  Map<String, Object?> toJson() => {
    'ronda': ronda,
    'jugador': jugador,
    'grupo': grupo,
    'nivel': nivel,
    'puntos': puntos,
  };

  factory Adjudicacion.fromJson(Map<String, Object?> j) => Adjudicacion(
    ronda: j['ronda'] as int,
    jugador: j['jugador'] as String,
    grupo: j['grupo'] as String,
    nivel: j['nivel'] as int,
    puntos: j['puntos'] as int,
  );
}

/// Estado público de un grupo: quién ocupa cada nivel de premio.
class ReclamacionGrupo {
  const ReclamacionGrupo({
    required this.grupo,
    this.niveles = const [],
    this.sinPremio = const [],
  });

  final String grupo;

  /// Jugadores de cada nivel ya usado (un empate comparte un nivel).
  final List<List<String>> niveles;

  /// Quienes completaron el grupo cuando ya no quedaban premios.
  final List<String> sinPremio;

  Map<String, Object?> toJson() => {
    'grupo': grupo,
    'niveles': niveles,
    'sinPremio': sinPremio,
  };

  factory ReclamacionGrupo.fromJson(Map<String, Object?> j) => ReclamacionGrupo(
    grupo: j['grupo'] as String,
    niveles: [for (final n in j['niveles'] as List) (n as List).cast<String>()],
    sinPremio: (j['sinPremio'] as List).cast<String>(),
  );
}

/// Historial competitivo de premios de una partida (lo guarda el servidor).
///
/// Reglas:
/// * Cada grupo tiene tantos niveles de premio como [GrupoPremio.premios].
/// * Quienes completan un grupo **en la misma ronda** (o todos a la vez al
///   terminar la preparación) comparten el siguiente nivel libre; el orden de
///   llegada de sus mensajes no cuenta.
/// * El siguiente grupo de jugadores recibe el siguiente nivel.
/// * Un jugador cobra una sola vez por grupo.
/// * Completar un grupo con todos los niveles agotados concede 0 puntos.
class LibroPremios {
  LibroPremios(this.grupos)
    : _niveles = {for (final g in grupos) g.id: <List<String>>[]},
      _sinPremio = {for (final g in grupos) g.id: <String>[]},
      _reclamaron = {for (final g in grupos) g.id: <String>{}};

  final List<GrupoPremio> grupos;
  final Map<String, List<List<String>>> _niveles;
  final Map<String, List<String>> _sinPremio;
  final Map<String, Set<String>> _reclamaron;

  GrupoPremio? grupo(String id) {
    for (final g in grupos) {
      if (g.id == id) return g;
    }
    return null;
  }

  /// ¿Ya completó [jugador] este grupo (con o sin premio) en liquidaciones
  /// anteriores?
  bool yaReclamo(String grupo, String jugador) =>
      _reclamaron[grupo]?.contains(jugador) ?? false;

  /// Grupos completos en [tablero].
  List<String> gruposCompletos(List<int?> tablero) => [
    for (final g in grupos)
      if (g.completo(tablero)) g.id,
  ];

  /// Liquida las finalizaciones de una ronda: [completan] asocia cada grupo
  /// con los jugadores que lo completaron en ella. El resultado no depende del
  /// orden de los mapas ni de los conjuntos.
  List<Adjudicacion> liquidar(int ronda, Map<String, Set<String>> completan) {
    final resultado = <Adjudicacion>[];
    final ids = completan.keys.toList()..sort();
    for (final id in ids) {
      final g = grupo(id);
      if (g == null) continue;
      final nuevos = [
        for (final j in completan[id]!)
          if (!yaReclamo(id, j)) j,
      ]..sort();
      if (nuevos.isEmpty) continue;
      final usados = _niveles[id]!;
      if (usados.length < g.niveles) {
        final nivel = usados.length + 1;
        usados.add(nuevos);
        for (final j in nuevos) {
          resultado.add(
            Adjudicacion(
              ronda: ronda,
              jugador: j,
              grupo: id,
              nivel: nivel,
              puntos: g.premios[nivel - 1],
            ),
          );
        }
      } else {
        _sinPremio[id]!.addAll(nuevos);
        for (final j in nuevos) {
          resultado.add(
            Adjudicacion(
              ronda: ronda,
              jugador: j,
              grupo: id,
              nivel: 0,
              puntos: 0,
            ),
          );
        }
      }
      _reclamaron[id]!.addAll(nuevos);
    }
    return resultado;
  }

  /// Estado público de cada grupo.
  List<ReclamacionGrupo> get reclamaciones => [
    for (final g in grupos)
      ReclamacionGrupo(
        grupo: g.id,
        niveles: [for (final n in _niveles[g.id]!) List<String>.of(n)],
        sinPremio: List<String>.of(_sinPremio[g.id]!),
      ),
  ];
}
