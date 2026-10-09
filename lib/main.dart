import 'package:flutter/material.dart';

import 'pantalla_numeros_iniciales.dart';
import 'pantalla_partida.dart';

void main() {
  runApp(const AplicacionJuego());
}

class AplicacionJuego extends StatelessWidget {
  const AplicacionJuego({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Brilliant',
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        useMaterial3: true,
      ),
      home: PantallaNumerosIniciales(
        alIniciar: (controlador) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) {
                return PantallaPartida(
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