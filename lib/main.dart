import 'package:flutter/material.dart';

import 'auth/cliente_auth.dart';
import 'auth/pantalla_acceso.dart';
import 'pantalla_seleccion_mapa.dart';

void main() {
  runApp(AplicacionBrilliant(auth: ClienteAuth()));
}

class AplicacionBrilliant extends StatelessWidget {
  /// Si [auth] es null no se pide cuenta y se entra directo al juego.
  const AplicacionBrilliant({super.key, this.auth});

  final ClienteAuth? auth;

  @override
  Widget build(BuildContext context) {
    final auth = this.auth;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Brilliant',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.deepPurple,
      ),
      home: auth == null
          ? const PantallaSeleccionMapa()
          : ListenableBuilder(
              listenable: auth,
              builder: (context, _) => auth.haySesion
                  ? PantallaSeleccionMapa(auth: auth)
                  : PantallaAcceso(auth: auth),
            ),
    );
  }
}
