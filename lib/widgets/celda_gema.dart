import 'package:flutter/material.dart';

import '../dart_package_1.dart';
import '../tema.dart';

class CeldaGema extends StatelessWidget {
  const CeldaGema({
    super.key,
    required this.region,
    this.valor,
    this.vistaPrevia,
    this.esInicial = false,
    this.seleccionada = false,
    this.esDestino = false,
    this.esAncla = false,
    this.completada = false,
    this.onTap,
  });

  final Region region;
  final int? valor;
  final int? vistaPrevia;
  final bool esInicial;
  final bool seleccionada;
  final bool esDestino;
  final bool esAncla;
  final bool completada;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final base = Tema.color(region);

    Color colorBorde;
    double anchoBorde;

    if (seleccionada) {
      colorBorde = Tema.dorado;
      anchoBorde = 3.5;
    } else if (esDestino) {
      colorBorde = Colors.white;
      anchoBorde = 3;
    } else if (esAncla) {
      colorBorde = Tema.dorado;
      anchoBorde = 3;
    } else if (completada) {
      colorBorde = Tema.dorado.withValues(alpha: 0.8);
      anchoBorde = 2;
    } else if (esInicial) {
      colorBorde = Colors.white.withValues(alpha: 0.85);
      anchoBorde = 2;
    } else {
      colorBorde = Colors.black.withValues(alpha: 0.18);
      anchoBorde = 1;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(base, Colors.white, 0.25)!,
              base,
              Color.lerp(base, Colors.black, 0.25)!,
            ],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorBorde, width: anchoBorde),
          boxShadow: esDestino
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: 0.9),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: LayoutBuilder(
          builder: (context, restricciones) {
            final tamano = restricciones.maxWidth * 0.46;

            return Stack(
              alignment: Alignment.center,
              children: [
                if (valor != null)
                  Text(
                    '$valor',
                    style: TextStyle(
                      fontSize: tamano,
                      fontWeight: FontWeight.w800,
                      color: Tema.colorTexto(region),
                    ),
                  ),
                if (valor == null && esDestino && vistaPrevia != null)
                  Text(
                    '$vistaPrevia',
                    style: TextStyle(
                      fontSize: tamano,
                      fontWeight: FontWeight.w800,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                if (esInicial)
                  Positioned(
                    top: 2,
                    right: 3,
                    child: Icon(
                      Icons.star_rounded,
                      size: restricciones.maxWidth * 0.24,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class TableroGemas extends StatelessWidget {
  const TableroGemas({super.key, required this.celdas});

  final List<Widget> celdas;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Tema.tablero,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: GridView.count(
            crossAxisCount: 7,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            children: celdas,
          ),
        ),
      ),
    );
  }
}
