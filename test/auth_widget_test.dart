import 'dart:convert';

import 'package:dart_package_1/auth/cliente_auth.dart';
import 'package:dart_package_1/main.dart';
import 'package:dart_package_1/pantalla_seleccion_mapa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'ayudas_pruebas.dart';

/// Servidor falso en memoria con las mismas rutas que el real.
class _ServidorFalso {
  final Map<String, String> cuentas = {};

  http.Response responder(http.Request req) {
    final cuerpo = jsonDecode(req.body) as Map;
    final correo = (cuerpo['correo'] as String?)?.trim().toLowerCase();
    final pass = cuerpo['contrasena'] as String;
    switch ('${req.method} ${req.url.path}') {
      case 'POST /registro':
        if (cuentas.containsKey(correo)) {
          return _json(409, {'error': 'Ese correo ya está registrado.'});
        }
        cuentas[correo!] = pass;
        return _json(201, {'correo': correo});
      case 'POST /login':
        if (cuentas[correo] != pass) {
          return _json(401, {'error': 'Correo o contraseña incorrectos.'});
        }
        return _json(200, {'token': 'token-$correo'});
      case 'DELETE /cuenta':
        final c = req.headers['authorization']!.substring(
          'Bearer token-'.length,
        );
        if (cuentas[c] != pass) {
          return _json(401, {'error': 'Contraseña incorrecta.'});
        }
        cuentas.remove(c);
        return _json(200, {'ok': true});
    }
    return _json(404, {'error': 'no existe'});
  }

  http.Response _json(int codigo, Map<String, Object?> d) => http.Response(
    jsonEncode(d),
    codigo,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  setUpAll(cargarFuentes);

  late _ServidorFalso servidor;
  late ClienteAuth auth;

  setUp(() {
    servidor = _ServidorFalso();
    auth = ClienteAuth(
      cliente: MockClient((req) async => servidor.responder(req)),
      urlBase: 'http://servidor.test',
    );
  });

  Future<void> abrir(WidgetTester tester) async {
    await fijarPantalla(tester);
    await tester.pumpWidget(AplicacionBrilliant(auth: auth));
    await tester.pumpAndSettle();
  }

  Future<void> escribir(WidgetTester tester, String clave, String texto) async {
    await tester.enterText(find.byKey(Key(clave)), texto);
  }

  Future<void> irARegistro(WidgetTester tester) =>
      tocar(tester, find.byKey(const Key('boton_cambiar_modo')));

  Future<void> enviar(WidgetTester tester) =>
      tocar(tester, find.byKey(const Key('boton_enviar_acceso')));

  testWidgets('sin sesión se muestra el acceso, no el juego', (tester) async {
    await abrir(tester);
    expect(find.byKey(const Key('titulo_acceso')), findsOneWidget);
    expect(find.byType(PantallaSeleccionMapa), findsNothing);
  });

  testWidgets('crear cuenta valida los campos antes de enviar', (tester) async {
    await abrir(tester);
    await irARegistro(tester);
    await escribir(tester, 'campo_correo', 'no-es-correo');
    await escribir(tester, 'campo_contrasena', 'corta');
    await escribir(tester, 'campo_repetir', 'otra');
    await enviar(tester);

    expect(find.text('Escribe un correo válido'), findsOneWidget);
    expect(
      find.text('Mínimo 8 caracteres, con letras y números'),
      findsOneWidget,
    );
    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
    expect(servidor.cuentas, isEmpty);
  });

  testWidgets('crear cuenta registra y entra al juego', (tester) async {
    await abrir(tester);
    await irARegistro(tester);
    await escribir(tester, 'campo_correo', 'Ana@Correo.com');
    await escribir(tester, 'campo_contrasena', 'clave1234');
    await escribir(tester, 'campo_repetir', 'clave1234');
    await enviar(tester);

    expect(servidor.cuentas.keys, ['ana@correo.com']);
    expect(find.byType(PantallaSeleccionMapa), findsOneWidget);
  });

  testWidgets('correo repetido muestra el error del servidor', (tester) async {
    servidor.cuentas['ana@correo.com'] = 'clave1234';
    await abrir(tester);
    await irARegistro(tester);
    await escribir(tester, 'campo_correo', 'ana@correo.com');
    await escribir(tester, 'campo_contrasena', 'clave1234');
    await escribir(tester, 'campo_repetir', 'clave1234');
    await enviar(tester);

    expect(find.text('Ese correo ya está registrado.'), findsOneWidget);
    expect(find.byType(PantallaSeleccionMapa), findsNothing);
  });

  testWidgets('login incorrecto muestra error; correcto entra', (tester) async {
    servidor.cuentas['ana@correo.com'] = 'clave1234';
    await abrir(tester);
    await escribir(tester, 'campo_correo', 'ana@correo.com');
    await escribir(tester, 'campo_contrasena', 'equivocada1');
    await enviar(tester);
    expect(find.byKey(const Key('error_acceso')), findsOneWidget);
    expect(find.byType(PantallaSeleccionMapa), findsNothing);

    await escribir(tester, 'campo_contrasena', 'clave1234');
    await enviar(tester);
    expect(find.byType(PantallaSeleccionMapa), findsOneWidget);
  });

  testWidgets('cerrar sesión vuelve al acceso', (tester) async {
    servidor.cuentas['ana@correo.com'] = 'clave1234';
    await auth.iniciarSesion('ana@correo.com', 'clave1234');
    await abrir(tester);

    await tocar(tester, find.byKey(const Key('menu_cuenta')));
    await tocar(tester, find.byKey(const Key('menu_salir')));

    expect(find.byKey(const Key('titulo_acceso')), findsOneWidget);
    expect(servidor.cuentas, isNotEmpty);
  });

  testWidgets('borrar cuenta pide contraseña y la elimina', (tester) async {
    servidor.cuentas['ana@correo.com'] = 'clave1234';
    await auth.iniciarSesion('ana@correo.com', 'clave1234');
    await abrir(tester);

    await tocar(tester, find.byKey(const Key('menu_cuenta')));
    await tocar(tester, find.byKey(const Key('menu_borrar')));

    await tester.enterText(
      find.byKey(const Key('campo_contrasena_borrar')),
      'mal',
    );
    await tocar(tester, find.byKey(const Key('boton_confirmar_borrar')));
    expect(find.text('Contraseña incorrecta.'), findsOneWidget);
    expect(servidor.cuentas, isNotEmpty);

    await tester.enterText(
      find.byKey(const Key('campo_contrasena_borrar')),
      'clave1234',
    );
    await tocar(tester, find.byKey(const Key('boton_confirmar_borrar')));

    expect(servidor.cuentas, isEmpty);
    expect(find.byKey(const Key('titulo_acceso')), findsOneWidget);
  });

  testWidgets('si el servidor no responde se avisa', (tester) async {
    auth = ClienteAuth(
      cliente: MockClient((_) async => throw Exception('sin red')),
      urlBase: 'http://servidor.test',
    );
    await abrir(tester);
    await escribir(tester, 'campo_correo', 'ana@correo.com');
    await escribir(tester, 'campo_contrasena', 'clave1234');
    await enviar(tester);
    expect(find.text('No se pudo conectar con el servidor.'), findsOneWidget);
  });
}
