import 'package:flutter/foundation.dart';

import '../dart_package_1.dart';

class PartidaBloc extends ChangeNotifier {
  PartidaBloc({
    required ControladorPartida controlador,
  }) : _controlador = controlador;

  static const int columnas = 7;
  static const int filas = 7;

  final ControladorPartida _controlador;

  int? _dadoUno;
  int? _dadoDos;
  int? _numeroAncla;
  int? _numeroPorColocar;
  List<int> _indicesPosibles = [];
  String? _mensaje;

  List<Celda> get matriz => _controlador.matriz;

  int? get dadoUno => _dadoUno;

  int? get dadoDos => _dadoDos;

  int? get numeroAncla => _numeroAncla;

  int? get numeroPorColocar => _numeroPorColocar;

  String? get mensaje => _mensaje;

  List<int> get indicesPosibles {
    return List<int>.unmodifiable(_indicesPosibles);
  }

  int get puntuacionTotal {
    return _controlador.calcularPuntuacionTotal();
  }

  bool get hayDados {
    return _dadoUno != null && _dadoDos != null;
  }

  bool esPosible(int indice) {
    return _indicesPosibles.contains(indice);
  }

  void establecerDados(int primerDado, int segundoDado) {
    if (primerDado < 1 ||
        primerDado > 6 ||
        segundoDado < 1 ||
        segundoDado > 6) {
      _mensaje = 'Los dados deben tener valores entre 1 y 6.';
      notifyListeners();
      return;
    }

    _dadoUno = primerDado;
    _dadoDos = segundoDado;
    _numeroAncla = null;
    _numeroPorColocar = null;
    _indicesPosibles = [];
    _mensaje = 'Selecciona uno de los dos números como ancla.';

    notifyListeners();
  }

  void seleccionarAncla(int ancla) {
    if (!hayDados) {
      _mensaje = 'Primero establece los valores de los dados.';
      notifyListeners();
      return;
    }

    if (ancla != _dadoUno && ancla != _dadoDos) {
      _mensaje = 'El ancla debe ser uno de los números de los dados.';
      notifyListeners();
      return;
    }

    final otroNumero = ancla == _dadoUno ? _dadoDos! : _dadoUno!;

    _numeroAncla = ancla;
    _numeroPorColocar = otroNumero;

    _indicesPosibles = _obtenerDestinosPosibles(
      numeroAncla: ancla,
      numeroPorColocar: otroNumero,
    );

    if (_indicesPosibles.isEmpty) {
      _mensaje =
          'No hay lugares válidos para colocar $otroNumero junto a un $ancla.';
    } else {
      _mensaje =
          'Ancla: $ancla. Coloca el número $otroNumero en una casilla iluminada.';
    }

    notifyListeners();
  }

  void colocarNumero(int indiceDestino) {
    if (_numeroPorColocar == null) {
      _mensaje = 'Selecciona primero uno de los dados como ancla.';
      notifyListeners();
      return;
    }

    if (!_indicesPosibles.contains(indiceDestino)) {
      _mensaje = 'Esa casilla no es un destino permitido.';
      notifyListeners();
      return;
    }

    final numeroColocado = _numeroPorColocar!;

    final agregado = _controlador.agregarNumeroEnCelda(
      indiceDestino,
      numeroColocado,
    );

    if (!agregado) {
      _mensaje = 'No fue posible colocar el número en esa casilla.';
      notifyListeners();
      return;
    }

    _numeroAncla = null;
    _numeroPorColocar = null;
    _indicesPosibles = [];

    _mensaje =
        'Se colocó el número $numeroColocado. Puntuación actual: $puntuacionTotal.';

    notifyListeners();
  }

  void cancelarSeleccion() {
    _numeroAncla = null;
    _numeroPorColocar = null;
    _indicesPosibles = [];
    _mensaje = 'Selección cancelada.';
    notifyListeners();
  }

  List<int> _obtenerDestinosPosibles({
    required int numeroAncla,
    required int numeroPorColocar,
  }) {
    final destinos = <int>{};

    for (var indice = 0; indice < matriz.length; indice++) {
      final celda = matriz[indice];

      if (!celda.esJugable || celda.valor != numeroAncla) {
        continue;
      }

      for (final vecino in _obtenerVecinos(indice)) {
        final destino = matriz[vecino];

        if (_esDestinoValido(destino, numeroPorColocar)) {
          destinos.add(vecino);
        }
      }
    }

    return destinos.toList()..sort();
  }

  bool _esDestinoValido(
    Celda celda,
    int numeroPorColocar,
  ) {
    if (!celda.esJugable ||
        celda.esInicial ||
        celda.valor != null) {
      return false;
    }

    final tipo = _tipoDeRegion(celda.region);

    final valoresActuales = obtenerValoresForIn(
      matriz,
      celda.region,
    );

    return tipo.esPosibleAgregar(
      valoresActuales,
      numeroPorColocar,
    );
  }

  List<int> _obtenerVecinos(int indice) {
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

  Tipo _tipoDeRegion(Region region) {
    switch (region) {
      case Region.verde:
        return TipoVerde();
      case Region.azul:
        return TipoAzul();
      case Region.amarillo:
        return TipoAmarillo();
      case Region.rojo:
        return TipoRojo();
      case Region.morado:
        return TipoMorado();
    }
  }
}