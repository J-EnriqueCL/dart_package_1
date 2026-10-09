class Color {
  const Color(this.value);

  final int value;

  static const Color verde = Color(0xFF4CAF50);
  static const Color morado = Color(0xFF9C27B0);
  static const Color amarillo = Color(0xFFFFC107);
  static const Color rojo = Color(0xFFF44336);
  static const Color azul = Color(0xFF2196F3);

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Color &&
            runtimeType == other.runtimeType &&
            value == other.value;
  }

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() {
    return 'Color(0x${value.toRadixString(16).toUpperCase()})';
  }
}

abstract class Tipo {
  Color get color;

  String get descripcion;

  bool esPosibleAgregar(
    List<int> actuales,
    int posible,
  );

  Map<int, int> get puntuaciones;

  int calcularPuntuacion(int cantidadNumeros) {
    return puntuaciones[cantidadNumeros] ?? 0;
  }
}

class TipoVerde extends Tipo {
  @override
  Color get color => Color.verde;

  @override
  String get descripcion => 'Se puede colocar cualquier número';

  @override
  bool esPosibleAgregar(List<int> actuales, int posible) {
    return true;
  }

  @override
  Map<int, int> get puntuaciones => const {
        1: 4,
        2: 3,
        3: 2,
      };
}

class TipoMorado extends Tipo {
  @override
  Color get color => Color.morado;

  @override
  String get descripcion => 'Máximo dos números diferentes por zona';

  @override
  bool esPosibleAgregar(List<int> actuales, int posible) {
    final distintos = actuales.toSet()..add(posible);

    return distintos.length <= 2;
  }

  @override
  Map<int, int> get puntuaciones => const {
        1: 8,
        2: 6,
        3: 4,
      };
}

class TipoAmarillo extends Tipo {
  @override
  Color get color => Color.amarillo;

  @override
  String get descripcion => 'Todos los números deben ser distintos';

  @override
  bool esPosibleAgregar(List<int> actuales, int posible) {
    return !actuales.contains(posible);
  }

  @override
  Map<int, int> get puntuaciones => const {
        1: 8,
        2: 6,
        3: 4,
      };
}

class TipoRojo extends Tipo {
  @override
  Color get color => Color.rojo;

  @override
  String get descripcion => 'Todos los números deben ser distintos';

  @override
  bool esPosibleAgregar(List<int> actuales, int posible) {
    return !actuales.contains(posible);
  }

  @override
  Map<int, int> get puntuaciones => const {
        1: 6,
        2: 4,
        3: 2,
      };
}

class TipoAzul extends Tipo {
  @override
  Color get color => Color.azul;

  @override
  String get descripcion => 'Todos los números de la zona deben ser iguales';

  @override
  bool esPosibleAgregar(List<int> actuales, int posible) {
    return actuales.isEmpty ||
        actuales.every((elemento) => elemento == posible);
  }

  @override
  Map<int, int> get puntuaciones => const {
        1: 7,
        2: 5,
        3: 3,
      };
}

enum Region {
  verde,
  azul,
  amarillo,
  rojo,
  morado,
}

class Celda {
  const Celda({
    required this.region,
    this.valor,
    this.esInicial = false,
    this.esJugable = true,
  });

  final Region region;
  final int? valor;
  final bool esInicial;
  final bool esJugable;

  Celda copiarCon({
    int? valor,
    bool? esInicial,
    bool? esJugable,
  }) {
    return Celda(
      region: region,
      valor: valor,
      esInicial: esInicial ?? this.esInicial,
      esJugable: esJugable ?? this.esJugable,
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
            celda.esJugable &&
            celda.region == region &&
            celda.valor != null,
      )
      .map((celda) => celda.valor!)
      .toList();
}

class ValoresInicialesNoProporcionadosException implements Exception {
  @override
  String toString() {
    return 'No se puede avanzar: los valores iniciales aun no han sido proporcionados';
  }
}

class ControladorPartida {
  List<Celda>? _matriz;

  final Map<Region, Tipo> _tiposPorRegion = {
    Region.verde: TipoVerde(),
    Region.azul: TipoAzul(),
    Region.amarillo: TipoAmarillo(),
    Region.rojo: TipoRojo(),
    Region.morado: TipoMorado(),
  };

  bool get tieneValoresIniciales => _matriz != null;

  List<Celda> get matriz {
    _verificarValoresIniciales();

    return List<Celda>.unmodifiable(_matriz!);
  }

  void establecerValoresIniciales(List<Celda> valoresIniciales) {
    if (valoresIniciales.isEmpty) {
      throw ArgumentError('La matriz inicial no puede estar vacia');
    }

    final valoresInicialesSeleccionados = valoresIniciales
        .where((celda) => celda.esInicial)
        .toList();

    if (valoresInicialesSeleccionados.isEmpty) {
      throw ArgumentError('Debe existir al menos una casilla inicial');
    }

    final valores = valoresInicialesSeleccionados
        .where((celda) => celda.valor != null)
        .map((celda) => celda.valor!)
        .toList();

    if (valores.length != valoresInicialesSeleccionados.length) {
      throw ArgumentError(
        'Todas las casillas iniciales deben tener un número',
      );
    }

    if (valores.length != valores.toSet().length) {
      throw ArgumentError('Los números iniciales no se pueden repetir');
    }

    if (!_cumpleReglasPorRegion(valoresIniciales)) {
      throw ArgumentError(
        'Los números iniciales no cumplen las reglas de las regiones',
      );
    }

    _matriz = List<Celda>.from(valoresIniciales);
  }

  List<int> valoresPorRegion(Region region) {
    _verificarValoresIniciales();

    return obtenerValoresForIn(_matriz!, region);
  }

  bool agregarNumeroEnCelda(int indice, int posible) {
    _verificarValoresIniciales();

    if (indice < 0 || indice >= _matriz!.length) {
      return false;
    }

    if (posible < 1 || posible > 6) {
      return false;
    }

    final celda = _matriz![indice];

    if (!celda.esJugable || celda.esInicial || celda.valor != null) {
      return false;
    }

    final tipo = _tiposPorRegion[celda.region]!;
    final valoresActuales = obtenerValoresForIn(
      _matriz!,
      celda.region,
    );

    if (!tipo.esPosibleAgregar(valoresActuales, posible)) {
      return false;
    }

    _matriz![indice] = Celda(
      region: celda.region,
      valor: posible,
      esJugable: celda.esJugable,
    );

    return true;
  }

  int calcularPuntuacionTotal() {
    _verificarValoresIniciales();

    var total = 0;

    for (final region in Region.values) {
      final tipo = _tiposPorRegion[region]!;
      final valores = obtenerValoresForIn(_matriz!, region);

      total += tipo.calcularPuntuacion(valores.length);
    }

    return total;
  }

  bool _cumpleReglasPorRegion(List<Celda> matriz) {
    for (final region in Region.values) {
      final tipo = _tiposPorRegion[region]!;
      final valores = obtenerValoresForIn(matriz, region);

      for (var indice = 0; indice < valores.length; indice++) {
        final valorActual = valores[indice];
        final otrosValores = List<int>.from(valores)..removeAt(indice);

        if (!tipo.esPosibleAgregar(otrosValores, valorActual)) {
          return false;
        }
      }
    }

    return true;
  }

  void _verificarValoresIniciales() {
    if (!tieneValoresIniciales) {
      throw ValoresInicialesNoProporcionadosException();
    }
  }
}