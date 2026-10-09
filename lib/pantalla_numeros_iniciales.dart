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

  final Map<Region, Tipo> _tiposPorRegion = {
    Region.verde: TipoVerde(),
    Region.azul: TipoAzul(),
    Region.amarillo: TipoAmarillo(),
    Region.rojo: TipoRojo(),
    Region.morado: TipoMorado(),
  };

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

    const indicesIniciales = {
      2,
      12,
      22,
      32,
      42,
      47,
    };

    _matriz = _distribucion.asMap().entries.map((entrada) {
      return Celda(
        region: entrada.value,
        esInicial: indicesIniciales.contains(entrada.key),
      );
    }).toList();
  }

  void _seleccionarCelda(int indice) {
    if (!_matriz[indice].esInicial) {
      setState(() {
        _mensajeError = 'Solo puedes seleccionar una de las 6 casillas iniciales.';
      });
      return;
    }

    setState(() {
      _indiceSeleccionado = indice;
      _mensajeError = null;
    });
  }

  void _colocarNumero(int numero) {
    if (numero < 1 || numero > 6) {
      setState(() {
        _mensajeError = 'Solo se permiten números del 1 al 6.';
      });
      return;
    }

    if (_indiceSeleccionado == null) {
      setState(() {
        _mensajeError =
            'Selecciona una de las 6 casillas iniciales antes de colocar un número.';
      });
      return;
    }

    final repetido = _matriz.asMap().entries.any(
      (entrada) =>
          entrada.key != _indiceSeleccionado &&
          entrada.value.esInicial &&
          entrada.value.valor == numero,
    );

    if (repetido) {
      setState(() {
        _mensajeError = 'El número $numero ya fue seleccionado.';
      });
      return;
    }

    final celdaActual = _matriz[_indiceSeleccionado!];

    final valoresRegion = obtenerValoresForIn(
      _matriz,
      celdaActual.region,
    );

    final valoresSinCeldaActual = List<int>.from(valoresRegion);

    if (celdaActual.valor != null) {
      valoresSinCeldaActual.remove(celdaActual.valor);
    }

    final tipo = _tiposPorRegion[celdaActual.region]!;

    if (!tipo.esPosibleAgregar(valoresSinCeldaActual, numero)) {
      setState(() {
        _mensajeError =
            'El número $numero no cumple la regla de esta región.';
      });
      return;
    }

    setState(() {
      _matriz[_indiceSeleccionado!] = celdaActual.copiarCon(
        valor: numero,
      );
      _mensajeError = null;
    });
  }

  void _borrarNumero() {
    if (_indiceSeleccionado == null) {
      setState(() {
        _mensajeError =
            'Selecciona una de las 6 casillas iniciales antes de borrar.';
      });
      return;
    }

    final celdaActual = _matriz[_indiceSeleccionado!];

    if (celdaActual.valor == null) {
      setState(() {
        _mensajeError = 'La casilla seleccionada está vacía.';
      });
      return;
    }

    setState(() {
      _matriz[_indiceSeleccionado!] = celdaActual.copiarCon(
        valor: null,
      );
      _mensajeError = null;
    });
  }

  bool get _todasLasCasillasInicialesTienenNumero {
    final valores = _matriz
        .where((celda) => celda.esInicial && celda.valor != null)
        .map((celda) => celda.valor!)
        .toSet();

    return valores.length == 6 &&
        valores.containsAll({
          1,
          2,
          3,
          4,
          5,
          6,
        });
  }

  bool get _noHayNumerosInicialesRepetidos {
    final valores = _matriz
        .where((celda) => celda.esInicial && celda.valor != null)
        .map((celda) => celda.valor!)
        .toList();

    return valores.length == valores.toSet().length;
  }

  bool get _reglasDeRegionesValidas {
    for (final region in Region.values) {
      final tipo = _tiposPorRegion[region]!;
      final valores = obtenerValoresForIn(_matriz, region);

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

  bool get _puedeIniciar {
    return _todasLasCasillasInicialesTienenNumero &&
        _noHayNumerosInicialesRepetidos &&
        _reglasDeRegionesValidas;
  }

  void _iniciarPartida() {
    if (!_puedeIniciar) {
      setState(() {
        _mensajeError =
            'Coloca los números del 1 al 6, sin repetir y respetando las reglas.';
      });
      return;
    }

    final controlador = ControladorPartida();
    controlador.establecerValoresIniciales(_matriz);

    widget.alIniciar(controlador);
  }

  material.Color _colorVisual(Region region) {
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
    if (region == Region.amarillo) {
      return material.Colors.black;
    }

    return material.Colors.white;
  }

  String _descripcionDeRegionSeleccionada() {
    if (_indiceSeleccionado == null) {
      return '';
    }

    final region = _matriz[_indiceSeleccionado!].region;

    return _tiposPorRegion[region]!.descripcion;
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
              const material.SizedBox(height: 8),
              const material.Text(
                'Cada número inicial debe respetar la regla de su región.',
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
                        final seleccionada =
                            indice == _indiceSeleccionado;

                        return material.InkWell(
                          onTap: () => _seleccionarCelda(indice),
                          child: material.Container(
                            alignment: material.Alignment.center,
                            decoration: material.BoxDecoration(
                              color: _colorVisual(celda.region),
                              border: material.Border.all(
                                color: seleccionada
                                    ? material.Colors.black
                                    : celda.esInicial
                                        ? material.Colors.white
                                        : material.Colors.grey.shade700,
                                width: seleccionada ? 4 : 1,
                              ),
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
              const material.SizedBox(height: 12),
              if (_indiceSeleccionado != null)
                material.Text(
                  _descripcionDeRegionSeleccionada(),
                  textAlign: material.TextAlign.center,
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
                  child: const material.Text(
                    'Inicio',
                    style: material.TextStyle(fontSize: 18),
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