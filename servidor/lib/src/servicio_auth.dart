import 'dart:convert';
import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'almacen.dart';

class ErrorAuth implements Exception {
  ErrorAuth(this.codigo, this.mensaje);
  final int codigo;
  final String mensaje;
}

/// Lógica de cuentas: registro, login, borrado y verificación de tokens.
class ServicioAuth {
  ServicioAuth({
    required this.almacen,
    required String secretoJwt,
    this.duracionToken = const Duration(hours: 1),
    this.maxIntentos = 5,
    this.bloqueo = const Duration(minutes: 15),
    this.costoBcrypt = 12,
    DateTime Function()? ahora,
  }) : _secreto = SecretKey(secretoJwt),
       _ahora = ahora ?? DateTime.now,
       // Hash de relleno para igualar tiempos cuando el correo no existe.
       _hashFalso = BCrypt.hashpw(
         'relleno',
         BCrypt.gensalt(logRounds: costoBcrypt),
       );

  final AlmacenUsuarios almacen;
  final Duration duracionToken;
  final int maxIntentos;
  final Duration bloqueo;
  final int costoBcrypt;
  final SecretKey _secreto;
  final DateTime Function() _ahora;
  final String _hashFalso;
  final Map<String, _Intentos> _intentos = {};

  static final _regexCorreo = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  static String normalizarCorreo(String c) => c.trim().toLowerCase();

  static void validarContrasena(String p) {
    // bcrypt ignora todo lo que pase de 72 bytes.
    if (utf8.encode(p).length > 72) {
      throw ErrorAuth(400, 'La contraseña no puede pasar de 72 bytes.');
    }
    if (p.length < 8 ||
        !p.contains(RegExp(r'[A-Za-z]')) ||
        !p.contains(RegExp(r'\d'))) {
      throw ErrorAuth(
        400,
        'La contraseña debe tener al menos 8 caracteres, con letras y números.',
      );
    }
  }

  Future<Usuario> registrar(String correo, String contrasena) async {
    correo = normalizarCorreo(correo);
    if (correo.length > 254 || !_regexCorreo.hasMatch(correo)) {
      throw ErrorAuth(400, 'Correo inválido.');
    }
    validarContrasena(contrasena);
    if (almacen.porCorreo(correo) != null) {
      throw ErrorAuth(409, 'Ese correo ya está registrado.');
    }
    final u = Usuario(
      id: _idAleatorio(),
      correo: correo,
      hashContrasena: BCrypt.hashpw(
        contrasena,
        BCrypt.gensalt(logRounds: costoBcrypt),
      ),
      creado: _ahora().toUtc(),
    );
    await almacen.guardar(u);
    return u;
  }

  /// Devuelve un token JWT si las credenciales son correctas.
  String iniciarSesion(String correo, String contrasena) {
    correo = normalizarCorreo(correo);
    _revisarBloqueo(correo);
    final u = almacen.porCorreo(correo);
    final ok = BCrypt.checkpw(contrasena, u?.hashContrasena ?? _hashFalso);
    if (u == null || !ok) {
      _registrarFallo(correo);
      throw ErrorAuth(401, 'Correo o contraseña incorrectos.');
    }
    _intentos.remove(correo);
    return JWT({'sub': u.id}).sign(_secreto, expiresIn: duracionToken);
  }

  /// Valida el token y devuelve al usuario; null si no es válido.
  Usuario? usuarioDeToken(String token) {
    try {
      final jwt = JWT.verify(token, _secreto);
      return almacen.porId((jwt.payload as Map)['sub'] as String);
    } catch (_) {
      return null;
    }
  }

  Future<void> borrarCuenta(Usuario u, String contrasena) async {
    if (!BCrypt.checkpw(contrasena, u.hashContrasena)) {
      throw ErrorAuth(401, 'Contraseña incorrecta.');
    }
    await almacen.borrar(u.id);
  }

  void _revisarBloqueo(String correo) {
    final i = _intentos[correo];
    if (i != null && i.hasta != null && _ahora().isBefore(i.hasta!)) {
      throw ErrorAuth(429, 'Demasiados intentos. Intenta más tarde.');
    }
  }

  void _registrarFallo(String correo) {
    final i = _intentos.putIfAbsent(correo, _Intentos.new);
    i.fallos++;
    if (i.fallos >= maxIntentos) {
      i.hasta = _ahora().add(bloqueo);
      i.fallos = 0;
    }
  }

  static String _idAleatorio() {
    final r = Random.secure();
    return base64UrlEncode(List.generate(18, (_) => r.nextInt(256)));
  }
}

class _Intentos {
  int fallos = 0;
  DateTime? hasta;
}
