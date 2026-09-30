import 'package:flutter/material.dart';

import 'dart_package_1.dart';
import 'pantalla_numeros_iniciales.dart';

void main() {
  runApp(const AplicacionJuego());
}

class AplicacionJuego extends StatelessWidget {
  const AplicacionJuego({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Juego de números',
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: PantallaNumerosIniciales(
        alIniciar: (controlador) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) {
                return PantallaPartidaIniciada(
                  controlador: controlador,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class PantallaPartidaIniciada extends StatelessWidget {
  const PantallaPartidaIniciada({
    super.key,
    required this.controlador,
  });

  final ControladorPartida controlador;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Partida iniciada'),
      ),
      body: Center(
        child: Text(
          'Valores iniciales guardados.\n'
          'Celdas en la matriz: ${controlador.matriz.length}',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20),
        ),
      ),
    );
  }
}