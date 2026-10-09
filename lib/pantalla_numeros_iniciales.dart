import 'package:flutter/material.dart' as material;

import 'dart_package_1.dart';

class PantallaNumerosIniciales extends material.StatefulWidget {
  const PantallaNumerosIniciales({
    super.key,
    required this.alIniciar,
  });

  final void Function(ControladorPartida controlador) alIniciar;

  @override
  material.State<PantallaNumerosIniciales> createState() {
    return _PantallaNumerosInicialesState();
  }
}

class _PantallaNumerosInicialesState
    extends material.State<PantallaNumerosIniciales> {
  static const int columnas = 7;

  final List<Region> _distribucion = [
    Region.amarillo,
    Region.verde,
    Region.azul,
    Region.morado,
    Region.morado,
    Region.morado,
    Region.amarillo,
    Region.verde,
    Region.verde,
    Region.azul,
    Region.azul,
    Region.morado,
    Region.morado,
    Region.verde,
    Region.verde,
    Region.rojo,
    Region.rojo,
    Region.azul,
    Region.morado,
    Region.verde,
    Region.verde,
    Region.verde,
    Region.rojo,
    Region.morado,
    Region.amarillo,
    Region.verde,
    Region.verde,
    Region.verde,
    Region.verde,
    Region.rojo,
    Region.morado,
    Region.morado,
    Region.rojo,
    Region.rojo,
    Region.azul,
    Region.rojo,
    Region.rojo,
    Region.morado,
    Region.rojo,
    Region.rojo,
    Region.azul,
    Region.azul,
    Region.amarillo,
    Region.morado,
    Region.morado,
    Region.rojo,
    Region.azul,
    Region.amarillo,
    Region.verde,
  ];

  late List<Celda> _matriz;

  int? _indiceSeleccionado;
  String? _mensajeError;

  @override
  void initState() {
    super.initState();

    const indicesIniciales = <int>{
      2,
      12,
      22,
      32,
      34,
      42,
    };

    _matriz = _distribucion.asMap().entries.map((entrada) {
      return Celda(
        region: entrada.value,
        esInicial: indicesIniciales.contains(entrada.key),
      );
    }).toList();
  }

  void _seleccionarCelda(int indice) {
    final celda = _matriz[indice];

    if (!celda.esInicial) {
      setState(() {
        _mensajeError =
            'Solo puedes seleccionar una de las 6 casillas iniciales.';
      });
      return;
    }

    setState(() {
      _indiceSeleccionado = indice;
      _mensajeError = null;
    });
  }

  void _colocarNumero(int numero) {
    if (_indiceSeleccionado == null) {
      setState(() {
        _mensajeError =
            'Selecciona una de las 6 casillas iniciales primero.';
      });
      return;
    }

    final indice = _indiceSeleccionado!;
    final celdaAnterior = _matriz[indice];

    if (!celdaAnterior.esInicial) {
      setState(() {
        _mensajeError =
            'La casilla seleccionada no pertenece a las casillas iniciales.';
      });
      return;
    }

    final numeroYaEstaUsado = _matriz.asMap().entries.any(
      (entrada) {
        return entrada.key != indice &&
            entrada.value.esInicial &&
            entrada.value.valor == numero;
      },
    );

    if (numeroYaEstaUsado) {
      setState(() {
        _mensajeError = 'El número $numero ya fue seleccionado.';
      });
      return;
    }

    setState(() {
      _matriz[indice] = Celda(
        region: celdaAnterior.region,
        valor: numero,
        esJugable: celdaAnterior.esJugable,
        esInicial: true,
      );

      _mensajeError = null;
    });
  }

  void _borrarNumero() {
    if (_indiceSeleccionado == null) {
      setState(() {
        _mensajeError =
            'Selecciona una de las 6 casillas iniciales primero.';
      });
      return;
    }

    final indice = _indiceSeleccionado!;
    final celdaAnterior = _matriz[indice];

    if (!celdaAnterior.esInicial) {
      setState(() {
        _mensajeError =
            'La casilla seleccionada no pertenece a las casillas iniciales.';
      });
      return;
    }

    if (celdaAnterior.valor == null) {
      setState(() {
        _mensajeError = 'La casilla seleccionada ya está vacía.';
      });
      return;
    }

    setState(() {
      _matriz[indice] = Celda(
        region: celdaAnterior.region,
        valor: null,
        esJugable: celdaAnterior.esJugable,
        esInicial: true,
      );

      _mensajeError = null;
    });
  }

  List<Celda> get _casillasIniciales {
    return _matriz.where((celda) => celda.esInicial).toList();
  }

  Set<int> get _valoresIniciales {
    return _casillasIniciales
        .map((celda) => celda.valor)
        .whereType<int>()
        .toSet();
  }

  bool get _puedeIniciar {
    const numerosObligatorios = <int>{
      1,
      2,
      3,
      4,
      5,
      6,
    };

    return _casillasIniciales.length == 6 &&
        _valoresIniciales.length == 6 &&
        _valoresIniciales.containsAll(numerosObligatorios);
  }

  void _iniciarPartida() {
    if (!_puedeIniciar) {
      setState(() {
        _mensajeError =
            'Debes colocar los números del 1 al 6 sin repetir.';
      });
      return;
    }

    final controlador = ControladorPartida();

    controlador.establecerValoresIniciales(
      List<Celda>.from(_matriz),
    );

    widget.alIniciar(controlador);
  }

  material.Color _colorDeRegion(Region region) {
    switch (region) {
      case Region.verde:
        return material.Colors.green;
      case Region.azul:
        return material.Colors.blue;
      case Region.amarillo:
        return material.Colors.yellow;
      case Region.rojo:
        return material.Colors.red;
      case Region.morado:
        return material.Colors.purple;
    }
  }

  material.Color _colorTexto(Region region) {
    return region == Region.amarillo
        ? material.Colors.black
        : material.Colors.white;
  }

  @override
  material.Widget build(material.BuildContext context) {
    return material.Scaffold(
      appBar: material.AppBar(
        title: const material.Text('Números iniciales'),
      ),
      body: material.SafeArea(
        child: material.Padding(
          padding: const material.EdgeInsets.all(16),
          child: material.Column(
            children: [
              const material.Text(
                'Selecciona los 6 números iniciales.',
                textAlign: material.TextAlign.center,
                style: material.TextStyle(
                  fontSize: 20,
                  fontWeight: material.FontWeight.bold,
                ),
              ),
              const material.SizedBox(height: 8),
              const material.Text(
                'Selecciona las 6 casillas marcadas y coloca los números del 1 al 6 sin repetir.',
                textAlign: material.TextAlign.center,
              ),
              const material.SizedBox(height: 6),
              const material.Text(
                'Las reglas de color se aplicarán después de presionar Inicio.',
                textAlign: material.TextAlign.center,
              ),
              const material.SizedBox(height: 16),
              material.Expanded(
                child: material.Center(
                  child: material.AspectRatio(
                    aspectRatio: 1,
                    child: material.GridView.builder(
                      physics:
                          const material.NeverScrollableScrollPhysics(),
                      itemCount: _matriz.length,
                      gridDelegate:
                          const material.SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columnas,
                      ),
                      itemBuilder: (context, indice) {
                        final celda = _matriz[indice];
                        final estaSeleccionada =
                            indice == _indiceSeleccionado;

                        return material.InkWell(
                          onTap: () => _seleccionarCelda(indice),
                          child: material.Container(
                            alignment: material.Alignment.center,
                            decoration: material.BoxDecoration(
                              color: _colorDeRegion(celda.region),
                              border: material.Border.all(
                                color: estaSeleccionada
                                    ? material.Colors.black
                                    : celda.esInicial
                                        ? material.Colors.white
                                        : material.Colors.black38,
                                width: estaSeleccionada
                                    ? 5
                                    : celda.esInicial
                                        ? 3
                                        : 1,
                              ),
                              boxShadow: celda.esInicial
                                  ? [
                                      material.BoxShadow(
                                        color: material.Colors.white
                                            .withValues(alpha: 0.65),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: material.Text(
                              celda.valor?.toString() ?? '',
                              style: material.TextStyle(
                                color: _colorTexto(celda.region),
                                fontSize: 24,
                                fontWeight: material.FontWeight.bold,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const material.SizedBox(height: 8),
              material.Text(
                'Casillas iniciales detectadas: ${_casillasIniciales.length}/6 · '
                'Números distintos: ${_valoresIniciales.length}/6',
                textAlign: material.TextAlign.center,
                style: material.TextStyle(
                  color: _puedeIniciar
                      ? material.Colors.green.shade800
                      : material.Colors.black87,
                  fontWeight: material.FontWeight.bold,
                ),
              ),
              if (_mensajeError != null) ...[
                const material.SizedBox(height: 8),
                material.Text(
                  _mensajeError!,
                  textAlign: material.TextAlign.center,
                  style: const material.TextStyle(
                    color: material.Colors.red,
                    fontWeight: material.FontWeight.bold,
                  ),
                ),
              ],
              const material.SizedBox(height: 12),
              material.Wrap(
                alignment: material.WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var numero = 1; numero <= 6; numero++)
                    material.ElevatedButton(
                      onPressed: () => _colocarNumero(numero),
                      child: material.Text('$numero'),
                    ),
                  material.OutlinedButton.icon(
                    onPressed: _borrarNumero,
                    icon: const material.Icon(
                      material.Icons.backspace_outlined,
                    ),
                    label: const material.Text('Borrar'),
                  ),
                ],
              ),
              const material.SizedBox(height: 16),
              material.SizedBox(
                width: double.infinity,
                child: material.ElevatedButton(
                  onPressed: _puedeIniciar ? _iniciarPartida : null,
                  style: material.ElevatedButton.styleFrom(
                    padding: const material.EdgeInsets.symmetric(
                      vertical: 16,
                    ),
                  ),
                  child: material.Text(
                    _puedeIniciar
                        ? 'Inicio'
                        : 'Faltan números iniciales',
                    style: const material.TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}