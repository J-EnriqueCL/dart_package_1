import 'dart:async';

import 'package:flutter/material.dart';

import '../dart_package_1.dart';
import '../tema.dart';
import '../widgets/celda_gema.dart';
import '../widgets/confirmar.dart';
import '../widgets/dado.dart';
import 'cliente_multijugador.dart';

/// Fase de preparación: cada jugador reparte el 1..6 en las seis posiciones
/// iniciales de su tablero y confirma.
///
/// Todo lo que se muestra sale de [sala] (el servidor guarda el borrador, así
/// que una reconexión lo recupera). Lo único local es el número elegido para
/// colocar.
class VistaPreparacion extends StatefulWidget {
  const VistaPreparacion({
    super.key,
    required this.cliente,
    required this.sala,
  });

  final ClienteMultijugador cliente;
  final EstadoSala sala;

  @override
  State<VistaPreparacion> createState() => _VistaPreparacionState();
}

class _VistaPreparacionState extends State<VistaPreparacion> {
  int? _seleccion;
  Timer? _reloj;

  EstadoSala get _sala => widget.sala;
  ClienteMultijugador get _cliente => widget.cliente;

  List<int> get _iniciales => _sala.mapaOficial.indicesIniciales;
  bool get _participa => _sala.miJugador?.participa ?? false;
  bool get _confirmada => _sala.miJugador?.estado == EstadoJugador.listo;
  bool get _puedoEditar => _participa && !_confirmada && !_cliente.esperando;
  int get _colocados => 6 - _sala.numerosPorColocar.length;

