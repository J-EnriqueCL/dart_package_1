import 'dart:convert';

import 'package:servidor_brilliant/servidor_brilliant.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late AlmacenMemoria almacen;
  late Handler api;
  var ahora = DateTime(2026, 1, 1);

  setUp(() {
    ahora = DateTime(2026, 1, 1);
    almacen = AlmacenMemoria();
    api = crearApi(
      ServicioAuth(
        almacen: almacen,
        secretoJwt: 'secreto-de-prueba-con-mas-de-32-caracteres',
        costoBcrypt: 4,
        ahora: () => ahora,
      ),
    );
  });

  Future<Response> llamar(
    String metodo,
    String ruta, {
    Map<String, Object?>? cuerpo,
    String? token,
  }) => Future.sync(
    () => api(
      Request(
        metodo,
        Uri.parse('http://localhost$ruta'),
        body: cuerpo == null ? null : jsonEncode(cuerpo),
        headers: {if (token != null) 'authorization': 'Bearer $token'},
      ),
    ),
  );

  Future<Map<String, Object?>> json(Response r) async =>
      (jsonDecode(await r.readAsString()) as Map).cast();

  Future<String> registrarYEntrar([
    String correo = 'a@b.com',
    String pass = 'clave1234',
  ]) async {
    await llamar(
      'POST',
      '/registro',
      cuerpo: {'correo': correo, 'contrasena': pass},
    );
    final r = await llamar(
      'POST',
      '/login',
      cuerpo: {'correo': correo, 'contrasena': pass},
    );
    return (await json(r))['token'] as String;
  }

  test('registro guarda hash, no la contraseña', () async {
    final r = await llamar(
      'POST',
      '/registro',
      cuerpo: {'correo': 'A@B.com ', 'contrasena': 'clave1234'},
    );
    expect(r.statusCode, 201);
    final u = almacen.porCorreo('a@b.com')!;
    expect(u.hashContrasena, startsWith(r'$2'));
    expect(u.hashContrasena, isNot(contains('clave1234')));
  });

  test('registro rechaza correo duplicado, correo y contraseña débiles', () async {
    await registrarYEntrar();
    var r = await llamar(
      'POST',
      '/registro',
      cuerpo: {'correo': 'a@b.com', 'contrasena': 'otraClave123'},
    );
    expect(r.statusCode, 409);
    r = await llamar(
      'POST',
      '/registro',
      cuerpo: {'correo': 'malo', 'contrasena': 'clave1234'},
    );
    expect(r.statusCode, 400);
    r = await llamar(
      'POST',
      '/registro',
      cuerpo: {'correo': 'c@d.com', 'contrasena': 'corta1'},
    );
    expect(r.statusCode, 400);
    r = await llamar(
      'POST',
      '/registro',
      cuerpo: {'correo': 'c@d.com', 'contrasena': 'solo letras'},
    );
    expect(r.statusCode, 400);
  });

  test('login correcto da token que abre /yo', () async {
    final token = await registrarYEntrar();
    final r = await llamar('GET', '/yo', token: token);
    expect(r.statusCode, 200);
    expect((await json(r))['correo'], 'a@b.com');
  });

  test('login con datos incorrectos da el mismo error', () async {
    await registrarYEntrar();
    final mal = await llamar(
      'POST',
      '/login',
      cuerpo: {'correo': 'a@b.com', 'contrasena': 'incorrecta1'},
    );
    final noExiste = await llamar(
      'POST',
      '/login',
      cuerpo: {'correo': 'x@y.com', 'contrasena': 'incorrecta1'},
    );
    expect(mal.statusCode, 401);
    expect(noExiste.statusCode, 401);
    expect(await json(mal), await json(noExiste));
  });

  test('se bloquea tras demasiados intentos y se libera con el tiempo', () async {
    await registrarYEntrar();
    for (var i = 0; i < 5; i++) {
      await llamar(
        'POST',
        '/login',
        cuerpo: {'correo': 'a@b.com', 'contrasena': 'incorrecta1'},
      );
    }
    var r = await llamar(
      'POST',
      '/login',
      cuerpo: {'correo': 'a@b.com', 'contrasena': 'clave1234'},
    );
    expect(r.statusCode, 429);
    ahora = ahora.add(const Duration(minutes: 16));
    r = await llamar(
      'POST',
      '/login',
      cuerpo: {'correo': 'a@b.com', 'contrasena': 'clave1234'},
    );
    expect(r.statusCode, 200);
  });

  test('rutas protegidas rechazan token ausente o falso', () async {
    expect((await llamar('GET', '/yo')).statusCode, 401);
    expect((await llamar('GET', '/yo', token: 'abc.def.ghi')).statusCode, 401);
  });

  test('borrar cuenta exige contraseña y deja el token inservible', () async {
    final token = await registrarYEntrar();
    var r = await llamar(
      'DELETE',
      '/cuenta',
      token: token,
      cuerpo: {'contrasena': 'incorrecta1'},
    );
    expect(r.statusCode, 401);
    expect(almacen.porCorreo('a@b.com'), isNotNull);

    r = await llamar(
      'DELETE',
      '/cuenta',
      token: token,
      cuerpo: {'contrasena': 'clave1234'},
    );
    expect(r.statusCode, 200);
    expect(almacen.porCorreo('a@b.com'), isNull);
    expect((await llamar('GET', '/yo', token: token)).statusCode, 401);
  });

  test('JSON inválido da 400', () async {
    final r = await api(
      Request('POST', Uri.parse('http://localhost/login'), body: 'no json'),
    );
    expect(r.statusCode, 400);
  });
  group('Salud', () {
    test('GET /salud es público y anuncia un servidor Brilliant compatible', () async {
      final r = await llamar('GET', '/salud');
      expect(r.statusCode, 200);
      final d = await json(r);
      expect(d, {'servicio': 'brilliant', 'protocolo': 1, 'ok': true});
    });

    test('no pide sesión y no filtra información sensible', () async {
      await registrarYEntrar('x@y.com');
      final r = await llamar('GET', '/salud', token: 'token-invalido');
      expect(r.statusCode, 200);
      final texto = jsonEncode(await json(r)).toLowerCase();
      for (final prohibido in ['x@y.com', 'token', 'secreto', 'usuario', 'hash']) {
        expect(texto, isNot(contains(prohibido)));
      }
    });

    test('solo acepta GET', () async {
      expect((await llamar('POST', '/salud')).statusCode, anyOf(404, 405));
    });
  });
}
