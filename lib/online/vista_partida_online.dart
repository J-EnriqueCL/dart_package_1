import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../dart_package_1.dart';
import '../tema.dart';
import '../widgets/celda_gema.dart';
import '../widgets/confirmar.dart';
import '../widgets/dado.dart';
import 'cliente_multijugador.dart';

/// Partida en curso (o ya terminada) vista por un jugador.
///
/// El tablero y los dados son los del servidor; aquí solo se elige el ancla
/// (algo local) y se piden acciones. Todo lo que se muestra sale de [sala].
class VistaPartidaOnline extends StatefulWidget {
  const VistaPartidaOnline({
    super.key,
    required this.cliente,
    required this.sala,
  });

  final ClienteMultijugador cliente;
  final EstadoSala sala;

  @override
  State<VistaPartidaOnline> createState() => _VistaPartidaOnlineState();
}

class _VistaPartidaOnlineState extends State<VistaPartidaOnline> {
  late ControladorPartida _ctl;
  int? _ancla;
  String? _clave;
  Timer? _reloj;

  EstadoSala get _sala => widget.sala;
  ClienteMultijugador get _cliente => widget.cliente;

  @override
  void initState() {
    super.initState();
    _preparar();
    // Refresca los cuentas atrás (turno y plazo de reconexión) cada segundo.
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(VistaPartidaOnline anterior) {
    super.didUpdateWidget(anterior);
    if (!identical(anterior.sala, widget.sala)) _preparar();
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  void _preparar() {
    _ctl = _sala.crearControlador();
    // La elección de ancla solo vale para esta tirada.
    final clave = '${_sala.turno}|${_sala.dados}|${_sala.turnoDe}';
    if (clave != _clave) {
      _ancla = null;
      _clave = clave;
    }
  }

  int? _restante(int? base) {
    if (base == null) return null;
    // El servidor manda los segundos que quedan; aquí solo se descuenta lo que
    // pasó desde que llegaron, con un reloj que no depende de la hora del
    // dispositivo.
    return max(0, base - _cliente.desdeUltimoEstado.inSeconds);
  }

  bool get _activo => _sala.miJugador?.activo ?? false;
  bool get _jugando => _sala.fase == FaseSala.jugando;
  bool get _puedoActuar => _sala.esMiTurno && _activo && !_cliente.esperando;

  List<bool> get _movimientosPorDado {
    final d = _sala.dados;
    if (d == null) return [false, false];
    return [
      for (var i = 0; i < 2; i++)
        _ctl.destinosPosibles(ancla: d[i], colocar: d[1 - i]).isNotEmpty,
    ];
  }

  Set<int> get _destinos {
    final d = _sala.dados;
    final a = _ancla;
    if (d == null || a == null || !_sala.esMiTurno) return {};
    return _ctl.destinosPosibles(ancla: d[a], colocar: d[1 - a]);
  }

  void _tocarDado(int posicion) {
    if (!_puedoActuar || _sala.dados == null) return;
    setState(() => _ancla = _ancla == posicion ? null : posicion);
  }

  void _colocar(int indice) {
    final a = _ancla;
    if (a == null || !_puedoActuar) return;
    _cliente.colocar(indice, a);
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

  void _mostrarReglas() {
    final regiones = {
      for (final c in _sala.mapaOficial.crearTablero()) c.region,
    }.toList()..sort((a, b) => a.index.compareTo(b.index));

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tema.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          shrinkWrap: true,
          children: [
            const Text(
              'Reglas de las áreas',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Quien completa un área se lleva sus puntos.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            for (final r in regiones)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Tema.color(r),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                title: Text(
                  r.nombre,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  r.regla,
                  style: const TextStyle(color: Colors.white60),
                ),
                trailing: Text(
                  '+${ControladorPartida.puntosPorRegion[r]}',
                  style: const TextStyle(
                    color: Tema.dorado,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------

  Widget _encabezado() {
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
          Pastilla(icono: Icons.flag_rounded, texto: 'Turno ${_sala.turno}'),
          PopupMenuButton<String>(
            key: const Key('menu_partida'),
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
            onSelected: (v) => v == 'reglas' ? _mostrarReglas() : _rendirse(),
            itemBuilder: (_) => [
              const PopupMenuItem(
                key: Key('menu_reglas'),
                value: 'reglas',
                child: Text('Reglas de las áreas'),
              ),
              if (_jugando && _activo)
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
                child: _FichaJugador(
                  key: Key('jugador_${j.id}'),
                  jugador: j,
                  esYo: j.id == _sala.yo,
                  enTurno: _jugando && _sala.turnoDe == j.id,
                  segundosTurno: _restante(_sala.segundosTurno),
                  segundosGracia: _restante(j.graciaRestante),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _textoEstado(bool hayMovimientos, Set<int> destinos) {
    if (!_activo) {
      return 'Ya no participas. Puedes seguir mirando la partida.';
    }
    if (!_sala.esMiTurno) {
      final quien = _sala.jugador(_sala.turnoDe ?? '')?.nombre ?? '';
      return 'Turno de $quien.';
    }
    final d = _sala.dados;
    if (d == null) return 'Es tu turno. Tira los dados.';
    final a = _ancla;
    if (a == null) {
      return hayMovimientos
          ? 'Salieron ${d[0]} y ${d[1]}. Toca un dado para elegirlo como ancla.'
          : 'Salieron ${d[0]} y ${d[1]}, pero no hay movimientos. Pasa el turno.';
    }
    return destinos.isEmpty
        ? 'No hay lugar para el ${d[1 - a]} junto a un ${d[a]}. Elige el otro dado.'
        : 'Ancla ${d[a]}. Coloca el ${d[1 - a]} en una casilla iluminada.';
  }

  Widget _panelInferior(bool hayMovimientos, Set<int> destinos) {
    final dados = _sala.dados;
    final movimientos = _movimientosPorDado;
    final miTurno = _sala.esMiTurno && _activo;

    RolDado rol(int posicion) {
      if (_ancla == null || !miTurno) return RolDado.ninguno;
      return _ancla == posicion ? RolDado.ancla : RolDado.aColocar;
    }

    // En pantallas bajas el panel se compacta para que el tablero conserve
    // casillas de tamaño táctil razonable.
    final compacto = MediaQuery.sizeOf(context).height < 700;
    final vertical = compacto ? 8.0 : 14.0;

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
            _textoEstado(hayMovimientos, destinos),
            key: const Key('texto_estado'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (_sala.mensaje.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                _sala.mensaje,
                key: const Key('texto_ultimo'),
                textAlign: TextAlign.center,
                maxLines: compacto ? 1 : null,
                overflow: compacto ? TextOverflow.ellipsis : null,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ),
          SizedBox(height: vertical),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var posicion = 0; posicion < 2; posicion++) ...[
                if (posicion == 1) const SizedBox(width: 18),
                Dado(
                  tamano: compacto ? 58 : 92,
                  key: Key('dado_$posicion'),
                  valor: dados?[posicion],
                  rol: rol(posicion),
                  activo: dados == null || movimientos[posicion] || !miTurno,
                  onTap: miTurno && dados != null
                      ? () => _tocarDado(posicion)
                      : null,
                ),
              ],
            ],
          ),
          SizedBox(height: vertical),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('boton_tirar_dados'),
                  onPressed: _puedoActuar && dados == null
                      ? _cliente.tirar
                      : null,
                  icon: const Icon(Icons.casino_rounded),
                  label: const Text('Tirar dados'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Tema.dorado,
                    foregroundColor: Tema.tinta,
                    padding: EdgeInsets.symmetric(vertical: compacto ? 10 : 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('boton_pasar_turno'),
                  // El servidor solo deja pasar si no hay movimientos.
                  onPressed: _puedoActuar && dados != null && !hayMovimientos
                      ? _cliente.pasar
                      : null,
                  icon: const Icon(Icons.skip_next_rounded),
                  label: const Text('Pasar turno'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: compacto ? 10 : 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panelResultado() {
    final r = _sala.resultado;
    final yo = _sala.miJugador;
    final ganadores = r?.ganadores ?? const <String>[];

    String titulo;
    if (r == null) {
      titulo = 'Partida terminada';
    } else if (ganadores.contains(_sala.yo)) {
      titulo = ganadores.length > 1 ? '¡Empate!' : '¡Ganaste!';
    } else if (yo?.estado == EstadoJugador.concedio) {
      titulo = 'Te rendiste';
    } else if (yo?.estado == EstadoJugador.abandono) {
      titulo = 'Perdiste por abandono';
    } else {
      titulo = 'Perdiste';
    }

    final ranking = [..._sala.jugadores]
      ..sort((a, b) {
        if (a.activo != b.activo) return a.activo ? -1 : 1;
        return b.puntos.compareTo(a.puntos);
      });

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: const BoxDecoration(
        color: Tema.panel,
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            titulo,
            key: const Key('titulo_resultado'),
            style: const TextStyle(
              color: Tema.dorado,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _sala.mensaje,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 10),
          for (final j in ranking)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    ganadores.contains(j.id)
                        ? Icons.emoji_events_rounded
                        : Icons.person_rounded,
                    size: 18,
                    color: ganadores.contains(j.id)
                        ? Tema.dorado
                        : Colors.white54,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      j.id == _sala.yo ? '${j.nombre} (tú)' : j.nombre,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: j.activo ? Colors.white : Colors.white54,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (j.estado == EstadoJugador.concedio)
                    const Text(
                      'se rindió  ',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  if (j.estado == EstadoJugador.abandono)
                    const Text(
                      'abandonó  ',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  Text(
                    '${j.puntos} pts',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          if (_sala.soyAnfitrion)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('boton_volver_lobby'),
                onPressed: _cliente.esperando ? null : _cliente.volverAlLobby,
                icon: const Icon(Icons.replay_rounded),
                label: const Text('Volver al lobby'),
                style: FilledButton.styleFrom(
                  backgroundColor: Tema.dorado,
                  foregroundColor: Tema.tinta,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            )
          else
            const Text(
              'Esperando a que el anfitrión abra otra partida…',
              key: Key('esperando_anfitrion'),
              style: TextStyle(color: Colors.white60),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('boton_salir'),
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Salir'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final destinos = _destinos;
    final hayMovimientos = _movimientosPorDado.contains(true);
    final matriz = _ctl.matriz;
    final d = _sala.dados;
    final a = _ancla;
    final numeroAncla = d != null && a != null ? d[a] : null;
    final porColocar = d != null && a != null ? d[1 - a] : null;

    return Column(
      children: [
        _encabezado(),
        _jugadores(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: TableroGemas(
              celdas: [
                for (var i = 0; i < matriz.length; i++)
                  CeldaGema(
                    key: Key('celda_$i'),
                    region: matriz[i].region,
                    valor: matriz[i].valor,
                    vistaPrevia: porColocar,
                    esInicial: matriz[i].esInicial,
                    esDestino: destinos.contains(i),
                    esAncla:
                        numeroAncla != null &&
                        _sala.esMiTurno &&
                        matriz[i].valor == numeroAncla,
                    completada: _ctl.areaCompleta(_ctl.areaDeCelda(i)),
                    onTap: destinos.contains(i) ? () => _colocar(i) : null,
                  ),
              ],
            ),
          ),
        ),
        if (_jugando)
          _panelInferior(hayMovimientos, destinos)
        else
          _panelResultado(),
      ],
    );
  }
}

class _FichaJugador extends StatelessWidget {
  const _FichaJugador({
    super.key,
    required this.jugador,
    required this.esYo,
    required this.enTurno,
    required this.segundosTurno,
    required this.segundosGracia,
  });

  final JugadorSala jugador;
  final bool esYo;
  final bool enTurno;
  final int? segundosTurno;
  final int? segundosGracia;

  @override
  Widget build(BuildContext context) {
    final fuera = !jugador.activo;
    String estado = '';
    Color colorEstado = Colors.white60;
    if (jugador.estado == EstadoJugador.concedio) {
      estado = 'Se rindió';
    } else if (jugador.estado == EstadoJugador.abandono) {
      estado = 'Abandonó';
    } else if (!jugador.conectado) {
      estado = segundosGracia == null
          ? 'Sin conexión'
          : 'Sin conexión ${segundosGracia}s';
      colorEstado = Colors.redAccent;
    } else if (enTurno) {
      estado = segundosTurno == null ? 'Su turno' : 'Turno · ${segundosTurno}s';
      colorEstado = Tema.dorado;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: enTurno ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enTurno ? Tema.dorado : Colors.transparent,
          width: 2,
        ),
      ),
      child: Opacity(
        opacity: fuera ? 0.5 : 1,
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
            Text(
              '${jugador.puntos}',
              key: Key('puntos_${jugador.id}'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(
              height: 14,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  estado,
                  key: Key('estado_${jugador.id}'),
                  style: TextStyle(color: colorEstado, fontSize: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
