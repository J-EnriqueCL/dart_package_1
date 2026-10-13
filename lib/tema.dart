import 'package:flutter/material.dart';

import 'dart_package_1.dart';

class Tema {
  static const Color fondoArriba = Color(0xFF1E1554);
  static const Color fondoAbajo = Color(0xFF0A0720);
  static const Color panel = Color(0xFF2A1F6B);
  static const Color tablero = Color(0xFF0E0A2B);
  static const Color dorado = Color(0xFFFFD54A);
  static const Color tinta = Color(0xFF24184F);

  static Color color(Region region) {
    switch (region) {
      case Region.verde:
        return const Color(0xFF2FB26A);
      case Region.azul:
        return const Color(0xFF2E7BE6);
      case Region.amarillo:
        return const Color(0xFFFFC928);
      case Region.rojo:
        return const Color(0xFFE23B4E);
      case Region.morado:
        return const Color(0xFF9B4FD0);
    }
  }

  static Color colorTexto(Region region) {
    return region == Region.amarillo ? const Color(0xFF4A3500) : Colors.white;
  }
}

class FondoJuego extends StatelessWidget {
  const FondoJuego({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Tema.fondoArriba, Tema.fondoAbajo],
        ),
      ),
      child: child,
    );
  }
}