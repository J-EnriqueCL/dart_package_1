import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Dirección del servidor; se cambia con `--dart-define=URL_SERVIDOR=...`.
const urlServidorPorDefecto = String.fromEnvironment(
  'URL_SERVIDOR',
  defaultValue: 'http://localhost:8080',
);

class ErrorCliente implements Exception {
  ErrorCliente(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Habla con el servidor de autenticación y guarda la sesión actual.
///
/// El token vive solo en memoria: al cerrar la app hay que volver a entrar.
class ClienteAuth extends ChangeNotifier {
  ClienteAuth({http.Client? cliente, String? urlBase})
    : _http = cliente ?? http.Client(),
      _base = Uri.parse(urlBase ?? urlServidorPorDefecto);

  final http.Client _http;
  final Uri _base;
  String? _token;
  String? _correo;

  bool get haySesion => _token != null;
  String? get correo => _correo;

  Future<void> registrar(String correo, String contrasena) async {
    await _enviar('POST', '/registro', {
      'correo': correo,
      'contrasena': contrasena,
    });
  }

  Future<void> iniciarSesion(String correo, String contrasena) async {
    final r = await _enviar('POST', '/login', {
      'correo': correo,
      'contrasena': contrasena,
    });
    _token = r['token'] as String;
    _correo = correo.trim().toLowerCase();
    notifyListeners();
  }

  void cerrarSesion() {
    _token = null;
    _correo = null;
    notifyListeners();
  }

  Future<void> borrarCuenta(String contrasena) async {
    await _enviar('DELETE', '/cuenta', {
      'contrasena': contrasena,
    }, conToken: true);
    cerrarSesion();
  }

  Future<Map<String, Object?>> _enviar(
    String metodo,
    String ruta,
    Map<String, Object?> cuerpo, {
    bool conToken = false,
  }) async {
    final peticion = http.Request(metodo, _base.resolve(ruta))
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode(cuerpo);
    if (conToken) peticion.headers['authorization'] = 'Bearer $_token';

    http.Response resp;
    try {
      resp = await http.Response.fromStream(
        await _http.send(peticion).timeout(const Duration(seconds: 15)),
      );
    } on TimeoutException {
      throw ErrorCliente('El servidor tardó demasiado en responder.');
    } catch (_) {
      throw ErrorCliente('No se pudo conectar con el servidor.');
    }

    Map<String, Object?> datos = {};
    try {
      final d = jsonDecode(utf8.decode(resp.bodyBytes));
      if (d is Map) datos = d.cast<String, Object?>();
    } catch (_) {}

    if (resp.statusCode >= 200 && resp.statusCode < 300) return datos;
    if (resp.statusCode == 401 && conToken && datos['error'] is! String) {
      cerrarSesion();
    }
    throw ErrorCliente(
      datos['error'] as String? ?? 'Error inesperado (${resp.statusCode}).',
    );
  }
}
