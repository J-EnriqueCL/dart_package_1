import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'auth/cliente_auth.dart';
import 'auth/config_servidor.dart';
import 'auth/pantalla_acceso.dart';
import 'pantalla_seleccion_mapa.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // El tablero está pensado para pantalla vertical; en horizontal no cabe.
  SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Primero se lee la dirección guardada: guardada válida > --dart-define >
  // valor por defecto. Solo después se crean los clientes de red.
  final config = await ConfigServidor.cargar();
  runApp(AplicacionBrilliant(auth: ClienteAuth(config: config)));
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
