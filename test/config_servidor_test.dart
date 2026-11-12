import 'dart:async';
import 'dart:convert';

import 'package:dart_package_1/auth/cliente_auth.dart';
import 'package:dart_package_1/auth/config_servidor.dart';
import 'package:dart_package_1/online/cliente_multijugador.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

String? error(String texto) {
  try {
    validarUrlServidor(texto);
    return null;
  } on ErrorUrl catch (e) {
    return e.mensaje;
  }
}

http.Response json(Object cuerpo, [int codigo = 200]) => http.Response(
  jsonEncode(cuerpo),
  codigo,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  group('Validación y normalización', () {
    test('acepta http y https con host y puerto opcional', () {
      expect(
        validarUrlServidor('http://192.168.1.10:8080').toString(),
        'http://192.168.1.10:8080',
      );
      expect(
        validarUrlServidor('https://juego.example.com').toString(),
        'https://juego.example.com',
      );
      expect(
        validarUrlServidor('http://localhost').toString(),
        'http://localhost',
      );
      expect(validarUrlServidor('http://[::1]:8080').host, '::1');
    });

    test('quita espacios exteriores y la barra final', () {
      expect(
        validarUrlServidor('  http://10.0.0.5:8080/  ').toString(),
        'http://10.0.0.5:8080',
      );
      expect(
        validarUrlServidor('https://x.com///').toString(),
        'https://x.com',
      );
    });

    test('normaliza esquema y host a minúsculas', () {
      expect(
        validarUrlServidor('HTTP://MiServidor.LOCAL:9000').toString(),
        'http://miservidor.local:9000',
      );
    });

    test('conserva un prefijo de ruta válido (sin la barra final)', () {
      expect(
        validarUrlServidor('https://x.com/brilliant/').toString(),
        'https://x.com/brilliant',
      );
      expect(validarUrlServidor('http://x.com:81/a/b').path, '/a/b');
    });

    test('rechaza lo vacío, sin esquema o con otro esquema', () {
      expect(error(''), contains('Escribe'));
      expect(error('   '), contains('Escribe'));
      expect(error('192.168.1.10:8080'), contains('http://'));
      expect(error('localhost:8080'), contains('http://'));
      expect(error('ftp://x.com'), contains('http'));
      expect(error('ws://x.com'), contains('http'));
    });

    test('rechaza credenciales incrustadas', () {
      expect(error('http://usuario:clave@x.com'), contains('usuario'));
      expect(error('http://usuario@x.com'), contains('usuario'));
      expect(error('http://:@x.com'), isNotNull);
    });

    test('rechaza query y fragmento (también vacíos)', () {
      expect(error('http://x.com?a=1'), contains('parámetros'));
      expect(error('http://x.com/?'), contains('parámetros'));
      expect(error('http://x.com/ruta#algo'), contains('fragmento'));
      expect(error('http://x.com#'), contains('fragmento'));
    });

    test('rechaza host ausente, espacios internos y puertos inválidos', () {
      expect(error('http://'), contains('Falta'));
      expect(error('http:///ruta'), isNotNull);
      expect(error('http://ho st.com'), contains('espacios'));
      expect(error('http://x.com:0'), contains('puerto'));
      expect(error('http://x.com:70000'), isNotNull);
      expect(error('http://x.com:abc'), isNotNull);
    });
  });

  group('Prioridad de la dirección efectiva', () {
    test('guardada válida > define > por defecto', () {
      final r = resolverUrlServidor(
        guardada: 'http://guardada:1',
        define: 'http://define:2',
        fallback: 'http://fallback:3',
      );
      expect(r.url.toString(), 'http://guardada:1');
      expect(r.origen, OrigenUrl.guardada);
    });

    test('sin guardada se usa el --dart-define', () {
      final r = resolverUrlServidor(
        define: 'http://define:2',
        fallback: 'http://fallback:3',
      );
      expect(r.url.toString(), 'http://define:2');
      expect(r.origen, OrigenUrl.define);
    });

    test('sin guardada ni define se usa el valor por defecto', () {
      final r = resolverUrlServidor(define: '', fallback: 'http://fallback:3');
      expect(r.url.toString(), 'http://fallback:3');
      expect(r.origen, OrigenUrl.porDefecto);
    });

    test('una guardada inválida o corrupta se ignora', () {
      for (final mala in ['', 'basura', 'http://u:p@x.com', 'ftp://x']) {
        final r = resolverUrlServidor(
          guardada: mala,
          define: 'http://define:2',
        );
        expect(r.origen, OrigenUrl.define, reason: mala);
      }
    });

    test('un define inválido cae al valor por defecto', () {
      final r = resolverUrlServidor(
        define: 'esto no es una url',
        fallback: 'http://fallback:3',
      );
      expect(r.origen, OrigenUrl.porDefecto);
    });

    test('compatibilidad: la constante por defecto sigue existiendo', () {
      // Sin --dart-define en las pruebas, es el valor de siempre.
      expect(urlServidorPorDefecto, urlServidorFallback);
      expect(urlServidorFallback, 'http://localhost:8080');
    });
  });

  group('Derivación de rutas y WebSocket', () {
    test('http → ws y https → wss con el puerto', () {
      expect(
        urlWebSocketDe(Uri.parse('http://192.168.1.10:8080')).toString(),
        'ws://192.168.1.10:8080/ws',
      );
      expect(
        urlWebSocketDe(Uri.parse('https://juego.example.com')).toString(),
        'wss://juego.example.com/ws',
      );
      expect(
        urlWebSocketDe(Uri.parse('https://juego.example.com:8443')).toString(),
        'wss://juego.example.com:8443/ws',
      );
    });

    test('conserva el prefijo de ruta y no deja query ni fragmento', () {
      final ws = urlWebSocketDe(Uri.parse('https://x.com/brilliant'));
      expect(ws.toString(), 'wss://x.com/brilliant/ws');
      expect(
        urlWebSocket(Uri.parse('http://x.com/a/')).toString(),
        'ws://x.com/a/ws',
      );
      expect(ws.hasQuery, isFalse);
      expect(ws.hasFragment, isFalse);
    });

    test('rutaEn añade la ruta bajo el prefijo', () {
      expect(
        rutaEn(Uri.parse('http://h:1'), '/login').toString(),
        'http://h:1/login',
      );
      expect(
        rutaEn(Uri.parse('https://h/api'), '/salud').toString(),
        'https://h/api/salud',
      );
    });
  });

  group('Persistencia con shared_preferences', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('guardar y restaurar tras "reiniciar" la app', () async {
      final c = await ConfigServidor.cargar(define: '');
      expect(c.origen, OrigenUrl.porDefecto);
      await c.guardar(Uri.parse('http://192.168.1.50:8080'));
      expect(c.url.toString(), 'http://192.168.1.50:8080');
      expect(c.origen, OrigenUrl.guardada);

      final otra = await ConfigServidor.cargar(define: 'http://define:9');
      expect(otra.url.toString(), 'http://192.168.1.50:8080');
      expect(otra.origen, OrigenUrl.guardada, reason: 'gana a --dart-define');
    });

    test('solo se guarda la URL: nunca contraseñas ni tokens', () async {
      final auth = ClienteAuth(
        cliente: MockClient((_) async => json({'token': 'secreto-123'})),
        config: await ConfigServidor.cargar(define: 'http://a:1'),
      );
      await auth.iniciarSesion('a@b.com', 'MiClave123');
      await auth.cambiarServidor(Uri.parse('http://b:2'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'url_servidor'});
      final todo = prefs.getKeys().map((k) => '${prefs.get(k)}').join();
      expect(todo, isNot(contains('secreto-123')));
      expect(todo, isNot(contains('MiClave123')));
    });

    test('sin nada guardado se usa el define', () async {
      final c = await ConfigServidor.cargar(define: 'http://define:9');
      expect(c.url.toString(), 'http://define:9');
      expect(c.origen, OrigenUrl.define);
    });

    test('una preferencia corrupta no impide arrancar', () async {
      SharedPreferences.setMockInitialValues({'url_servidor': 'esto??no'});
      final c = await ConfigServidor.cargar(define: 'http://define:9');
      expect(c.url.toString(), 'http://define:9');
    });

    test('si no se puede leer el almacén se sigue con el define', () async {
      final c = await ConfigServidor.cargar(
        almacen: _AlmacenRoto(),
        define: 'http://define:9',
      );
      expect(c.url.toString(), 'http://define:9');
    });
  });

  group('Prueba de conexión', () {
    final base = Uri.parse('http://h:8080');
    const ok = {'servicio': 'brilliant', 'protocolo': 1, 'ok': true};

    Future<PruebaServidor> probar(
      FutureOr<http.Response> Function(http.Request) f, {
      Duration tiempo = const Duration(seconds: 2),
      Uri? url,
    }) => probarServidor(
      url ?? base,
      crearCliente: () => MockClient((r) async => f(r)),
      tiempoMaximo: tiempo,
    );

    test('éxito: responde un servidor Brilliant compatible', () async {
      late http.Request recibida;
      final r = await probar((req) {
        recibida = req;
        return json(ok);
      });
      expect(r.resultado, ResultadoPrueba.correcta);
      expect(recibida.url.toString(), 'http://h:8080/salud');
      expect(recibida.method, 'GET');
      expect(
        recibida.headers.containsKey('authorization'),
        isFalse,
        reason: 'no usa sesión',
      );
    });

    test('respeta el prefijo de ruta de la dirección', () async {
      late Uri pedida;
      await probar((req) {
        pedida = req.url;
        return json(ok);
      }, url: Uri.parse('https://x.com/brilliant'));
      expect(pedida.toString(), 'https://x.com/brilliant/salud');
    });

    test('tiempo agotado', () async {
      final r = await probar(
        (_) => Completer<http.Response>().future,
        tiempo: const Duration(milliseconds: 40),
      );
      expect(r.resultado, ResultadoPrueba.tiempoAgotado);
      expect(r.mensaje, contains('tardó'));
    });

    test('error de conexión', () async {
      final r = await probar((_) => throw http.ClientException('rechazada'));
      expect(r.resultado, ResultadoPrueba.sinConexion);
      expect(r.mensaje, contains('No se pudo conectar'));
    });

    test('un puerto abierto que no es Brilliant es incompatible', () async {
      for (final resp in [
        http.Response('<html>hola</html>', 200),
        http.Response('not found', 404),
        http.Response('error', 500),
        json({'servicio': 'otra-cosa', 'protocolo': 1}),
        json(['no', 'es', 'un', 'objeto']),
        json({'ok': true}),
      ]) {
        final r = await probar((_) => resp);
        expect(r.resultado, ResultadoPrueba.incompatible, reason: resp.body);
      }
    });

    test('servidor Brilliant con otra versión de protocolo', () async {
      final r = await probar(
        (_) => json({'servicio': 'brilliant', 'protocolo': 99}),
      );
      expect(r.resultado, ResultadoPrueba.incompatible);
      expect(r.mensaje, contains('versión incompatible'));
    });

    test('cierra el cliente HTTP también al fallar', () async {
      final cliente = _ClienteConCierre();
      await probarServidor(base, crearCliente: () => cliente);
      expect(cliente.cerrado, isTrue);
    });
  });

  group('Cambio de servidor sin arrastrar sesión', () {
    late List<http.Request> peticiones;
    late Completer<http.Response>? pendiente;

    ClienteAuth crear({ConfigServidor? config, bool pausaLogin = false}) {
      peticiones = [];
      pendiente = null;
      return ClienteAuth(
        config: config,
        urlBase: config == null ? 'http://viejo:1' : null,
        cliente: MockClient((req) async {
          peticiones.add(req);
          if (req.url.path.endsWith('/login') && pausaLogin) {
            pendiente = Completer<http.Response>();
            return pendiente!.future;
          }
          if (req.url.path.endsWith('/login')) {
            return json({'token': 'token-de-${req.url.host}'});
          }
          return json({'ok': true});
        }),
      );
    }

    test('cierra la sesión y no reutiliza el token anterior', () async {
      final auth = crear();
      await auth.iniciarSesion('a@b.com', 'x');
      expect(auth.token, 'token-de-viejo');
      var avisos = 0;
      auth.addListener(() => avisos++);

      await auth.cambiarServidor(Uri.parse('http://nuevo:2'));
      expect(auth.haySesion, isFalse);
      expect(auth.token, isNull);
      expect(auth.correo, isNull);
      expect(auth.urlBase.toString(), 'http://nuevo:2');
      expect(avisos, 1);

      // Las peticiones siguientes van al nuevo servidor y sin token viejo.
      await auth.iniciarSesion('a@b.com', 'x');
      expect(peticiones.last.url.host, 'nuevo');
      expect(peticiones.last.headers.containsKey('authorization'), isFalse);
      expect(auth.token, 'token-de-nuevo');
    });

    test('borrar cuenta tras cambiar no envía el token anterior', () async {
      final auth = crear();
      await auth.iniciarSesion('a@b.com', 'x');
      await auth.cambiarServidor(Uri.parse('http://nuevo:2'));
      await auth.borrarCuenta('x').catchError((_) {});
      for (final p in peticiones.where((p) => p.url.host == 'nuevo')) {
        expect(p.headers['authorization'], isNot(contains('token-de-viejo')));
      }
    });

    test('una respuesta en vuelo del servidor anterior se descarta', () async {
      final auth = crear(pausaLogin: true);
      final intento = auth.iniciarSesion('a@b.com', 'x');
      await Future<void>.delayed(Duration.zero);
      await auth.cambiarServidor(Uri.parse('http://nuevo:2'));
      pendiente!.complete(json({'token': 'token-del-viejo'}));
      await expectLater(intento, throwsA(isA<ErrorCliente>()));
      expect(
        auth.haySesion,
        isFalse,
        reason: 'no se crea sesión con el token viejo',
      );
      expect(auth.token, isNull);
    });

    test('el mismo servidor no cierra la sesión', () async {
      final auth = crear();
      await auth.iniciarSesion('a@b.com', 'x');
      await auth.cambiarServidor(Uri.parse('http://viejo:1'));
      expect(auth.haySesion, isTrue);
    });

    test('si no se puede guardar, no cambia nada', () async {
      final almacen = AlmacenUrlMemoria()..fallaAlGuardar = true;
      final config = ConfigServidor.fija(
        Uri.parse('http://viejo:1'),
        almacen: almacen,
      );
      final auth = crear(config: config);
      await auth.iniciarSesion('a@b.com', 'x');
      await expectLater(
        auth.cambiarServidor(Uri.parse('http://nuevo:2')),
        throwsA(isA<ErrorCliente>()),
      );
      expect(auth.urlBase.toString(), 'http://viejo:1');
      expect(auth.haySesion, isTrue);
      expect(config.url.toString(), 'http://viejo:1');
      expect(almacen.valor, isNull);
    });

    test(
      'guarda la dirección y avisa a quien escucha la configuración',
      () async {
        final almacen = AlmacenUrlMemoria();
        final config = ConfigServidor.fija(
          Uri.parse('http://viejo:1'),
          almacen: almacen,
        );
        var avisos = 0;
        config.addListener(() => avisos++);
        final auth = crear(config: config);
        await auth.cambiarServidor(Uri.parse('https://nuevo.example.com'));
        expect(almacen.valor, 'https://nuevo.example.com');
        expect(config.origen, OrigenUrl.guardada);
        expect(avisos, 1);
      },
    );

    test('las peticiones respetan el prefijo de ruta del servidor', () async {
      final auth = crear();
      await auth.cambiarServidor(Uri.parse('https://x.com/brilliant'));
      await auth.iniciarSesion('a@b.com', 'x');
      expect(peticiones.last.url.toString(), 'https://x.com/brilliant/login');
    });

    test(
      'el WebSocket del cliente usa la dirección del servidor actual',
      () async {
        final auth = crear();
        expect(urlWebSocket(auth.urlBase).toString(), 'ws://viejo:1/ws');
        await auth.cambiarServidor(Uri.parse('https://nuevo.example.com'));
        expect(
          urlWebSocket(auth.urlBase).toString(),
          'wss://nuevo.example.com/ws',
        );
      },
    );

    test('cerrar el cliente multijugador cancela las reconexiones', () async {
      // El cliente se crea con la URL del servidor anterior; al cambiar de
      // servidor la pantalla lo cierra y no vuelve a conectar nunca.
      final conexiones = <Uri>[];
      final cliente = ClienteMultijugador(
        url: Uri.parse('ws://viejo:1/ws'),
        token: () => 'token-viejo',
        fabrica: (url) {
          conexiones.add(url);
          throw StateError('sin red');
        },
        esperasReintento: const [Duration(milliseconds: 10)],
      );
      cliente.conectar();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final antes = conexiones.length;
      cliente.cerrar();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(conexiones.length, antes, reason: 'no hay más reintentos');
      expect(cliente.conexion, EstadoConexion.desconectado);
    });
  });
}

class _AlmacenRoto implements AlmacenUrl {
  @override
  Future<String?> leer() async => throw StateError('no se puede leer');
  @override
  Future<void> guardar(String url) async => throw StateError('no');
  @override
  Future<void> borrar() async {}
}

class _ClienteConCierre extends http.BaseClient {
  bool cerrado = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.error(http.ClientException('sin red'));

  @override
  void close() => cerrado = true;
}
