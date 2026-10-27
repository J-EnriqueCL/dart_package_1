import 'dart_package_1_base.dart';

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
  });

  final String nombre;
  final List<String> plano;

  /// Seis casillas (índices 0..48) que reciben los números 1..6.
  final List<int> indicesIniciales;

  /// Casillas no contiguas que forman una misma área (p. ej. las esquinas
  /// amarillas del nivel 1).
  final List<Set<int>> gruposConectados;

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
