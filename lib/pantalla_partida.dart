import 'package:flutter/material.dart' as material;

import 'bloc/partida_bloc.dart';
import 'dart_package_1.dart';

class PantallaPartida extends material.StatefulWidget {
  const PantallaPartida({
    super.key,
    required this.controlador,
  });

  final ControladorPartida controlador;

  @override
  material.State<PantallaPartida> createState() {
    return _PantallaPartidaState();
  }
}

class _PantallaPartidaState extends material.State<PantallaPartida> {
  late PartidaBloc _bloc;

  @override
  void initState() {
    super.initState();

    _bloc = PartidaBloc(
      controlador: widget.controlador,
    );
  }

  @override
  void dispose() {
    _bloc.dispose();
    super.dispose();
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

  void _mostrarSeleccionDados() {
    var primerDado = 1;
    var segundoDado = 1;

    material.showDialog(
      context: context,
      builder: (contextoDialogo) {
        return material.AlertDialog(
          title: const material.Text('Resultados de los dados'),
          content: material.Column(
            mainAxisSize: material.MainAxisSize.min,
            children: [
              material.DropdownButtonFormField<int>(
                value: primerDado,
                decoration: const material.InputDecoration(
                  labelText: 'Primer dado',
                ),
                items: [
                  for (var numero = 1; numero <= 6; numero++)
                    material.DropdownMenuItem<int>(
                      value: numero,
                      child: material.Text('$numero'),
                    ),
                ],
                onChanged: (valor) {
                  if (valor != null) {
                    primerDado = valor;
                  }
                },
              ),
              const material.SizedBox(height: 12),
              material.DropdownButtonFormField<int>(
                value: segundoDado,
                decoration: const material.InputDecoration(
                  labelText: 'Segundo dado',
                ),
                items: [
                  for (var numero = 1; numero <= 6; numero++)
                    material.DropdownMenuItem<int>(
                      value: numero,
                      child: material.Text('$numero'),
                    ),
                ],
                onChanged: (valor) {
                  if (valor != null) {
                    segundoDado = valor;
                  }
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
                _bloc.establecerDados(
                  primerDado,
                  segundoDado,
                );

                material.Navigator.of(contextoDialogo).pop();
              },
              child: const material.Text('Aceptar'),
            ),
          ],
        );
      },
    );
  }

  @override
  material.Widget build(material.BuildContext context) {
    return material.Scaffold(
      appBar: material.AppBar(
        title: const material.Text('Partida Brilliant'),
        actions: [
          material.IconButton(
            onPressed: _bloc.cancelarSeleccion,
            icon: const material.Icon(material.Icons.clear),
            tooltip: 'Cancelar selección',
          ),
        ],
      ),
      floatingActionButton: material.FloatingActionButton.extended(
        onPressed: _mostrarSeleccionDados,
        icon: const material.Icon(material.Icons.casino),
        label: const material.Text('Dados'),
      ),
      body: material.SafeArea(
        child: material.AnimatedBuilder(
          animation: _bloc,
          builder: (context, child) {
            return material.Padding(
              padding: const material.EdgeInsets.all(16),
              child: material.Column(
                children: [
                  material.Card(
                    child: material.Padding(
                      padding: const material.EdgeInsets.all(16),
                      child: material.Row(
                        mainAxisAlignment:
                            material.MainAxisAlignment.spaceAround,
                        children: [
                          material.Column(
                            children: [
                              const material.Text('Puntuación'),
                              material.Text(
                                '${_bloc.puntuacionTotal}',
                                style: const material.TextStyle(
                                  fontSize: 32,
                                  fontWeight: material.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          material.Column(
                            children: [
                              const material.Text('Dados'),
                              material.Text(
                                _bloc.hayDados
                                    ? '${_bloc.dadoUno} | ${_bloc.dadoDos}'
                                    : '- | -',
                                style: const material.TextStyle(
                                  fontSize: 28,
                                  fontWeight: material.FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const material.SizedBox(height: 12),
                  if (_bloc.hayDados)
                    material.Row(
                      mainAxisAlignment:
                          material.MainAxisAlignment.spaceEvenly,
                      children: [
                        material.ElevatedButton(
                          onPressed: () {
                            _bloc.seleccionarAncla(_bloc.dadoUno!);
                          },
                          child: material.Text(
                            'Ancla: ${_bloc.dadoUno}',
                          ),
                        ),
                        material.ElevatedButton(
                          onPressed: () {
                            _bloc.seleccionarAncla(_bloc.dadoDos!);
                          },
                          child: material.Text(
                            'Ancla: ${_bloc.dadoDos}',
                          ),
                        ),
                      ],
                    ),
                  const material.SizedBox(height: 12),
                  material.Text(
                    _bloc.mensaje ??
                        'Presiona Dados y selecciona uno como ancla.',
                    textAlign: material.TextAlign.center,
                    style: const material.TextStyle(
                      fontSize: 16,
                      fontWeight: material.FontWeight.bold,
                    ),
                  ),
                  const material.SizedBox(height: 12),
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
                            final esPosible = _bloc.esPosible(indice);

                            return material.InkWell(
                              onTap: esPosible
                                  ? () => _bloc.colocarNumero(indice)
                                  : null,
                              child: material.AnimatedContainer(
                                duration: const Duration(
                                  milliseconds: 180,
                                ),
                                alignment: material.Alignment.center,
                                decoration: material.BoxDecoration(
                                  color: _colorVisual(celda.region),
                                  border: material.Border.all(
                                    color: esPosible
                                        ? material.Colors.white
                                        : material.Colors.black26,
                                    width: esPosible ? 5 : 1,
                                  ),
                                  boxShadow: esPosible
                                      ? [
                                          material.BoxShadow(
                                            color: material.Colors.white
                                                .withOpacity(0.9),
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
                  const material.Text(
                    'Las casillas con borde blanco brillante son lugares válidos para colocar el otro número.',
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