  @override
  void initState() {
    super.initState();
    // Refresca el plazo de reconexión de los demás cada segundo.
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  int? _restante(int? base) {
    if (base == null) return null;
    final pasado = _cliente.desdeUltimoEstado.inSeconds;
    return base > pasado ? base - pasado : 0;
  }

  void _elegirNumero(int n) {
    if (!_puedoEditar) return;
    setState(() => _seleccion = _seleccion == n ? null : n);
  }

  void _tocarPosicion(int indice) {
    if (!_puedoEditar) return;
    final actual = _sala.tablero[indice];
    if (actual != null) {
      // Retirar el número para devolverlo a los disponibles.
      _cliente.quitarInicial(indice);
      return;
    }
    final n = _seleccion;
    if (n == null) return;
    if (_cliente.colocarInicial(indice, n)) setState(() => _seleccion = null);
  }

  Future<void> _rendirse() async {
    final ok = await confirmar(
      context,
      titulo: '¿Rendirte?',
      texto: 'Perderás la partida, aunque podrás seguir mirándola.',
      textoConfirmar: 'Rendirme',
    );
    if (ok && mounted) _cliente.conceder();
  }

  String _textoEstado() {
    if (!_participa) return 'Ya no participas. Puedes seguir mirando.';
    if (_confirmada) return 'Esperando a los demás jugadores';
    if (_colocados == 6) return 'Todo colocado. Confirma tu distribución.';
    final n = _seleccion;
    if (n != null) return 'Toca una posición inicial vacía para poner el $n.';
    return 'Elige un número y toca una posición con estrella.';
  }

  Widget _encabezado(int puntos) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            key: const Key('boton_volver'),
            tooltip: 'Salir de la partida',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          const Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'BRILLIANT',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
            ),
          ),
          const Spacer(),
          KeyedSubtree(
            key: const Key('puntos_provisionales'),
            child: Pastilla(
              icono: Icons.diamond_rounded,
              texto: _confirmada ? '$puntos pts' : '$puntos pts (provisional)',
              destacado: true,
            ),
          ),
          PopupMenuButton<String>(
            key: const Key('menu_partida'),
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            onSelected: (_) => _rendirse(),
            itemBuilder: (_) => [
              if (_participa)
                const PopupMenuItem(
                  key: Key('menu_rendirse'),
                  value: 'rendirse',
                  child: Text('Rendirme'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _jugadores() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9),
      child: Row(
        children: [
          for (final j in _sala.jugadores)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _FichaPreparacion(
                  key: Key('jugador_${j.id}'),
                  jugador: j,
                  esYo: j.id == _sala.yo,
                  segundosGracia: _restante(j.graciaRestante),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _panelInferior() {
    final compacto = MediaQuery.sizeOf(context).height < 700;
    final vertical = compacto ? 8.0 : 14.0;
    final tam = compacto ? 44.0 : 52.0;
    final pendientes = _sala.numerosPorColocar;
    final faltan = [
      for (final j in _sala.jugadores)
        if (j.estado == EstadoJugador.preparando) j.nombre,
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, vertical, 16, compacto ? 10 : 16),
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
            _textoEstado(),
            key: const Key('texto_estado'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Números colocados: $_colocados/6',
            key: const Key('progreso_numeros'),
            style: const TextStyle(color: Tema.dorado, fontSize: 13),
          ),
          SizedBox(height: vertical),
          if (_confirmada)
            Text(
              faltan.isEmpty
                  ? 'Todos listos…'
                  : 'Faltan por confirmar: ${faltan.join(', ')}',
              key: const Key('faltan_por_confirmar'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            )
          else
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final n in numerosIniciales)
                  SizedBox(
                    width: tam,
                    height: tam,
                    child: FilledButton(
                      key: Key('numero_$n'),
                      onPressed: _puedoEditar && pendientes.contains(n)
                          ? () => _elegirNumero(n)
                          : null,
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: _seleccion == n
                            ? Tema.dorado
                            : Colors.white,
                        foregroundColor: Tema.tinta,
                        disabledBackgroundColor: Colors.white12,
                        disabledForegroundColor: Colors.white30,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: _seleccion == n
                                ? Colors.white
                                : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Text(
                        '$n',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          if (!_confirmada && _participa) ...[
            SizedBox(height: vertical),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('boton_confirmar_distribucion'),
                onPressed: _colocados == 6 && _puedoEditar
                    ? _cliente.confirmarDistribucion
                    : null,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Confirmar distribución'),
                style: FilledButton.styleFrom(
                  backgroundColor: Tema.dorado,
                  foregroundColor: Tema.tinta,
                  padding: EdgeInsets.symmetric(vertical: compacto ? 10 : 14),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctl = _sala.crearControlador();
    final matriz = ctl.matriz;
    final posiciones = _iniciales;
    final editando = _puedoEditar;

    // Números que ya no están pendientes dejan de poder estar elegidos.
    if (_seleccion != null && !_sala.numerosPorColocar.contains(_seleccion)) {
      _seleccion = null;
    }

    return Column(
      children: [
        _encabezado(ctl.puntuacionTotal),
        _jugadores(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: TableroGemas(
              celdas: [
                for (var i = 0; i < matriz.length; i++)
                  CeldaGema(
                    key: posiciones.contains(i)
                        ? Key('inicial_${posiciones.indexOf(i)}')
                        : Key('celda_$i'),
                    region: matriz[i].region,
                    valor: matriz[i].valor,
                    esInicial: matriz[i].esInicial,
                    // Con un número elegido se iluminan las posiciones libres.
                    esDestino:
                        editando &&
                        _seleccion != null &&
                        matriz[i].esInicial &&
                        matriz[i].valor == null,
                    onTap: matriz[i].esInicial && editando
                        ? () => _tocarPosicion(i)
                        : null,
                  ),
              ],
            ),
          ),
        ),
        _panelInferior(),
      ],
    );
  }
}

class _FichaPreparacion extends StatelessWidget {
  const _FichaPreparacion({
    super.key,
    required this.jugador,
    required this.esYo,
    required this.segundosGracia,
  });

  final JugadorSala jugador;
  final bool esYo;
  final int? segundosGracia;

  @override
  Widget build(BuildContext context) {
    final String estado;
    Color color = Colors.white60;
    switch (jugador.estado) {
      case EstadoJugador.preparando:
        estado = 'Colocando números';
      case EstadoJugador.listo:
        estado = 'Listo';
        color = Colors.greenAccent;
      case EstadoJugador.concedio:
        estado = 'Rendido';
      case EstadoJugador.abandono:
        estado = 'Abandonó';
      case EstadoJugador.jugando:
      case EstadoJugador.terminado:
        estado = '';
    }
    // La desconexión temporal se suma al estado, sin sustituirlo.
    final sinConexion = jugador.participa && !jugador.conectado;
    final texto = sinConexion
        ? '$estado · Sin conexión${segundosGracia == null ? '' : ' ${segundosGracia}s'}'
        : estado;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Opacity(
        opacity: jugador.participa ? 1 : 0.5,
        child: Column(
          children: [
            Text(
              esYo ? 'Tú' : jugador.nombre,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(
              height: 28,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  texto,
                  key: Key('estado_${jugador.id}'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: sinConexion ? Colors.redAccent : color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
