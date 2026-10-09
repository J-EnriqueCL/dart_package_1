import 'package:flutter/material.dart' as material;

import 'bloc/partida_bloc.dart';
import 'dart_package_1.dart';

class PantallaPartida extends material.StatefulWidget {
  const PantallaPartida({super.key, required this.controlador});

  final ControladorPartida controlador;

  @override
  material.State<PantallaPartida> createState() {
    return _PantallaPartidaState();
  }
}

class _PantallaPartidaState extends material.State<PantallaPartida> {
  late final PartidaBloc _bloc;

  @override
  void initState() {
    super.initState();

    _bloc = PartidaBloc(controlador: widget.controlador);
  }

  @override
  void dispose() {
    _bloc.dispose();
    super.dispose();
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

  void _mostrarDialogoDados() {
    var resultadoDadoUno = 1;
    var resultadoDadoDos = 1;

    material.showDialog<void>(
      context: context,
      builder: (contextoDialogo) {
        return material.StatefulBuilder(
          builder: (context, actualizarDialogo) {
            return material.AlertDialog(
              title: const material.Text('Tirar dados'),
              content: material.Column(
                mainAxisSize: material.MainAxisSize.min,
                children: [
                  const material.Text(
                    'Selecciona los dos resultados obtenidos.',
                    textAlign: material.TextAlign.center,
                  ),
                  const material.SizedBox(height: 16),
                  material.DropdownButtonFormField<int>(
                    value: resultadoDadoUno,
                    decoration: const material.InputDecoration(
                      labelText: 'Dado 1',
                      border: material.OutlineInputBorder(),
                    ),
                    items: [
                      for (var numero = 1; numero <= 6; numero++)
                        material.DropdownMenuItem<int>(
                          value: numero,
                          child: material.Text('$numero'),
                        ),
                    ],
                    onChanged: (valor) {
                      if (valor == null) {
                        return;
                      }

                      actualizarDialogo(() {
                        resultadoDadoUno = valor;
                      });
                    },
                  ),
                  const material.SizedBox(height: 16),
                  material.DropdownButtonFormField<int>(
                    value: resultadoDadoDos,
                    decoration: const material.InputDecoration(
                      labelText: 'Dado 2',
                      border: material.OutlineInputBorder(),
                    ),
                    items: [
                      for (var numero = 1; numero <= 6; numero++)
                        material.DropdownMenuItem<int>(
                          value: numero,
                          child: material.Text('$numero'),
                        ),
                    ],
                    onChanged: (valor) {
                      if (valor == null) {
                        return;
                      }

                      actualizarDialogo(() {
                        resultadoDadoDos = valor;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                material.TextButton(
                  onPressed: () {
                    material.Navigator.of(contextoDialogo).pop();
                  },
                  child: const material.Text('Cancelar'),
                ),
                material.ElevatedButton(
                  onPressed: () {
                    _bloc.lanzarDados(resultadoDadoUno, resultadoDadoDos);

                    material.Navigator.of(contextoDialogo).pop();
                  },
                  child: const material.Text('Aceptar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  material.Widget _botonDado({required int numero}) {
    final esAncla = _bloc.numeroAncla == numero;

    return material.InkWell(
      onTap: () {
        _bloc.seleccionarAncla(numero);
      },
      borderRadius: material.BorderRadius.circular(18),
      child: material.AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 98,
        height: 108,
        alignment: material.Alignment.center,
        decoration: material.BoxDecoration(
          color: esAncla
              ? material.Colors.amber.shade300
              : material.Colors.white,
          borderRadius: material.BorderRadius.circular(18),
          border: material.Border.all(
            color: esAncla
                ? material.Colors.deepOrange
                : material.Colors.black54,
            width: esAncla ? 5 : 2,
          ),
          boxShadow: [
            material.BoxShadow(
              color: material.Colors.black.withOpacity(0.16),
              blurRadius: 6,
              offset: const material.Offset(0, 3),
            ),
          ],
        ),
        child: material.Column(
          mainAxisAlignment: material.MainAxisAlignment.center,
          children: [
            material.Text(
              '$numero',
              style: const material.TextStyle(
                fontSize: 42,
                fontWeight: material.FontWeight.bold,
              ),
            ),
            const material.SizedBox(height: 6),
            material.Text(
              esAncla ? 'ANCLA' : 'ELEGIR',
              style: material.TextStyle(
                color: esAncla
                    ? material.Colors.deepOrange.shade900
                    : material.Colors.black87,
                fontSize: 12,
                fontWeight: material.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  material.Widget _panelDados() {
    if (!_bloc.hayDados) {
      return material.Card(
        child: material.Padding(
          padding: const material.EdgeInsets.all(14),
          child: material.Column(
            children: [
              const material.Text(
                'Dados',
                style: material.TextStyle(
                  fontSize: 18,
                  fontWeight: material.FontWeight.bold,
                ),
              ),
              const material.SizedBox(height: 8),
              const material.Text(
                'Presiona “Tirar dados” para iniciar un turno.',
                textAlign: material.TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return material.Card(
      color: material.Colors.grey.shade100,
      child: material.Padding(
        padding: const material.EdgeInsets.all(14),
        child: material.Column(
          children: [
            const material.Text(
              'Dados lanzados',
              style: material.TextStyle(
                fontSize: 18,
                fontWeight: material.FontWeight.bold,
              ),
            ),
            const material.SizedBox(height: 8),
            material.Text(
              _bloc.esperandoAncla
                  ? 'Toca un dado para elegir el ancla.'
                  : 'El dado resaltado es el ancla.',
              textAlign: material.TextAlign.center,
            ),
            const material.SizedBox(height: 12),
            material.Row(
              mainAxisAlignment: material.MainAxisAlignment.spaceEvenly,
              children: [
                _botonDado(numero: _bloc.dadoUno!),
                _botonDado(numero: _bloc.dadoDos!),
              ],
            ),
            if (_bloc.esperandoDestino) ...[
              const material.SizedBox(height: 12),
              material.Container(
                width: double.infinity,
                padding: const material.EdgeInsets.all(10),
                decoration: material.BoxDecoration(
                  color: material.Colors.amber.shade100,
                  borderRadius: material.BorderRadius.circular(10),
                ),
                child: material.Text(
                  'Ancla: ${_bloc.numeroAncla}. '
                  'Coloca el número ${_bloc.numeroPorColocar} '
                  'en una casilla iluminada.',
                  textAlign: material.TextAlign.center,
                  style: const material.TextStyle(
                    fontWeight: material.FontWeight.bold,
                  ),
                ),
              ),
              const material.SizedBox(height: 4),
              material.TextButton.icon(
                onPressed: _bloc.cancelarSeleccionAncla,
                icon: const material.Icon(material.Icons.restart_alt),
                label: const material.Text('Cambiar ancla'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  material.Widget build(material.BuildContext context) {
    return material.Scaffold(
      appBar: material.AppBar(title: const material.Text('Partida Brilliant')),
      floatingActionButton: material.FloatingActionButton.extended(
        onPressed: _mostrarDialogoDados,
        icon: const material.Icon(material.Icons.casino),
        label: const material.Text('Tirar dados'),
      ),
      body: material.SafeArea(
        child: material.AnimatedBuilder(
          animation: _bloc,
          builder: (context, child) {
            return material.Padding(
              padding: const material.EdgeInsets.all(12),
              child: material.Column(
                children: [
                  material.Row(
                    children: [
                      material.Expanded(
                        child: material.Card(
                          child: material.Padding(
                            padding: const material.EdgeInsets.all(12),
                            child: material.Column(
                              children: [
                                const material.Text('Puntuación'),
                                material.Text(
                                  '${_bloc.puntuacionTotal}',
                                  style: const material.TextStyle(
                                    fontSize: 30,
                                    fontWeight: material.FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const material.SizedBox(width: 8),
                      material.Expanded(
                        child: material.Card(
                          child: material.Padding(
                            padding: const material.EdgeInsets.all(12),
                            child: material.Column(
                              children: [
                                const material.Text('Turno'),
                                material.Text(
                                  '${_bloc.turno}',
                                  style: const material.TextStyle(
                                    fontSize: 30,
                                    fontWeight: material.FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const material.SizedBox(height: 8),
                  _panelDados(),
                  const material.SizedBox(height: 8),
                  material.Container(
                    width: double.infinity,
                    padding: const material.EdgeInsets.all(10),
                    decoration: material.BoxDecoration(
                      color: material.Colors.blueGrey.shade50,
                      borderRadius: material.BorderRadius.circular(10),
                    ),
                    child: material.Text(
                      _bloc.mensaje,
                      textAlign: material.TextAlign.center,
                    ),
                  ),
                  const material.SizedBox(height: 10),
                  material.Expanded(
                    child: material.Center(
                      child: material.AspectRatio(
                        aspectRatio: 1,
                        child: material.GridView.builder(
                          physics:
                              const material.NeverScrollableScrollPhysics(),
                          itemCount: _bloc.matriz.length,
                          gridDelegate:
                              const material.SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: PartidaBloc.columnas,
                              ),
                          itemBuilder: (context, indice) {
                            final celda = _bloc.matriz[indice];
                            final esDestinoPosible = _bloc.esDestinoPosible(
                              indice,
                            );

                            return material.InkWell(
                              onTap: esDestinoPosible
                                  ? () => _bloc.colocarNumero(indice)
                                  : null,
                              child: material.AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                alignment: material.Alignment.center,
                                decoration: material.BoxDecoration(
                                  color: _colorDeRegion(celda.region),
                                  border: material.Border.all(
                                    color: esDestinoPosible
                                        ? material.Colors.white
                                        : material.Colors.black38,
                                    width: esDestinoPosible ? 5 : 1,
                                  ),
                                  boxShadow: esDestinoPosible
                                      ? [
                                          material.BoxShadow(
                                            color: material.Colors.white
                                                .withOpacity(0.95),
                                            blurRadius: 12,
                                            spreadRadius: 2,
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
                  const material.SizedBox(height: 4),
                  const material.Text(
                    'Las casillas con borde blanco son los lugares válidos para colocar el otro dado.',
                    textAlign: material.TextAlign.center,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
