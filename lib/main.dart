import 'package:flutter/material.dart';

import 'dart_package_1.dart';
import 'pantalla_numeros_iniciales.dart';

void main() {
  runApp(const AplicacionBrilliant());
}

class AplicacionBrilliant extends StatelessWidget {
  const AplicacionBrilliant({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Brilliant',
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const PantallaInicioAplicacion(),
    );
  }
}

class PantallaInicioAplicacion extends StatelessWidget {
  const PantallaInicioAplicacion({super.key});

  void _abrirPantallaDados(
    BuildContext context,
    ControladorPartida controlador,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) {
          return PantallaDados(controlador: controlador);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PantallaNumerosIniciales(
      alIniciar: (controlador) {
        _abrirPantallaDados(context, controlador);
      },
    );
  }
}

class PantallaDados extends StatefulWidget {
  const PantallaDados({super.key, required this.controlador});

  final ControladorPartida controlador;

  @override
  State<PantallaDados> createState() => _PantallaDadosState();
}

class _PantallaDadosState extends State<PantallaDados> {
  int? _dadoUno;
  int? _dadoDos;
  int? _anclaSeleccionada;

  void _tirarDados() {
    setState(() {
      _dadoUno = 2;
      _dadoDos = 5;
      _anclaSeleccionada = null;
    });
  }

  void _seleccionarAncla(int numero) {
    if (_dadoUno == null || _dadoDos == null) {
      return;
    }

    setState(() {
      _anclaSeleccionada = numero;
    });
  }

  @override
  Widget build(BuildContext context) {
    final numeroAColocar = _anclaSeleccionada == null
        ? null
        : _anclaSeleccionada == _dadoUno
        ? _dadoDos
        : _dadoUno;

    return Scaffold(
      appBar: AppBar(title: const Text('Partida Brilliant')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text(
                'Comienza el juego con los dados',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              const Text(
                'Presiona el botón para mostrar los dos números.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _DadoVisual(
                    numero: _dadoUno,
                    seleccionado:
                        _anclaSeleccionada == _dadoUno && _dadoUno != null,
                    onTap: _dadoUno == null
                        ? null
                        : () => _seleccionarAncla(_dadoUno!),
                  ),
                  _DadoVisual(
                    numero: _dadoDos,
                    seleccionado:
                        _anclaSeleccionada == _dadoDos && _dadoDos != null,
                    onTap: _dadoDos == null
                        ? null
                        : () => _seleccionarAncla(_dadoDos!),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (_anclaSeleccionada != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Ancla seleccionada: $_anclaSeleccionada\n'
                    'Número que se colocará: $numeroAColocar',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _tirarDados,
                  icon: const Icon(Icons.casino),
                  label: Text(
                    _dadoUno == null ? 'Tirar dados' : 'Tirar nuevamente',
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
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

class _DadoVisual extends StatelessWidget {
  const _DadoVisual({
    required this.numero,
    required this.seleccionado,
    required this.onTap,
  });

  final int? numero;
  final bool seleccionado;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 110,
        height: 110,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: seleccionado ? Colors.amber.shade300 : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: seleccionado ? Colors.deepOrange : Colors.black54,
            width: seleccionado ? 5 : 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          numero?.toString() ?? '?',
          style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
