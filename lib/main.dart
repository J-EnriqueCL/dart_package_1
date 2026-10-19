import 'package:flutter/material.dart';

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
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.deepPurple,
      ),
      home: const PantallaNumerosIniciales(),
    );
  }
}
