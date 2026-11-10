import 'package:flutter/material.dart';

import '../tema.dart';

class Pastilla extends StatelessWidget {
  const Pastilla({
    required this.icono,
    required this.texto,
    this.destacado = false,
  });

  final IconData icono;
  final String texto;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: destacado ? Tema.dorado : Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 16, color: destacado ? Tema.tinta : Colors.white),
          const SizedBox(width: 6),
          Text(
            texto,
            style: TextStyle(
              color: destacado ? Tema.tinta : Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

enum RolDado { ninguno, ancla, aColocar }

class Dado extends StatelessWidget {
  const Dado({
    super.key,
    required this.valor,
    required this.rol,
    required this.activo,
    required this.onTap,
    this.tamano = 92,
  });

  /// Lado del dado; en pantallas bajas se usa uno menor (todo escala).
  final double tamano;
  final int? valor;
  final RolDado rol;
  final bool activo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final esAncla = rol == RolDado.ancla;
    final esColocar = rol == RolDado.aColocar;

    String etiqueta = 'DADO';
    if (esAncla) {
      etiqueta = 'ANCLA';
    } else if (esColocar) {
      etiqueta = 'A COLOCAR';
    } else if (valor != null) {
      etiqueta = 'ELEGIR';
    }

    final escala = tamano / 92;

    return Opacity(
      opacity: activo ? 1 : 0.4,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: tamano,
          height: tamano,
          decoration: BoxDecoration(
            color: esAncla ? Tema.dorado : Colors.white,
            borderRadius: BorderRadius.circular(20 * escala),
            border: Border.all(
              color: esColocar ? Tema.dorado : Colors.transparent,
              width: 4 * escala,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                valor?.toString() ?? '?',
                style: TextStyle(
                  fontSize: 40 * escala,
                  fontWeight: FontWeight.w900,
                  color: Tema.tinta,
                ),
              ),
              Text(
                etiqueta,
                style: TextStyle(
                  fontSize: 10 * escala,
                  fontWeight: FontWeight.w800,
                  color: Tema.tinta,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
