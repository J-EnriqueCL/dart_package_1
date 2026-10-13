import 'package:flutter/material.dart';

import 'dart_package_1.dart';
import 'pantalla_partida.dart';
import 'tema.dart';
import 'widgets/celda_gema.dart';

class PantallaNumerosIniciales extends StatefulWidget {
  const PantallaNumerosIniciales({super.key});

  @override
  State<PantallaNumerosIniciales> createState() =>
      _PantallaNumerosInicialesState();
}

class _PantallaNumerosInicialesState extends State<PantallaNumerosIniciales> {
  late List<Celda> _matriz;
  int? _seleccionada;
  String _mensaje = 'Toca una casilla con estrella y elige su número.';

  @override
  void initState() {
    super.initState();
    _matriz = crearTableroNivelUno();
  }

  Set<int> get _usados {
    return _matriz
        .where((celda) => celda.esInicial)
        .map((celda) => celda.valor)
        .whereType<int>()
        .toSet();
  }

  bool get _completo => _usados.length == 6;

  void _tocar(int indice) {
    if (!_matriz[indice].esInicial) {
      setState(() {
        _mensaje = 'Solo las casillas con estrella llevan número inicial.';
      });
      return;
    }

    setState(() {
      _seleccionada = indice;
      _mensaje = 'Elige el número de esta casilla.';
    });
  }

  void _poner(int numero) {
    final indice = _seleccionada;

    if (indice == null) {
      setState(() {
        _mensaje = 'Primero toca una casilla con estrella.';
      });
      return;
    }

    setState(() {
      _matriz[indice] = _matriz[indice].copiarCon(valor: numero);

      final siguiente = _matriz.indexWhere(
        (celda) => celda.esInicial && celda.valor == null,
      );

      if (siguiente != -1) {
        _seleccionada = siguiente;
      }

      _mensaje = _completo
          ? 'Todo listo. Presiona Inicio.'
          : 'Número $numero colocado.';
    });
  }

  void _borrar() {
    final indice = _seleccionada;

    if (indice == null) {
      return;
    }

    setState(() {
      _matriz[indice] = _matriz[indice].copiarCon(borrarValor: true);
      _mensaje = 'Casilla vacía.';
    });
  }

  void _iniciar() {
    final controlador = ControladorPartida();

    try {
      controlador.establecerValoresIniciales(_matriz);
    } on ArgumentError catch (error) {
      setState(() {
        _mensaje = '${error.message}';
      });
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PantallaPartida(controlador: controlador),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final usados = _usados;
    final valorSeleccionado =
        _seleccionada == null ? null : _matriz[_seleccionada!].valor;

    return Scaffold(
      body: FondoJuego(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 14, bottom: 2),
                    child: Text(
                      'BRILLIANT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                  const Text(
                    'Coloca los números del 1 al 6 en las casillas con estrella',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: TableroGemas(
                        celdas: [
                          for (var i = 0; i < _matriz.length; i++)
                            CeldaGema(
                              region: _matriz[i].region,
                              valor: _matriz[i].valor,
                              esInicial: _matriz[i].esInicial,
                              seleccionada: i == _seleccionada,
                              onTap: () => _tocar(i),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    decoration: const BoxDecoration(
                      color: Tema.panel,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(26)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _mensaje,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (var numero = 1; numero <= 6; numero++)
                              SizedBox(
                                width: 52,
                                height: 52,
                                child: FilledButton(
                                  onPressed: usados.contains(numero) &&
                                          valorSeleccionado != numero
                                      ? null
                                      : () => _poner(numero),
                                  style: FilledButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    backgroundColor: Colors.white,
                                    foregroundColor: Tema.tinta,
                                    disabledBackgroundColor: Colors.white12,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: Text(
                                    '$numero',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            SizedBox(
                              height: 52,
                              child: OutlinedButton.icon(
                                onPressed: _borrar,
                                icon: const Icon(Icons.backspace_outlined),
                                label: const Text('Borrar'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _completo ? _iniciar : null,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Inicio'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Tema.dorado,
                              foregroundColor: Tema.tinta,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              textStyle: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}