enum Region { verde, azul, amarillo, rojo, morado }

extension ReglasDeRegion on Region {
  String get nombre {
    switch (this) {
      case Region.verde:
        return 'Verde';
      case Region.azul:
        return 'Azul';
      case Region.amarillo:
        return 'Amarillo';
      case Region.rojo:
        return 'Rojo';
      case Region.morado:
        return 'Morado';
    }
  }

  String get regla {
    switch (this) {
      case Region.verde:
        return 'Cualquier número.';
      case Region.azul:
        return 'Todos los números deben ser iguales.';
      case Region.amarillo:
      case Region.rojo:
        return 'Todos los números deben ser distintos.';
      case Region.morado:
        return 'Máximo dos números distintos.';
    }
  }

  bool permite(List<int> valoresDelArea, int nuevo) {
    if (nuevo < 1 || nuevo > 6) {
      return false;
    }

    switch (this) {
      case Region.verde:
        return true;

      case Region.azul:
        return valoresDelArea.every((valor) => valor == nuevo);

      case Region.amarillo:
      case Region.rojo:
        return !valoresDelArea.contains(nuevo);

      case Region.morado:
        final distintos = <int>{...valoresDelArea, nuevo};

        return distintos.length <= 2;
    }
  }
}

class Celda {
  const Celda({
    required this.region,
    this.valor,
    this.esJugable = true,
    this.esInicial = false,
  });

  final Region region;
  final int? valor;
  final bool esJugable;
  final bool esInicial;

  Celda copiarCon({int? valor, bool borrarValor = false}) {
    return Celda(
      region: region,
      valor: borrarValor ? null : valor ?? this.valor,
      esJugable: esJugable,
      esInicial: esInicial,
    );
  }
}

class Area {
  const Area({
    required this.id,
    required this.region,
    required this.indices,
    required this.puntos,
  });

  final int id;
  final Region region;
  final List<int> indices;
  final int puntos;

  int get tamano => indices.length;
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
    default:
      throw ArgumentError('Color no reconocido: $letra');
  }
}

List<Celda> crearTableroNivelUno() {
  // A = amarillo
  // V = verde
  // B = azul
  // R = rojo
  // M = morado
  const plano = <String>[
    'AVBMMMA',
    'VVBBMMV',
    'VRRBMVV',
    'VRMAVVV',
    'VRMMRRB',
    'RRMRRBB',
    'AMMRRBA',
  ];

  // Posiciones iniciales de la nueva imagen.
  // Filas y columnas contadas desde 1.
  //
  // 2  = fila 1, columna 3: azul
  // 12 = fila 2, columna 6: morado
  // 22 = fila 4, columna 2: rojo
  // 25 = fila 4, columna 5: verde
  // 37 = fila 6, columna 3: morado
  // 46 = fila 7, columna 5: rojo
  //
  // No se precargan números.
  const indicesIniciales = <int>{2, 12, 22, 25, 37, 46};

  final celdas = <Celda>[];

  for (var fila = 0; fila < 7; fila++) {
    for (var columna = 0; columna < 7; columna++) {
      final indice = fila * 7 + columna;

      celdas.add(
        Celda(
          region: _regionDeLetra(plano[fila][columna]),
          esInicial: indicesIniciales.contains(indice),
        ),
      );
    }
  }

  return celdas;
}

class ControladorPartida {
  static const int filas = 7;
  static const int columnas = 7;

  static const Map<Region, int> puntosPorRegion = {
    Region.verde: 4,
    Region.azul: 7,
    Region.amarillo: 8,
    Region.rojo: 6,
    Region.morado: 6,
  };

  List<Celda>? _matriz;
  List<Area> _areas = [];
  List<int> _areaDeCelda = [];

  static List<int> vecinosDe(int indice) {
    if (indice < 0 || indice >= filas * columnas) {
      return [];
    }

    final fila = indice ~/ columnas;
    final columna = indice % columnas;
    final vecinos = <int>[];

    if (fila > 0) {
      vecinos.add(indice - columnas);
    }

    if (fila < filas - 1) {
      vecinos.add(indice + columnas);
    }

    if (columna > 0) {
      vecinos.add(indice - 1);
    }

    if (columna < columnas - 1) {
      vecinos.add(indice + 1);
    }

    return vecinos;
  }

  List<Celda> get matriz {
    _verificarTablero();

    return List<Celda>.unmodifiable(_matriz!);
  }

  List<Area> get areas {
    _verificarTablero();

    return List<Area>.unmodifiable(_areas);
  }

