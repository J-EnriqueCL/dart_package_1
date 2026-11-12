import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config_servidor.dart';

export 'config_servidor.dart' show urlServidorPorDefecto;

class ErrorCliente implements Exception {
  ErrorCliente(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Habla con el servidor de autenticación y guarda la sesión actual.
///
/// El token vive solo en memoria: al cerrar la app hay que volver a entrar.
///
/// La dirección del servidor sale de [config] (la guardada en la app o, si no
/// hay, la compilada con `--dart-define`); al cambiarla con [cambiarServidor]
/// se cierra la sesión y se descarta todo lo que dependía del servidor
/// anterior.
class ClienteAuth extends ChangeNotifier {
  ClienteAuth({http.Client? cliente, String? urlBase, this.config})
    : _http = cliente ?? http.Client(),
      _base = urlBase != null
          ? validarUrlServidor(urlBase)
          : (config?.url ?? validarUrlServidor(urlServidorPorDefecto));

  final http.Client _http;
  Uri _base;
  String? _token;
  String? _correo;

  /// Configuración persistente del servidor (null: no se puede cambiar desde
  /// la app, como en algunas pruebas).
  final ConfigServidor? config;

  /// Sube al cambiar de servidor o cerrar sesión: las respuestas que llegan
  /// de una petición anterior se descartan en vez de aplicarse.
  int _generacion = 0;

  bool get haySesion => _token != null;
  String? get correo => _correo;

  /// JWT de la sesión actual (null sin sesión); lo usa el cliente multijugador.
  String? get token => _token;

  /// Dirección base del servidor.
  Uri get urlBase => _base;

  /// Cambia de servidor. Cierra la sesión (el token del servidor anterior no
  /// se reutiliza nunca) y anula las peticiones en curso. Primero guarda la
  /// dirección: si no se puede guardar, no cambia nada.
  Future<void> cambiarServidor(Uri nueva) async {
    if (nueva == _base) return;
    try {
      await config?.guardar(nueva);
    } catch (_) {
      throw ErrorCliente('No se pudo guardar la dirección del servidor.');
    }
    _generacion++;
    _token = null;
    _correo = null;
    _base = nueva;
    notifyListeners();
  }

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
    _generacion++;
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
    final generacion = _generacion;
    final peticion = http.Request(metodo, rutaEn(_base, ruta))
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

    if (generacion != _generacion) {
      // Mientras esperaba cambió el servidor o se cerró la sesión: esta
      // respuesta ya no vale y no debe crear ni cerrar nada.
      throw ErrorCliente('La configuración cambió. Vuelve a intentarlo.');
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
