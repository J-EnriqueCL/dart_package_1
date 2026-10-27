import 'dart:math';

import 'package:flutter/foundation.dart';

import '../dart_package_1.dart';

class PartidaBloc extends ChangeNotifier {
  /// [azar] permite inyectar una fuente de dados determinista (pruebas).
  PartidaBloc(this._controlador, {Random? azar}) : _azar = azar ?? Random();

  final ControladorPartida _controlador;
  final Random _azar;

  List<int>? _dados;
  List<bool> _movimientosPorDado = [false, false];
  int? _posicionAncla;
  Set<int> _destinos = {};
  int _turno = 1;
  String _mensaje = 'Tira los dados para comenzar.';

  List<Celda> get matriz => _controlador.matriz;
  List<Area> get areas => _controlador.areas;

  /// Regiones que existen en el mapa actual.
  List<Region> get regiones =>
      Region.values.where((region) => totalAreas(region) > 0).toList();
  int get turno => _turno;
  String get mensaje => _mensaje;
  List<int>? get dados => _dados;
  bool get hayDados => _dados != null;
  int? get posicionAncla => _posicionAncla;
  int get puntuacionTotal => _controlador.puntuacionTotal;

  int? get numeroAncla {
    if (_dados == null || _posicionAncla == null) {
      return null;
    }
    return _dados![_posicionAncla!];
  }

  int? get numeroPorColocar {
    if (_dados == null || _posicionAncla == null) {
      return null;
    }
    return _dados![1 - _posicionAncla!];
  }

  bool dadoTieneMovimientos(int posicion) => _movimientosPorDado[posicion];

  bool esDestino(int indice) => _destinos.contains(indice);

  bool esCeldaAncla(int indice) {
    final ancla = numeroAncla;
    return ancla != null && matriz[indice].valor == ancla;
  }

  bool celdaEnAreaCompleta(int indice) {
    return _controlador.areaCompleta(_controlador.areaDeCelda(indice));
  }

  int puntosDeRegion(Region region) => _controlador.puntosDeRegion(region);

  int totalAreas(Region region) => _controlador.areasDe(region).length;

  int areasCompletas(Region region) {
    return _controlador.areasDe(region).where(_controlador.areaCompleta).length;
  }

  int casillasLlenas(Area area) => _controlador.casillasLlenas(area);

  bool areaCompleta(Area area) => _controlador.areaCompleta(area);

  void tirarDados() {
    if (hayDados) {
      _mensaje = 'Primero coloca un número o pasa el turno.';
      notifyListeners();
      return;
    }

    final dados = [_azar.nextInt(6) + 1, _azar.nextInt(6) + 1];

    _dados = dados;
    _posicionAncla = null;
    _destinos = {};
    _movimientosPorDado = [
      _controlador
          .destinosPosibles(ancla: dados[0], colocar: dados[1])
          .isNotEmpty,
      _controlador
          .destinosPosibles(ancla: dados[1], colocar: dados[0])
          .isNotEmpty,
    ];

    if (_movimientosPorDado.contains(true)) {
      _mensaje =
          'Salieron ${dados[0]} y ${dados[1]}. Toca un dado para elegirlo como ancla.';
    } else {
      _mensaje =
          'Salieron ${dados[0]} y ${dados[1]}, pero no hay movimientos. Pasa el turno.';
    }

    notifyListeners();
  }

  void seleccionarAncla(int posicion) {
    if (!hayDados) {
      return;
    }

    if (_posicionAncla == posicion) {
      _posicionAncla = null;
      _destinos = {};
      _mensaje = 'Toca un dado para elegirlo como ancla.';
      notifyListeners();
      return;
    }

    _posicionAncla = posicion;
    _destinos = _controlador.destinosPosibles(
      ancla: numeroAncla!,
      colocar: numeroPorColocar!,
    );

    if (_destinos.isEmpty) {
      _mensaje =
          'No hay lugar para el $numeroPorColocar junto a un $numeroAncla. Elige el otro dado.';
    } else {
      _mensaje =
          'Ancla $numeroAncla. Coloca el $numeroPorColocar en una casilla iluminada.';
    }

    notifyListeners();
  }

  void colocar(int indice) {
    if (!hayDados || _posicionAncla == null || !_destinos.contains(indice)) {
      return;
    }

    final numero = numeroPorColocar!;
    final puntosAntes = puntuacionTotal;

    if (!_controlador.colocar(indice, numero)) {
      _mensaje = 'Ese número no cumple la regla del área.';
      notifyListeners();
      return;
    }

    final ganados = puntuacionTotal - puntosAntes;

    _mensaje = ganados > 0
        ? '¡Área completada! +$ganados puntos. Tira los dados.'
        : 'Colocaste el $numero. Tira los dados.';

    _dados = null;
    _posicionAncla = null;
    _destinos = {};
    _movimientosPorDado = [false, false];
    _turno++;

    notifyListeners();
  }

  void pasarTurno() {
    if (!hayDados) {
      return;
    }

    _dados = null;
    _posicionAncla = null;
    _destinos = {};
    _movimientosPorDado = [false, false];
    _turno++;
    _mensaje = 'Turno pasado. Tira los dados.';

    notifyListeners();
  }
}
