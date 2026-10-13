import 'package:flutter/material.dart';

import 'bloc/partida_bloc.dart';
import 'dart_package_1.dart';
import 'tema.dart';
import 'widgets/celda_gema.dart';

class PantallaPartida extends StatefulWidget {
  const PantallaPartida({super.key, required this.controlador});

  final ControladorPartida controlador;

  @override
  State<PantallaPartida> createState() => _PantallaPartidaState();
}

class _PantallaPartidaState extends State<PantallaPartida> {
  late final PartidaBloc _bloc;

  @override
  void initState() {
    super.initState();
    _bloc = PartidaBloc(widget.controlador);
  }

  @override
  void dispose() {
    _bloc.dispose();
    super.dispose();
  }

  void _mostrarDetalle() {
    final areas = [..._bloc.areas]..sort((a, b) {
        if (a.region.index != b.region.index) {
          return a.region.index.compareTo(b.region.index);
        }
        return a.id.compareTo(b.id);
      });

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tema.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            child: ListView(
              padding: const EdgeInsets.all(16),
              shrinkWrap: true,
              children: [
                const Text(
                  'Puntos por región',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Total: ${_bloc.puntuacionTotal} puntos',
                  style: const TextStyle(color: Tema.dorado, fontSize: 16),
                ),
                const SizedBox(height: 12),
                for (final area in areas) _filaArea(area),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _filaArea(Area area) {
    final llenas = _bloc.casillasLlenas(area);
    final completa = _bloc.areaCompleta(area);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Tema.color(area.region),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${area.region.nombre} · ${area.tamano} casillas',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  area.region.regla,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: llenas / area.tamano,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(4),
                  color: Tema.color(area.region),
                  backgroundColor: Colors.white12,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            completa ? '+${area.puntos}' : '$llenas/${area.tamano}',
            style: TextStyle(
              color: completa ? Tema.dorado : Colors.white70,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _encabezado() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Volver a los números iniciales',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          const Text(
            'BRILLIANT',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
          const Spacer(),
          _Pastilla(icono: Icons.flag_rounded, texto: 'Turno ${_bloc.turno}'),
          const SizedBox(width: 8),
          _Pastilla(
            icono: Icons.diamond_rounded,
            texto: '${_bloc.puntuacionTotal} pts',
            destacado: true,
          ),
        ],
      ),
    );
  }

  Widget _resumenRegiones() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9),
      child: Row(
        children: [
          for (final region in Region.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _mostrarDetalle,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: Tema.color(region),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '${_bloc.puntosDeRegion(region)}',
                          style: TextStyle(
                            color: Tema.colorTexto(region),
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          '${_bloc.areasCompletas(region)}/${_bloc.totalAreas(region)} áreas',
                          style: TextStyle(
                            color: Tema.colorTexto(region),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _panelInferior() {
    final dados = _bloc.dados;

    _RolDado rol(int posicion) {
      if (_bloc.posicionAncla == null) {
        return _RolDado.ninguno;
      }
      return _bloc.posicionAncla == posicion
          ? _RolDado.ancla
          : _RolDado.aColocar;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Tema.panel,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _bloc.mensaje,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var posicion = 0; posicion < 2; posicion++) ...[
                if (posicion == 1) const SizedBox(width: 18),
                _Dado(
                  valor: dados?[posicion],
                  rol: rol(posicion),
                  activo: dados == null || _bloc.dadoTieneMovimientos(posicion),
                  onTap: dados == null
                      ? null
                      : () => _bloc.seleccionarAncla(posicion),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _bloc.hayDados ? null : _bloc.tirarDados,
                  icon: const Icon(Icons.casino_rounded),
                  label: const Text('Tirar dados'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Tema.dorado,
                    foregroundColor: Tema.tinta,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _bloc.hayDados ? _bloc.pasarTurno : null,
                  icon: const Icon(Icons.skip_next_rounded),
                  label: const Text('Pasar turno'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FondoJuego(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListenableBuilder(
                listenable: _bloc,
                builder: (context, _) {
                  final matriz = _bloc.matriz;

                  return Column(
                    children: [
                      _encabezado(),
                      _resumenRegiones(),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: TableroGemas(
                            celdas: [
                              for (var i = 0; i < matriz.length; i++)
                                CeldaGema(
                                  region: matriz[i].region,
                                  valor: matriz[i].valor,
                                  vistaPrevia: _bloc.numeroPorColocar,
                                  esInicial: matriz[i].esInicial,
                                  esDestino: _bloc.esDestino(i),
                                  esAncla: _bloc.esCeldaAncla(i),
                                  completada: _bloc.celdaEnAreaCompleta(i),
                                  onTap: _bloc.esDestino(i)
                                      ? () => _bloc.colocar(i)
                                      : null,
                                ),
                            ],
                          ),
                        ),
                      ),
                      _panelInferior(),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pastilla extends StatelessWidget {
  const _Pastilla({
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

enum _RolDado { ninguno, ancla, aColocar }

class _Dado extends StatelessWidget {
  const _Dado({
    required this.valor,
    required this.rol,
    required this.activo,
    required this.onTap,
  });

  final int? valor;
  final _RolDado rol;
  final bool activo;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final esAncla = rol == _RolDado.ancla;
    final esColocar = rol == _RolDado.aColocar;

    String etiqueta = 'DADO';
    if (esAncla) {
      etiqueta = 'ANCLA';
    } else if (esColocar) {
      etiqueta = 'A COLOCAR';
    } else if (valor != null) {
      etiqueta = 'ELEGIR';
    }

    return Opacity(
      opacity: activo ? 1 : 0.4,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            color: esAncla ? Tema.dorado : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: esColocar ? Tema.dorado : Colors.transparent,
              width: 4,
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
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  color: Tema.tinta,
                ),
              ),
              Text(
                etiqueta,
                style: const TextStyle(
                  fontSize: 10,
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