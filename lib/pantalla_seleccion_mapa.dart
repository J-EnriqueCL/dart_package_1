import 'dart:math';

import 'package:flutter/material.dart';

import 'auth/cliente_auth.dart';
import 'auth/pantalla_acceso.dart';
import 'dart_package_1.dart';
import 'pantalla_numeros_iniciales.dart';
import 'tema.dart';

class PantallaSeleccionMapa extends StatelessWidget {
  const PantallaSeleccionMapa({super.key, this.azar, this.auth});

  /// Fuente de azar que se pasa a la partida; si es null se usa `Random()`.
  final Random? azar;

  /// Sesión actual; si es null no se muestra el menú de cuenta.
  final ClienteAuth? auth;

  Future<void> _borrarCuenta(BuildContext context, ClienteAuth auth) async {
    final mensajes = ScaffoldMessenger.of(context);
    if (await confirmarBorrarCuenta(context, auth)) {
      mensajes.showSnackBar(const SnackBar(content: Text('Cuenta borrada')));
    }
  }

  void _elegir(BuildContext context, MapaOficial mapa) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PantallaNumerosIniciales(mapa: mapa, azar: azar),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = this.auth;
    return Scaffold(
      appBar: auth == null
          ? null
          : AppBar(
              backgroundColor: Colors.transparent,
              actions: [
                PopupMenuButton<String>(
                  key: const Key('menu_cuenta'),
                  icon: const Icon(Icons.account_circle_outlined),
                  tooltip: auth.correo,
                  onSelected: (v) => v == 'salir'
                      ? auth.cerrarSesion()
                      : _borrarCuenta(context, auth),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      enabled: false,
                      child: Text(auth.correo ?? ''),
                    ),
                    const PopupMenuItem(
                      key: Key('menu_salir'),
                      value: 'salir',
                      child: Text('Cerrar sesión'),
                    ),
                    const PopupMenuItem(
                      key: Key('menu_borrar'),
                      value: 'borrar',
                      child: Text('Borrar cuenta'),
                    ),
                  ],
                ),
              ],
            ),
      extendBodyBehindAppBar: true,
      body: FondoJuego(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 14, bottom: 2),
                    child: Text(
                      'BRILLIANT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                  const Text(
                    'Elige un mapa para jugar',
                    style: TextStyle(color: Colors.white70),
                  ),
                  Expanded(
                    child: GridView.count(
                      padding: const EdgeInsets.all(16),
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      children: [
                        for (var i = 0; i < mapasOficiales.length; i++)
                          _TarjetaMapa(
                            key: Key('mapa_$i'),
                            mapa: mapasOficiales[i],
                            onTap: () => _elegir(context, mapasOficiales[i]),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TarjetaMapa extends StatelessWidget {
  const _TarjetaMapa({super.key, required this.mapa, required this.onTap});

  final MapaOficial mapa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final celdas = mapa.crearTablero();

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Tema.panel,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: GridView.count(
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 7,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                  children: [
                    for (final celda in celdas)
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: Tema.color(celda.region),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              mapa.nombre,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
