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

bool listaNumeros(List<int> actuales, int posible) {
  return !actuales.contains(posible) &&
      actuales.length == actuales.toSet().length;
}

bool bloqueVerde(List<int> actuales, int posible) {
  return TipoVerde().esPosibleAgregar(actuales, posible);
}

bool bloqueAzul(List<int> actuales, int posible) {
  return TipoAzul().esPosibleAgregar(actuales, posible);
}

bool bloqueRojo(List<int> actuales, int posible) {
  return TipoRojo().esPosibleAgregar(actuales, posible);
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
  });

  final int? valor;
  final Region region;
}

List<int> obtenerValoresForIn(
  List<Celda> matriz,
  Region region,
) {
  return matriz
      .where((celda) => celda.region == region && celda.valor != null)
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

  bool get tieneValoresIniciales => _matriz != null;

  void establecerValoresIniciales(List<Celda> valoresIniciales) {
    if (valoresIniciales.isEmpty) {
      throw ArgumentError('La lista de valores iniciales no puede estar vacia');
    }

    _matriz = List<Celda>.from(valoresIniciales);
  }

  List<Celda> get matriz {
    _verificarValoresIniciales();

    return List<Celda>.unmodifiable(_matriz!);
  }

  List<int> valoresPorRegion(Region region) {
    _verificarValoresIniciales();

    return obtenerValoresForIn(_matriz!, region);
  }

  bool agregarNumero(Region region, int posible, Tipo tipo) {
    _verificarValoresIniciales();

    final actuales = obtenerValoresForIn(_matriz!, region);

    if (!tipo.esPosibleAgregar(actuales, posible)) {
      return false;
    }

    final indice = _matriz!.indexWhere(
      (celda) => celda.region == region && celda.valor == null,
    );

    if (indice == -1) {
      return false;
    }

    _matriz![indice] = Celda(
      region: region,
      valor: posible,
    );

    return true;
  }

  int calcularPuntuacionTotal(Map<Region, Tipo> tiposPorRegion) {
    _verificarValoresIniciales();

    var total = 0;

    for (final region in Region.values) {
      final tipo = tiposPorRegion[region];

      if (tipo == null) {
        continue;
      }

      final valores = obtenerValoresForIn(_matriz!, region);
      total += tipo.calcularPuntuacion(valores.length);
    }

    return total;
  }

  void _verificarValoresIniciales() {
    if (!tieneValoresIniciales) {
      throw ValoresInicialesNoProporcionadosException();
    }
  }
}

class Awesome {
  bool get isAwesome => true;
}