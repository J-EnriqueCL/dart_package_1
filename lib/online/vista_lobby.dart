import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../dart_package_1.dart';
import '../tema.dart';
import 'cliente_multijugador.dart';

/// Sala de espera: código de invitación, mapa y jugadores.
class VistaLobby extends StatelessWidget {
  const VistaLobby({super.key, required this.cliente, required this.sala});

  final ClienteMultijugador cliente;
  final EstadoSala sala;

  Future<void> _copiar(BuildContext context) async {
    final mensajes = ScaffoldMessenger.of(context);
    await Clipboard.setData(
      ClipboardData(
        text: 'Únete a mi partida de Brilliant con el código ${sala.codigo}',
      ),
    );
    mensajes
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Invitación copiada al portapapeles')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final libre = !cliente.esperando;
    final todosConectados = sala.jugadores.every((j) => j.conectado);
    final suficientes = sala.jugadores.length >= 2;
    final puedeEmpezar =
        sala.soyAnfitrion && suficientes && todosConectados && libre;

    String? aviso;
    if (sala.soyAnfitrion) {
      if (!suficientes) {
        aviso = 'Hace falta al menos otro jugador. Comparte el código.';
      } else if (!todosConectados) {
        aviso = 'Esperando a que vuelvan los jugadores desconectados.';
      }
    } else {
      aviso = 'Esperando a que el anfitrión empiece la partida…';
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Center(
          child: Text(
            'SALA',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
            ),
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          key: const Key('tarjeta_codigo'),
          borderRadius: BorderRadius.circular(18),
          onTap: () => _copiar(context),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Tema.panel,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                const Text(
                  'Código de invitación',
                  style: TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Text(
                  sala.codigo,
                  key: const Key('codigo_sala'),
                  style: const TextStyle(
                    color: Tema.dorado,
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 8,
                  ),
                ),
                const SizedBox(height: 4),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.copy_rounded, size: 14, color: Colors.white54),
                    SizedBox(width: 6),
                    Text(
                      'Toca para copiar la invitación',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _Seccion('Mapa'),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              height: 96,
              child: _MiniMapa(mapa: mapasOficiales[sala.mapa]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: sala.soyAnfitrion
                  ? Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < mapasOficiales.length; i++)
                          ChoiceChip(
                            key: Key('mapa_$i'),
                            label: Text(mapasOficiales[i].nombre),
                            selected: sala.mapa == i,
                            onSelected: libre
                                ? (_) => cliente.elegirMapa(i)
                                : null,
                          ),
                      ],
                    )
                  : Text(
                      mapasOficiales[sala.mapa].nombre,
                      key: const Key('mapa_elegido'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _Seccion('Jugadores (${sala.jugadores.length}/${sala.maxJugadores})'),
        const SizedBox(height: 8),
        for (final j in sala.jugadores)
          _FilaJugador(
            key: Key('jugador_${j.id}'),
            jugador: j,
            esYo: j.id == sala.yo,
            esAnfitrion: j.id == sala.anfitrion,
            onExpulsar: sala.soyAnfitrion && j.id != sala.yo && libre
                ? () => cliente.expulsar(j.id)
                : null,
          ),
        const SizedBox(height: 16),
        if (aviso != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              aviso,
              key: const Key('aviso_lobby'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        if (sala.soyAnfitrion)
          FilledButton.icon(
            key: const Key('boton_empezar'),
            onPressed: puedeEmpezar ? cliente.empezar : null,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Empezar partida'),
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
        const SizedBox(height: 10),
        OutlinedButton.icon(
          key: const Key('boton_salir_sala'),
          onPressed: libre ? cliente.salirSala : null,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Salir de la sala'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto.toUpperCase(),
      style: const TextStyle(
        color: Colors.white60,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 2,
      ),
    );
  }
}

class _FilaJugador extends StatelessWidget {
  const _FilaJugador({
    super.key,
    required this.jugador,
    required this.esYo,
    required this.esAnfitrion,
    required this.onExpulsar,
  });

  final JugadorSala jugador;
  final bool esYo;
  final bool esAnfitrion;
  final VoidCallback? onExpulsar;

  @override
  Widget build(BuildContext context) {
    final gracia = jugador.graciaRestante;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.circle,
            size: 12,
            color: jugador.conectado ? Colors.greenAccent : Colors.redAccent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  esYo ? '${jugador.nombre} (tú)' : jugador.nombre,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (!jugador.conectado)
                  Text(
                    gracia == null
                        ? 'Desconectado'
                        : 'Desconectado · puede volver durante ${gracia}s',
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          if (esAnfitrion)
            const Tooltip(
              message: 'Anfitrión',
              child: Icon(Icons.star_rounded, color: Tema.dorado),
            ),
          if (onExpulsar != null)
            IconButton(
              key: Key('expulsar_${jugador.id}'),
              tooltip: 'Expulsar',
              onPressed: onExpulsar,
              icon: const Icon(Icons.person_remove_rounded),
              color: Colors.white70,
            ),
        ],
      ),
    );
  }
}

/// Vista en miniatura de los colores de un mapa.
class _MiniMapa extends StatelessWidget {
  const _MiniMapa({required this.mapa});
  final MapaOficial mapa;

  @override
  Widget build(BuildContext context) {
    final celdas = mapa.crearTablero();
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Tema.panel,
        borderRadius: BorderRadius.circular(12),
      ),
      child: GridView.count(
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 7,
        mainAxisSpacing: 1,
        crossAxisSpacing: 1,
        children: [
          for (final c in celdas)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Tema.color(c.region),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}
