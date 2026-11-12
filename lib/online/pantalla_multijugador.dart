import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/cliente_auth.dart';
import '../dart_package_1.dart';
import '../tema.dart';
import '../widgets/confirmar.dart';
import 'cliente_multijugador.dart';
import 'vista_lobby.dart';
import 'vista_partida_online.dart';
import 'vista_preparacion.dart';

/// Pantalla única del modo en línea: según el estado muestra la entrada (crear
/// o unirse), el lobby o la partida. Al ser una sola ruta, los cortes de
/// conexión, las expulsiones o el final de partida solo cambian su contenido.
class PantallaMultijugador extends StatefulWidget {
  const PantallaMultijugador({super.key, required this.auth, this.cliente});

  final ClienteAuth auth;

  /// Solo para pruebas: cliente ya preparado (se conecta aquí; quien lo pasa
  /// es quien lo desecha).
  final ClienteMultijugador? cliente;

  @override
  State<PantallaMultijugador> createState() => _PantallaMultijugadorState();
}

class _PantallaMultijugadorState extends State<PantallaMultijugador>
    with WidgetsBindingObserver {
  late final ClienteMultijugador _cliente;
  late final bool _propio;
  late final Uri _servidorAlAbrir;
  StreamSubscription<String>? _avisos;

  @override
  void initState() {
    super.initState();
    _propio = widget.cliente == null;
    _servidorAlAbrir = widget.auth.urlBase;
    widget.auth.addListener(_alCambiarAuth);
    _cliente =
        widget.cliente ??
        ClienteMultijugador(
          url: urlWebSocket(widget.auth.urlBase),
          token: () => widget.auth.token,
        );
    _avisos = _cliente.avisos.listen(_mostrarAviso);
    WidgetsBinding.instance.addObserver(this);
    _cliente.conectar();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _cliente.cicloDeVida(state);
  }

  /// Si se cambia de servidor con esta pantalla abierta, se cierra el socket
  /// del servidor anterior (sin más reconexiones) y se vuelve al acceso.
  void _alCambiarAuth() {
    if (widget.auth.urlBase == _servidorAlAbrir) return;
    _cliente.cerrar();
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  void dispose() {
    widget.auth.removeListener(_alCambiarAuth);
    WidgetsBinding.instance.removeObserver(this);
    _avisos?.cancel();
    // Al irse avisa al servidor (en partida cuenta como rendición).
    if (_propio) _cliente.dispose();
    super.dispose();
  }

  void _mostrarAviso(String texto) {
    if (!mounted) return;
    final mensajes = ScaffoldMessenger.of(context);
    mensajes
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  /// Hay una partida (o su preparación) en marcha en la que el jugador aún
  /// participa: salir cuenta como rendirse.
  bool get _jugandoActivo {
    final s = _cliente.sala;
    return s != null &&
        (s.fase == FaseSala.jugando || s.fase == FaseSala.preparacion) &&
        (s.miJugador?.participa ?? false);
  }

  Future<void> _alIntentarSalir(bool didPop) async {
    if (didPop) return;
    final navegador = Navigator.of(context);
    final salir = await confirmar(
      context,
      titulo: '¿Rendirte y salir?',
      texto: 'Si sales ahora, pierdes la partida.',
      textoConfirmar: 'Rendirme y salir',
    );
    if (salir && mounted) navegador.pop();
  }

  void _volverAAcceso() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    widget.auth.cerrarSesion();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _cliente,
      builder: (context, _) {
        return PopScope(
          canPop: !_jugandoActivo,
          onPopInvokedWithResult: (didPop, _) => _alIntentarSalir(didPop),
          child: Scaffold(
            body: FondoJuego(
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      children: [
                        if (_cliente.conexion == EstadoConexion.reconectando)
                          _BandaConexion(intento: _cliente.intento),
                        Expanded(child: _cuerpo()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _cuerpo() {
    final fatal = _cliente.errorFatal;
    if (fatal != null) {
      return _VistaFatal(
        mensaje: fatal,
        sesionInvalida: _cliente.sesionInvalida,
        onReintentar: _cliente.conectar,
        onSalir: () => Navigator.of(context).maybePop(),
        onVolverAAcceso: _volverAAcceso,
      );
    }
    final sala = _cliente.sala;
    if (sala == null) {
      if (!_cliente.autenticado) return const _VistaConectando();
      return _VistaEntrada(cliente: _cliente);
    }
    if (sala.fase == FaseSala.lobby) {
      return VistaLobby(cliente: _cliente, sala: sala);
    }
    if (sala.fase == FaseSala.preparacion) {
      return VistaPreparacion(cliente: _cliente, sala: sala);
    }
    return VistaPartidaOnline(cliente: _cliente, sala: sala);
  }
}

class _BandaConexion extends StatelessWidget {
  const _BandaConexion({required this.intento});
  final int intento;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('banda_reconectando'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.orange.shade800,
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sin conexión. Reconectando… (intento $intento)',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VistaConectando extends StatelessWidget {
  const _VistaConectando();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: Tema.dorado),
          SizedBox(height: 16),
          Text('Conectando…', style: TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _VistaFatal extends StatelessWidget {
  const _VistaFatal({
    required this.mensaje,
    required this.sesionInvalida,
    required this.onReintentar,
    required this.onSalir,
    required this.onVolverAAcceso,
  });

  final String mensaje;
  final bool sesionInvalida;
  final VoidCallback onReintentar;
  final VoidCallback onSalir;
  final VoidCallback onVolverAAcceso;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              color: Colors.white54,
              size: 56,
            ),
            const SizedBox(height: 16),
            Text(
              mensaje,
              key: const Key('error_fatal'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 24),
            if (sesionInvalida)
              FilledButton(
                key: const Key('boton_volver_acceso'),
                onPressed: onVolverAAcceso,
                child: const Text('Iniciar sesión de nuevo'),
              )
            else
              FilledButton(
                key: const Key('boton_reintentar'),
                onPressed: onReintentar,
                child: const Text('Reintentar'),
              ),
            const SizedBox(height: 8),
            TextButton(
              key: const Key('boton_salir_fatal'),
              onPressed: onSalir,
              child: const Text('Volver al menú'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VistaEntrada extends StatefulWidget {
  const _VistaEntrada({required this.cliente});
  final ClienteMultijugador cliente;

  @override
  State<_VistaEntrada> createState() => _VistaEntradaState();
}

class _VistaEntradaState extends State<_VistaEntrada> {
  final _codigo = TextEditingController();

  @override
  void dispose() {
    _codigo.dispose();
    super.dispose();
  }

  void _unirse() {
    final c = _codigo.text.trim();
    if (c.isEmpty) return;
    widget.cliente.unirse(c);
  }

  @override
  Widget build(BuildContext context) {
    final libre = !widget.cliente.esperando;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            tooltip: 'Volver',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        const Center(
          child: Text(
            'JUGAR EN LÍNEA',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 3,
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Juega por turnos contra tus amigos, cada uno en su propio tablero.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          key: const Key('boton_crear_sala'),
          onPressed: libre ? () => widget.cliente.crearSala(0) : null,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Crear sala'),
          style: FilledButton.styleFrom(
            backgroundColor: Tema.dorado,
            foregroundColor: Tema.tinta,
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          '¿Te invitaron? Escribe el código de la sala:',
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('campo_codigo'),
          controller: _codigo,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          maxLength: 12,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (_) => _unirse(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: 6,
          ),
          decoration: const InputDecoration(
            counterText: '',
            hintText: 'ABC123',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('boton_unirse'),
          onPressed: libre ? _unirse : null,
          icon: const Icon(Icons.login_rounded),
          label: const Text('Unirme'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }
}
