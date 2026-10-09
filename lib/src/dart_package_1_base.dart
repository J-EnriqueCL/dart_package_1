enum Region {
  verde,
  azul,
  amarillo,
  rojo,
  morado,
}

abstract class Tipo {
  const Tipo();

  String get descripcion;

  bool esPosibleAgregar(
    List<int> valoresActuales,
    int nuevoValor,
  );

  int calcularPuntuacion(
    List<int> valores,
  );
}

class TipoVerde extends Tipo {
  const TipoVerde();

  @override
  String get descripcion {
    return 'Zona verde: los números no se pueden repetir.';
  }

  @override
  bool esPosibleAgregar(
    List<int> valoresActuales,
    int nuevoValor,
  ) {
    return !valoresActuales.contains(nuevoValor);
  }

  @override
  int calcularPuntuacion(
    List<int> valores,
  ) {
    return valores.length;
  }
}

class TipoAzul extends Tipo {
  const TipoAzul();

  @override
  String get descripcion {
    return 'Zona azul: todos los números deben ser iguales.';
  }

  @override
  bool esPosibleAgregar(
    List<int> valoresActuales,
    int nuevoValor,
  ) {
    if (valoresActuales.isEmpty) {
      return true;
    }

    return valoresActuales.every(
      (valor) => valor == nuevoValor,
    );
  }

  @override
  int calcularPuntuacion(
    List<int> valores,
  ) {
    if (valores.isEmpty) {
      return 0;
    }

    return valores.length * valores.first;
  }
}

class TipoAmarillo extends Tipo {
  const TipoAmarillo();

  @override
  String get descripcion {
    return 'Zona amarilla: los números no se pueden repetir.';
  }

  @override
  bool esPosibleAgregar(
    List<int> valoresActuales,
    int nuevoValor,
  ) {
    return !valoresActuales.contains(nuevoValor);
  }

  @override
  int calcularPuntuacion(
    List<int> valores,
  ) {
    return valores.fold(
      0,
      (total, valor) => total + valor,
    );
  }
}

class TipoRojo extends Tipo {
  const TipoRojo();

  @override
  String get descripcion {
    return 'Zona roja: los números no se pueden repetir.';
  }

  @override
  bool esPosibleAgregar(
    List<int> valoresActuales,
    int nuevoValor,
  ) {
    return !valoresActuales.contains(nuevoValor);
  }

  @override
  int calcularPuntuacion(
    List<int> valores,
  ) {
    return valores.fold(
      0,
      (total, valor) => total + valor,
    );
  }
}

class TipoMorado extends Tipo {
  const TipoMorado();

  @override
  String get descripcion {
    return 'Zona morada: puede contener como máximo dos números distintos.';
  }

  @override
  bool esPosibleAgregar(
    List<int> valoresActuales,
    int nuevoValor,
  ) {
    final valoresDistintos = valoresActuales.toSet();

    valoresDistintos.add(nuevoValor);

    return valoresDistintos.length <= 2;
  }

  @override
  int calcularPuntuacion(
    List<int> valores,
  ) {
    return valores.fold(
      0,
      (total, valor) => total + valor,
    );
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

  Celda copiarCon({
    Region? region,
    int? valor,
    bool borrarValor = false,
    bool? esJugable,
    bool? esInicial,
  }) {
    return Celda(
      region: region ?? this.region,
      valor: borrarValor ? null : valor ?? this.valor,
      esJugable: esJugable ?? this.esJugable,
      esInicial: esInicial ?? this.esInicial,
    );
  }
}

List<int> obtenerValoresForIn(
  List<Celda> matriz,
  Region region,
) {
  return matriz
      .where(
        (celda) =>
            celda.region == region &&
            celda.valor != null,
      )
      .map((celda) => celda.valor!)
      .toList();
}

class ControladorPartida {
  List<Celda>? _matriz;

  final Map<Region, Tipo> _tiposPorRegion = {
    Region.verde: const TipoVerde(),
    Region.azul: const TipoAzul(),
    Region.amarillo: const TipoAmarillo(),
    Region.rojo: const TipoRojo(),
    Region.morado: const TipoMorado(),
  };

  List<Celda> get matriz {
    _verificarTableroInicializado();

    return List<Celda>.unmodifiable(_matriz!);
  }

  void establecerValoresIniciales(
    List<Celda> matriz,
  ) {
    if (matriz.length != 49) {
      throw ArgumentError(
        'El tablero debe tener exactamente 49 celdas.',
      );
    }

    final casillasIniciales = matriz
        .where((celda) => celda.esInicial)
        .toList();

    final valoresIniciales = casillasIniciales
        .map((celda) => celda.valor)
        .whereType<int>()
        .toSet();

    if (casillasIniciales.length != 6) {
      throw ArgumentError(
        'Debe haber exactamente 6 casillas iniciales.',
      );
    }

    const numerosRequeridos = <int>{
      1,
      2,
      3,
      4,
      5,
      6,
    };

    if (valoresIniciales.length != 6 ||
        !valoresIniciales.containsAll(numerosRequeridos)) {
      throw ArgumentError(
        'Las casillas iniciales deben contener los números del 1 al 6 sin repetir.',
      );
    }

    // IMPORTANTE:
    // En la configuración inicial NO se validan las reglas
    // de las regiones de colores. Solo se guardan los seis
    // números iniciales para comenzar la partida.
    _matriz = List<Celda>.from(matriz);
  }

  bool agregarNumeroEnCelda(
    int indice,
    int numero,
  ) {
    _verificarTableroInicializado();

    if (indice < 0 || indice >= _matriz!.length) {
      return false;
    }

    if (numero < 1 || numero > 6) {
      return false;
    }

    final celdaDestino = _matriz![indice];

    if (!celdaDestino.esJugable) {
      return false;
    }

    if (celdaDestino.esInicial) {
      return false;
    }

    if (celdaDestino.valor != null) {
      return false;
    }

    final tipoRegionDestino =
        _tiposPorRegion[celdaDestino.region]!;

    final valoresActualesRegion = obtenerValoresForIn(
      _matriz!,
      celdaDestino.region,
    );

    final esValido = tipoRegionDestino.esPosibleAgregar(
      valoresActualesRegion,
      numero,
    );

    if (!esValido) {
      return false;
    }

    _matriz![indice] = Celda(
      region: celdaDestino.region,
      valor: numero,
      esJugable: celdaDestino.esJugable,
      esInicial: celdaDestino.esInicial,
    );

    return true;
  }

  int calcularPuntuacionTotal() {
    _verificarTableroInicializado();

    var puntuacionTotal = 0;

    for (final region in Region.values) {
      final tipo = _tiposPorRegion[region]!;

      final valoresRegion = obtenerValoresForIn(
        _matriz!,
        region,
      );

      puntuacionTotal += tipo.calcularPuntuacion(
        valoresRegion,
      );
    }

    return puntuacionTotal;
  }

  void _verificarTableroInicializado() {
    if (_matriz == null) {
      throw StateError(
        'Primero debes establecer los valores iniciales.',
      );
    }
  }
}