  void establecerValoresIniciales(List<Celda> celdas) {
    if (celdas.length != filas * columnas) {
      throw ArgumentError('El tablero debe tener exactamente 49 celdas.');
    }

    final iniciales = celdas.where((celda) => celda.esInicial).toList();

    if (iniciales.length != 6) {
      throw ArgumentError('Debe haber exactamente 6 casillas iniciales.');
    }

    final valores = iniciales
        .map((celda) => celda.valor)
        .whereType<int>()
        .toSet();

    const requeridos = <int>{1, 2, 3, 4, 5, 6};

    if (valores.length != 6 || !valores.containsAll(requeridos)) {
      throw ArgumentError('Coloca los números del 1 al 6 sin repetir.');
    }

    _matriz = List<Celda>.of(celdas);

    _calcularAreas();
  }

  List<int> _vecinosParaFormarArea(int indice) {
    final vecinos = <int>{...vecinosDe(indice)};

    // Las cuatro esquinas amarillas y la casilla amarilla
    // central se consideran una misma región amarilla.
    const amarillasConectadas = <int>{0, 6, 24, 42, 48};

    if (amarillasConectadas.contains(indice)) {
      vecinos.addAll(amarillasConectadas);
    }

    vecinos.remove(indice);

    return vecinos.toList();
  }

  void _calcularAreas() {
    final total = _matriz!.length;

    final visitadas = List<bool>.filled(total, false);
    final asignacion = List<int>.filled(total, -1);
    final areasCalculadas = <Area>[];

    for (var inicio = 0; inicio < total; inicio++) {
      if (visitadas[inicio]) {
        continue;
      }

      final region = _matriz![inicio].region;
      final pendientes = <int>[inicio];
      final indices = <int>[];

      visitadas[inicio] = true;

      while (pendientes.isNotEmpty) {
        final actual = pendientes.removeLast();

        indices.add(actual);

        for (final vecino in _vecinosParaFormarArea(actual)) {
          if (visitadas[vecino]) {
            continue;
          }

          if (_matriz![vecino].region != region) {
            continue;
          }

          visitadas[vecino] = true;
          pendientes.add(vecino);
        }
      }

      indices.sort();

      final id = areasCalculadas.length;

      for (final indice in indices) {
        asignacion[indice] = id;
      }

      areasCalculadas.add(
        Area(
          id: id,
          region: region,
          indices: List<int>.unmodifiable(indices),
          puntos: puntosPorRegion[region]!,
        ),
      );
    }

    _areas = areasCalculadas;
    _areaDeCelda = asignacion;
  }

  Area areaDeCelda(int indice) {
    _verificarTablero();

    if (indice < 0 || indice >= _matriz!.length) {
      throw RangeError.index(indice, _matriz!);
    }

    return _areas[_areaDeCelda[indice]];
  }

  List<int> valoresDelArea(Area area) {
    _verificarTablero();

    return area.indices
        .map((indice) => _matriz![indice].valor)
        .whereType<int>()
        .toList();
  }

  int casillasLlenas(Area area) {
    return valoresDelArea(area).length;
  }

  bool areaCompleta(Area area) {
    return casillasLlenas(area) == area.tamano;
  }

  bool puedeColocar(int indice, int numero) {
    _verificarTablero();

    if (indice < 0 || indice >= _matriz!.length) {
      return false;
    }

    if (numero < 1 || numero > 6) {
      return false;
    }

    final celda = _matriz![indice];

    if (!celda.esJugable || celda.esInicial || celda.valor != null) {
      return false;
    }

    final area = areaDeCelda(indice);

    return area.region.permite(valoresDelArea(area), numero);
  }

  Set<int> destinosPosibles({required int ancla, required int colocar}) {
    _verificarTablero();

    if (ancla < 1 || ancla > 6 || colocar < 1 || colocar > 6) {
      return <int>{};
    }

    final destinos = <int>{};

    for (var indice = 0; indice < _matriz!.length; indice++) {
      if (_matriz![indice].valor != ancla) {
        continue;
      }

      for (final vecino in vecinosDe(indice)) {
        if (puedeColocar(vecino, colocar)) {
          destinos.add(vecino);
        }
      }
    }

    return destinos;
  }

  bool colocar(int indice, int numero) {
    if (!puedeColocar(indice, numero)) {
      return false;
    }

    _matriz![indice] = _matriz![indice].copiarCon(valor: numero);

    return true;
  }

  int puntosDeArea(Area area) {
    return areaCompleta(area) ? area.puntos : 0;
  }

  List<Area> areasDe(Region region) {
    _verificarTablero();

    return _areas.where((area) => area.region == region).toList();
  }

  int puntosDeRegion(Region region) {
    return areasDe(region)
        .fold<int>(0, (total, area) => total + puntosDeArea(area));
  }

  int get puntuacionTotal {
    _verificarTablero();

    return _areas.fold<int>(0, (total, area) => total + puntosDeArea(area));
  }

  void _verificarTablero() {
    if (_matriz == null) {
      throw StateError('Primero debes establecer los valores iniciales.');
    }
  }
}
