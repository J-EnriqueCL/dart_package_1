import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';

import 'almacen.dart';
import 'servicio_auth.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};

Response _resp(int codigo, Map<String, Object?> cuerpo) =>
    Response(codigo, body: jsonEncode(cuerpo), headers: _json);

Future<Map<String, Object?>> _leer(Request req) async {
  final texto = await req.readAsString();
  try {
    final d = jsonDecode(texto);
    if (d is Map) return d.cast<String, Object?>();
  } catch (_) {}
  throw ErrorAuth(400, 'Cuerpo JSON inválido.');
}

String _campo(Map<String, Object?> d, String k) {
  final v = d[k];
  if (v is! String) throw ErrorAuth(400, 'Falta el campo "$k".');
  return v;
}

Handler crearApi(ServicioAuth auth, {String? origenPermitido}) {
  final r = Router();

  r.post('/registro', (Request req) async {
    final d = await _leer(req);
    final u = await auth.registrar(
      _campo(d, 'correo'),
      _campo(d, 'contrasena'),
    );
    return _resp(201, {'id': u.id, 'correo': u.correo});
  });

  r.post('/login', (Request req) async {
    final d = await _leer(req);
    final token = auth.iniciarSesion(
      _campo(d, 'correo'),
      _campo(d, 'contrasena'),
    );
    return _resp(200, {'token': token});
  });

  r.get('/yo', (Request req) {
    final u = _autenticar(req, auth);
    return _resp(200, {'id': u.id, 'correo': u.correo});
  });

  r.delete('/cuenta', (Request req) async {
    final u = _autenticar(req, auth);
    final d = await _leer(req);
    await auth.borrarCuenta(u, _campo(d, 'contrasena'));
    return _resp(200, {'ok': true});
  });

  return const Pipeline()
      .addMiddleware(
        corsHeaders(
          headers: {
            ACCESS_CONTROL_ALLOW_ORIGIN: origenPermitido ?? '*',
            ACCESS_CONTROL_ALLOW_HEADERS: 'content-type, authorization',
            ACCESS_CONTROL_ALLOW_METHODS: 'GET, POST, DELETE, OPTIONS',
          },
        ),
      )
      .addMiddleware(_manejarErrores())
      .addMiddleware(_limitarCuerpo(10 * 1024))
      .addHandler(r.call);
}

Usuario _autenticar(Request req, ServicioAuth auth) {
  final h = req.headers['authorization'];
  if (h == null || !h.startsWith('Bearer ')) {
    throw ErrorAuth(401, 'No autenticado.');
  }
  final u = auth.usuarioDeToken(h.substring(7));
  if (u == null) throw ErrorAuth(401, 'Sesión inválida o expirada.');
  return u;
}

Middleware _limitarCuerpo(int max) =>
    (inner) => (req) {
      final len = req.contentLength;
      if (len != null && len > max) {
        return _resp(413, {'error': 'Cuerpo demasiado grande.'});
      }
      return inner(req);
    };

Middleware _manejarErrores() =>
    (inner) => (req) async {
      try {
        final resp = await inner(req);
        return resp.change(
          headers: {
            'cache-control': 'no-store',
            'x-content-type-options': 'nosniff',
          },
        );
      } on ErrorAuth catch (e) {
        return _resp(e.codigo, {'error': e.mensaje});
      } catch (e, st) {
        print('Error interno: $e\n$st');
        return _resp(500, {'error': 'Error interno.'});
      }
    };
