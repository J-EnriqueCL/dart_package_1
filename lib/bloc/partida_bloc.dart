import 'package:flutter/foundation.dart';

import '../dart_package_1.dart';

class PartidaBloc extends ChangeNotifier {
  PartidaBloc({required ControladorPartida controlador})
    : _controlador = controlador;

  static const int filas = 7;
  static const int columnas = 7;

  final ControladorPartida _controlador;

  int? _dadoUno;
  int? _dadoDos;
  int? _numeroAncla;
  int? _numeroPorColocar;

  List<int> _indicesPosibles = [];

  int _turno = 1;

  String _mensaje = 'Presiona “Tirar dados” para iniciar un turno.';

  List<Celda> get matriz => _controlador.matriz;

  int? get dadoUno => _dadoUno;

  int? get dadoDos => _dadoDos;

  int? get numeroAncla => _numeroAncla;

  int? get numeroPorColocar => _numeroPorColocar;

  int get turno => _turno;

  String get mensaje => _mensaje;

  int get puntuacionTotal => _controlador.calcularPuntuacionTotal();

  bool get hayDados {
    return _dadoUno != null && _dadoDos != null;
  }

  bool get esperandoAncla {
    return hayDados && _numeroAncla == null && _numeroPorColocar == null;
  }

  bool get esperandoDestino {
    return _numeroAncla != null && _numeroPorColocar != null;
  }

  bool esDestinoPosible(int indice) {
    return _indicesPosibles.contains(indice);
  }

  void lanzarDados(int dadoUno, int dadoDos) {
    if (dadoUno < 1 || dadoUno > 6 || dadoDos < 1 || dadoDos > 6) {
      _mensaje = 'Los valores de los dados deben estar entre 1 y 6.';
      notifyListeners();
      return;
    }

    _dadoUno = dadoUno;
    _dadoDos = dadoDos;

    _numeroAncla = null;
    _numeroPorColocar = null;
    _indicesPosibles = [];

    _mensaje =
        'Dados lanzados: $dadoUno y $dadoDos. Toca uno para elegir el ancla.';

    notifyListeners();
  }

  void seleccionarAncla(int numeroAncla) {
    if (!hayDados) {
      _mensaje = 'Primero debes tirar los dados.';
      notifyListeners();
      return;
    }

    if (numeroAncla != _dadoUno && numeroAncla != _dadoDos) {
      _mensaje = 'El ancla debe ser uno de los dos resultados.';
      notifyListeners();
      return;
    }

    final numeroPorColocar = numeroAncla == _dadoUno ? _dadoDos! : _dadoUno!;

    _numeroAncla = numeroAncla;
    _numeroPorColocar = numeroPorColocar;

    _indicesPosibles = _buscarDestinosPosibles(
      numeroAncla: numeroAncla,
      numeroPorColocar: numeroPorColocar,
    );

    if (_indicesPosibles.isEmpty) {
      _mensaje =
          'No hay una casilla válida para colocar $numeroPorColocar junto a un $numeroAncla.';
    } else {
      _mensaje =
          'Ancla: $numeroAncla. Coloca $numeroPorColocar en una casilla iluminada.';
    }

    notifyListeners();
  }

  void colocarNumero(int indiceDestino) {
    if (!esperandoDestino) {
      _mensaje = 'Primero toca uno de los dados para elegir el ancla.';
      notifyListeners();
      return;
    }

    if (!_indicesPosibles.contains(indiceDestino)) {
      _mensaje = 'Solo puedes tocar una casilla iluminada.';
      notifyListeners();
      return;
    }

    final numero = _numeroPorColocar!;

    final seColoco = _controlador.agregarNumeroEnCelda(indiceDestino, numero);

    if (!seColoco) {
      _mensaje =
          'No se pudo colocar $numero porque la regla de la región no lo permite.';
      notifyListeners();
      return;
    }

    _numeroAncla = null;
    _numeroPorColocar = null;
    _indicesPosibles = [];

    _turno++;

    _mensaje =
        'Se colocó $numero. Puntuación: $puntuacionTotal. '
        'Presiona “Tirar dados” para continuar.';

    notifyListeners();
  }

  void cancelarSeleccionAncla() {
    if (!hayDados) {
      return;
    }

    _numeroAncla = null;
    _numeroPorColocar = null;
    _indicesPosibles = [];

    _mensaje = 'Toca uno de los dados para elegir el ancla.';

    notifyListeners();
  }

  List<int> _buscarDestinosPosibles({
    required int numeroAncla,
    required int numeroPorColocar,
  }) {
    final destinos = <int>{};

    for (var indiceAncla = 0; indiceAncla < matriz.length; indiceAncla++) {
      final celdaAncla = matriz[indiceAncla];

      if (celdaAncla.valor != numeroAncla) {
        continue;
      }

      for (final indiceVecino in _obtenerVecinos(indiceAncla)) {
        final celdaDestino = matriz[indiceVecino];

        if (_esDestinoValido(
          celdaDestino: celdaDestino,
          numeroPorColocar: numeroPorColocar,
        )) {
          destinos.add(indiceVecino);
        }
      }
    }

    return destinos.toList()..sort();
  }

  bool _esDestinoValido({
    required Celda celdaDestino,
    required int numeroPorColocar,
  }) {
    if (!celdaDestino.esJugable) {
      return false;
    }

    if (celdaDestino.esInicial) {
      return false;
    }

    if (celdaDestino.valor != null) {
      return false;
    }

    final tipo = _obtenerTipo(celdaDestino.region);

    final valoresEnRegion = obtenerValoresForIn(matriz, celdaDestino.region);

    return tipo.esPosibleAgregar(valoresEnRegion, numeroPorColocar);
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

  Tipo _obtenerTipo(Region region) {
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
