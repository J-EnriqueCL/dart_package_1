import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:servidor_brilliant/servidor_brilliant.dart';
import 'package:shelf/shelf_io.dart' as io;

/// El secreto del JWT sale de JWT_SECRETO o se genera y guarda la primera vez.
String _secreto(String dir) {
  final env = Platform.environment['JWT_SECRETO'];
  if (env != null && env.length >= 32) return env;
  final f = File('$dir/secreto_jwt.txt');
  if (f.existsSync()) return f.readAsStringSync().trim();
  final r = Random.secure();
  final s = base64UrlEncode(List.generate(48, (_) => r.nextInt(256)));
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(s);
  return s;
}

Future<void> main() async {
  const dir = 'datos';
  final puerto = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final auth = ServicioAuth(
    almacen: AlmacenArchivo('$dir/usuarios.json'),
    secretoJwt: _secreto(dir),
  );
  final api = crearApi(
    auth,
    origenPermitido: Platform.environment['ORIGEN_PERMITIDO'],
  );
  final servidor = await io.serve(api, InternetAddress.loopbackIPv4, puerto);
  print(
    'Servidor escuchando en http://${servidor.address.host}:${servidor.port}',
  );
}
