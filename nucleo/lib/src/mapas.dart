import 'dart_package_1_base.dart';
import 'premios.dart';

/// Un mapa oficial: disposición de colores 7x7 y casillas iniciales.
///
/// Letras de [plano]: A = amarillo, V = verde, B = azul, R = rojo, M = morado.
/// N = naranja, W = blanco (gris en la foto oficial).
class MapaOficial {
  const MapaOficial({
    required this.nombre,
    required this.plano,
    required this.indicesIniciales,
    this.gruposConectados = const [],
    this.gruposPremio = const [],
  });

  final String nombre;
  final List<String> plano;

  /// Seis casillas (índices 0..48) que reciben los números 1..6.
  final List<int> indicesIniciales;

  /// Casillas no contiguas que forman una misma área (p. ej. las esquinas
  /// amarillas del nivel 1).
  final List<Set<int>> gruposConectados;

  /// Unidades de puntuación competitiva del multijugador (premios por orden de
  /// completar). Vacío = el mapa todavía no tiene su tabla validada y no está
  /// disponible en línea (sigue disponible en el modo individual).
  final List<GrupoPremio> gruposPremio;

  /// ¿Se puede jugar este mapa en el multijugador?
  bool get disponibleEnLinea => gruposPremio.isNotEmpty;

  /// Nombre legible de un grupo, p. ej. "Azul (casilla 2)".
  String etiquetaDe(GrupoPremio g) {
    final region = crearTablero()[g.casillas.first].region.nombre;
    return '$region (casilla ${g.casillas.reduce((a, b) => a < b ? a : b)})';
  }

  List<Celda> crearTablero() {
    final celdas = <Celda>[];

    for (var fila = 0; fila < 7; fila++) {
      for (var columna = 0; columna < 7; columna++) {
        celdas.add(
          Celda(
            region: _regionDeLetra(plano[fila][columna]),
            esInicial: indicesIniciales.contains(fila * 7 + columna),
          ),
        );
      }
    }

    return celdas;
  }
}

Region _regionDeLetra(String letra) {
  switch (letra) {
    case 'V':
      return Region.verde;
    case 'B':
      return Region.azul;
    case 'A':
      return Region.amarillo;
    case 'R':
      return Region.rojo;
    case 'M':
      return Region.morado;
    case 'N':
      return Region.naranja;
    case 'W':
      return Region.blanco;
    default:
      throw ArgumentError('Color no reconocido: $letra');
  }
}

const mapasOficiales = <MapaOficial>[
  MapaOficial(
    nombre: 'Nivel 1',
    plano: [
      'AVBMMMA',
      'VVBBMMV',
      'VRRBMVV',
      'VRMAVVV',
      'VRMMRRB',
      'RRMRRBB',
      'AMMRRBA',
    ],
    indicesIniciales: [2, 12, 22, 25, 37, 46],
    gruposConectados: [
      {0, 6, 24, 42, 48},
    ],
    // Provisional (primera prueba en teléfonos): agrupación y premios leídos
    // de la imagen del tablero; cada grupo es independiente aunque comparta
    // color con otro.
    gruposPremio: [
      GrupoPremio(
        id: 'N1-a0',
        casillas: [0, 6, 24, 42, 48],
        premios: [8, 6, 4],
      ),
      GrupoPremio(
        id: 'N1-a1',
        casillas: [1, 7, 8, 14, 21, 28],
        premios: [4, 3, 2],
      ),
      GrupoPremio(id: 'N1-a2', casillas: [2, 9, 10, 17], premios: [7, 5, 3]),
      GrupoPremio(
        id: 'N1-a3',
        casillas: [3, 4, 5, 11, 12, 18],
        premios: [6, 4, 2],
      ),
      GrupoPremio(
        id: 'N1-a13',
        casillas: [13, 19, 20, 25, 26, 27],
        premios: [4, 3, 2],
      ),
      GrupoPremio(
        id: 'N1-a15',
        casillas: [15, 16, 22, 29, 35, 36],
        premios: [6, 4, 2],
      ),
      GrupoPremio(
        id: 'N1-a23',
        casillas: [23, 30, 31, 37, 43, 44],
        premios: [6, 4, 2],
      ),
      GrupoPremio(
        id: 'N1-a32',
        casillas: [32, 33, 38, 39, 45, 46],
        premios: [6, 4, 2],
      ),
      GrupoPremio(id: 'N1-a34', casillas: [34, 40, 41, 47], premios: [7, 5, 3]),
    ],
  ),
  MapaOficial(
    nombre: 'Nivel 2',
    plano: [
      'MMMWVVV',
      'MABBBAV',
      'MRRBBRV',
      'RRRARRR',
      'VRBBRRM',
      'VABBBAM',
      'VVVWMMM',
    ],
    indicesIniciales: [1, 11, 22, 26, 37, 47],
    gruposConectados: [
      {8, 12, 24, 36, 40},
    ],
  ),
  MapaOficial(
    nombre: 'Nivel 3',
    plano: [
      'AAMWMAA',
      'WAMMMAW',
      'RRRMRRR',
      'RRRWRRR',
      'VBBBBBV',
      'VVVVVVV',
      'MMMWMMM',
    ],
    indicesIniciales: [3, 15, 23, 25, 33, 45],
    gruposConectados: [
      {0, 1, 8, 5, 6, 12},
    ],
  ),
  MapaOficial(
    nombre: 'Nivel 4',
    plano: [
      'NNNNNNN',
      'ARBVBRA',
      'RRMMMRR',
      'AVBMBVA',
      'RRMMMRR',
      'ARBVBRA',
      'NNNNNNN',
    ],
    indicesIniciales: [10, 16, 24, 28, 32, 38],
  ),
];
