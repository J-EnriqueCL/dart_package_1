import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../dart_package_1.dart';

/// Valor de `--dart-define=URL_SERVIDOR=...` ('' si no se dio).
const urlServidorDefine = String.fromEnvironment('URL_SERVIDOR');

/// Último recurso cuando no hay URL guardada ni `--dart-define`.
const urlServidorFallback = 'http://localhost:8080';

/// Dirección del servidor que usa la app al arrancar si no hay una guardada
/// (compatibilidad con los comandos de compilación actuales).
const urlServidorPorDefecto = urlServidorDefine == ''
    ? urlServidorFallback
    : urlServidorDefine;

/// De dónde sale la dirección efectiva del servidor.
enum OrigenUrl {
  /// La que el usuario guardó desde la app.
  guardada,

  /// La del `--dart-define=URL_SERVIDOR` con que se compiló.
  define,

  /// El valor de último recurso.
  porDefecto,
}

/// La dirección escrita no es válida; [mensaje] se muestra tal cual.
class ErrorUrl implements Exception {
  ErrorUrl(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Valida y normaliza la dirección base de un servidor.
///
/// Acepta `http://` y `https://` con host y puerto opcional (y, si se desea,
/// un prefijo de ruta, por ejemplo detrás de un proxy). Quita los espacios
/// exteriores y la barra final. Rechaza credenciales, `?query` y `#fragmento`.
/// Lanza [ErrorUrl] con un mensaje claro si no es válida.
Uri validarUrlServidor(String entrada) {
  final t = entrada.trim();
  if (t.isEmpty) throw ErrorUrl('Escribe la dirección del servidor.');
  if (RegExp(r'\s').hasMatch(t)) {
    throw ErrorUrl('La dirección no puede contener espacios.');
  }
  if (!RegExp(r'^[A-Za-z][A-Za-z0-9+.-]*://').hasMatch(t)) {
    throw ErrorUrl(
      'Empieza por http:// o https:// '
      '(por ejemplo, http://192.168.1.10:8080).',
    );
  }
  final Uri u;
  try {
    u = Uri.parse(t);
  } on FormatException {
    throw ErrorUrl(
      'La dirección no es válida (revisa el puerto y el formato).',
    );
  }
  if (u.scheme != 'http' && u.scheme != 'https') {
    throw ErrorUrl('Solo se admiten direcciones http:// o https://.');
  }
  if (u.host.isEmpty) {
    throw ErrorUrl('Falta el nombre o la IP del servidor.');
  }
  if (u.userInfo.isNotEmpty) {
    throw ErrorUrl('No pongas usuario ni contraseña dentro de la dirección.');
  }
  if (u.hasQuery) {
    throw ErrorUrl('La dirección no puede llevar parámetros (?…).');
  }
  if (u.hasFragment) {
    throw ErrorUrl('La dirección no puede llevar fragmento (#…).');
  }
  if (u.hasPort && (u.port < 1 || u.port > 65535)) {
    throw ErrorUrl('El puerto debe estar entre 1 y 65535.');
  }
  final ruta = u.path.replaceFirst(RegExp(r'/+$'), '');
  return Uri(
    scheme: u.scheme,
    host: u.host,
    port: u.hasPort ? u.port : null,
    path: ruta,
  );
}

/// Dirección efectiva y su origen. Prioridad: la guardada (si es válida) >
/// el `--dart-define` (si es válido) > el valor de último recurso. Una
/// dirección guardada o definida que no sea válida se ignora.
({Uri url, OrigenUrl origen}) resolverUrlServidor({
  String? guardada,
  String define = urlServidorDefine,
  String fallback = urlServidorFallback,
}) {
  if (guardada != null) {
    try {
      return (url: validarUrlServidor(guardada), origen: OrigenUrl.guardada);
    } on ErrorUrl {
      // Una preferencia corrupta no debe impedir arrancar.
    }
  }
  if (define.trim().isNotEmpty) {
    try {
      return (url: validarUrlServidor(define), origen: OrigenUrl.define);
    } on ErrorUrl {
      // Un define mal escrito tampoco.
    }
  }
  return (url: validarUrlServidor(fallback), origen: OrigenUrl.porDefecto);
}

/// Ruta [ruta] (que empieza por `/`) bajo la dirección base [base], conservando
/// el prefijo de ruta de la base. (`Uri.resolve('/x')` lo descartaría.)
Uri rutaEn(Uri base, String ruta) {
  final prefijo = base.path.replaceFirst(RegExp(r'/+$'), '');
  return base.replace(path: '$prefijo$ruta', query: null, fragment: null);
}

/// Dirección del WebSocket a partir de la del servidor HTTP: `http` → `ws`,
/// `https` → `wss`, con la ruta `/ws` bajo el mismo prefijo.
Uri urlWebSocketDe(Uri base) =>
    rutaEn(base, '/ws').replace(scheme: base.scheme == 'https' ? 'wss' : 'ws');

/// Dónde se guarda la dirección elegida. Solo la URL: nunca contraseñas ni
/// tokens.
abstract class AlmacenUrl {
  Future<String?> leer();
  Future<void> guardar(String url);
  Future<void> borrar();
}

/// Guarda la dirección con `shared_preferences`.
class AlmacenUrlPreferencias implements AlmacenUrl {
  const AlmacenUrlPreferencias();

  static const clave = 'url_servidor';

  @override
  Future<String?> leer() async =>
      (await SharedPreferences.getInstance()).getString(clave);

  @override
  Future<void> guardar(String url) async {
    final ok = await (await SharedPreferences.getInstance()).setString(
      clave,
      url,
    );
    if (!ok) throw StateError('No se pudo guardar la dirección.');
  }

  @override
  Future<void> borrar() async {
    await (await SharedPreferences.getInstance()).remove(clave);
  }
}

/// Almacén en memoria (pruebas).
class AlmacenUrlMemoria implements AlmacenUrl {
  AlmacenUrlMemoria([this.valor]);
  String? valor;
  bool fallaAlGuardar = false;

  @override
  Future<String?> leer() async => valor;

  @override
  Future<void> guardar(String url) async {
    if (fallaAlGuardar) throw StateError('disco lleno');
    valor = url;
  }

  @override
  Future<void> borrar() async => valor = null;
}

/// Resultado de "Probar conexión".
enum ResultadoPrueba {
  /// Responde un servidor Brilliant con un protocolo compatible.
  correcta,

  /// No contestó a tiempo.
  tiempoAgotado,

  /// No se pudo conectar (host inalcanzable, puerto cerrado, TLS, etc.).
  sinConexion,

  /// Contestó algo que no es un servidor Brilliant compatible.
  incompatible,
}

class PruebaServidor {
  const PruebaServidor(this.resultado, this.mensaje);
  final ResultadoPrueba resultado;
  final String mensaje;

  bool get correcta => resultado == ResultadoPrueba.correcta;
}

/// Función que comprueba un servidor (inyectable en pruebas).
typedef Probador = Future<PruebaServidor> Function(Uri base);

/// Comprueba `GET /salud` (público, sin sesión) con un tiempo máximo y exige
/// que responda un servidor Brilliant con el protocolo [versionProtocolo]: que
/// haya un puerto abierto no basta.
Future<PruebaServidor> probarServidor(
  Uri base, {
  http.Client Function()? crearCliente,
  Duration tiempoMaximo = const Duration(seconds: 6),
}) async {
  final cliente = (crearCliente ?? http.Client.new)();
  try {
    final resp = await cliente
        .get(rutaEn(base, '/salud'))
        .timeout(tiempoMaximo);
    if (resp.statusCode != 200) {
      return PruebaServidor(
        ResultadoPrueba.incompatible,
        'Respondió algo, pero no parece un servidor Brilliant '
        '(código ${resp.statusCode}).',
      );
    }
    Object? datos;
    try {
      datos = jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (_) {}
    if (datos is! Map || datos['servicio'] != servicioBrilliant) {
      return const PruebaServidor(
        ResultadoPrueba.incompatible,
        'Respondió algo, pero no es un servidor Brilliant.',
      );
    }
    if (datos['protocolo'] != versionProtocolo) {
      return const PruebaServidor(
        ResultadoPrueba.incompatible,
        'Es un servidor Brilliant, pero de una versión incompatible con '
        'esta app. Actualiza el servidor o la app.',
      );
    }
    return const PruebaServidor(
      ResultadoPrueba.correcta,
      'Conexión correcta: servidor Brilliant compatible.',
    );
  } on TimeoutException {
    return const PruebaServidor(
      ResultadoPrueba.tiempoAgotado,
      'El servidor tardó demasiado en responder.',
    );
  } catch (_) {
    return const PruebaServidor(
      ResultadoPrueba.sinConexion,
      'No se pudo conectar. Revisa la dirección, que el servidor esté '
      'encendido y que estén en la misma red.',
    );
  } finally {
    cliente.close();
  }
}

/// Dirección efectiva del servidor, su persistencia y la prueba de conexión.
///
/// Es la única fuente de la URL que usan los clientes HTTP y WebSocket.
class ConfigServidor extends ChangeNotifier {
  ConfigServidor._(this._almacen, this._probador, this._url, this._origen);

  /// Crea una configuración con una dirección ya resuelta (pruebas).
  ConfigServidor.fija(
    Uri url, {
    AlmacenUrl? almacen,
    Probador? probador,
    OrigenUrl origen = OrigenUrl.porDefecto,
  }) : this._(
         almacen ?? AlmacenUrlMemoria(),
         probador ?? probarServidor,
         url,
         origen,
       );

  /// Lee la dirección guardada (si la hay) y resuelve la efectiva **antes** de
  /// crear los clientes de red.
  static Future<ConfigServidor> cargar({
    AlmacenUrl almacen = const AlmacenUrlPreferencias(),
    Probador? probador,
    String define = urlServidorDefine,
    String fallback = urlServidorFallback,
  }) async {
    String? guardada;
    try {
      guardada = await almacen.leer();
    } catch (_) {
      // Si no se puede leer, se sigue con el define o el valor por defecto.
    }
    final r = resolverUrlServidor(
      guardada: guardada,
      define: define,
      fallback: fallback,
    );
    return ConfigServidor._(
      almacen,
      probador ?? probarServidor,
      r.url,
      r.origen,
    );
  }

  final AlmacenUrl _almacen;
  final Probador _probador;
  Uri _url;
  OrigenUrl _origen;

  Uri get url => _url;
  OrigenUrl get origen => _origen;

  Future<PruebaServidor> probar(Uri base) => _probador(base);

  /// Guarda [nueva] como dirección del servidor. Si no se puede guardar lanza
  /// y deja la configuración vigente como estaba.
  Future<void> guardar(Uri nueva) async {
    await _almacen.guardar(nueva.toString());
    _url = nueva;
    _origen = OrigenUrl.guardada;
    notifyListeners();
  }
}
