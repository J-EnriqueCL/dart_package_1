import 'dart:async';
import 'dart:convert';

import 'package:dart_package_1/auth/cliente_auth.dart';
import 'package:dart_package_1/auth/config_servidor.dart';
import 'package:dart_package_1/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'ayudas_pruebas.dart' hide tocar;

/// Como `tocar`, pero sin esperar a que todo se asiente: el indicador de
/// "Probando…" anima sin parar y `pumpAndSettle` no terminaría.
Future<void> tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(cargarFuentes);

  late AlmacenUrlMemoria almacen;
  late ConfigServidor config;
  late ClienteAuth auth;
  late List<(Uri, Completer<PruebaServidor>)> pruebas;
  late List<http.Request> peticiones;

  setUp(() {
    almacen = AlmacenUrlMemoria();
    pruebas = [];
    peticiones = [];
    config = ConfigServidor.fija(
      Uri.parse('http://viejo.test:8080'),
      almacen: almacen,
      probador: (uri) {
        final c = Completer<PruebaServidor>();
        pruebas.add((uri, c));
        return c.future;
      },
    );
    auth = ClienteAuth(
      config: config,
      cliente: MockClient((req) async {
        peticiones.add(req);
        return http.Response(
          jsonEncode({'token': 'token-${req.url.host}'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });

  Future<void> abrir(WidgetTester tester, {ClienteAuth? con}) async {
    await fijarPantalla(tester);
    await tester.pumpWidget(AplicacionBrilliant(auth: con ?? auth));
    await tester.pumpAndSettle();
  }

  Future<void> abrirDialogo(WidgetTester tester) async {
    await tocar(tester, find.byKey(const Key('boton_configurar_servidor')));
    expect(find.text('Servidor'), findsWidgets);
  }

  Future<void> escribirUrl(WidgetTester tester, String texto) async {
    await tester.enterText(find.byKey(const Key('campo_url_servidor')), texto);
    await tester.pump();
  }

  String textoDe(String clave) =>
      (find.byKey(Key(clave)).evaluate().single.widget as Text).data!;

  Future<void> iniciarSesion(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('campo_correo')),
      'ana@ejemplo.com',
    );
    await tester.enterText(
      find.byKey(const Key('campo_contrasena')),
      'clave1234',
    );
    await tocar(tester, find.byKey(const Key('boton_enviar_acceso')));
  }

  group('Pantalla de acceso', () {
    testWidgets('muestra el servidor actual y el botón de configurar', (
      tester,
    ) async {
      await abrir(tester);
      expect(textoDe('servidor_actual'), 'Servidor: http://viejo.test:8080');
      expect(
        find.byKey(const Key('boton_configurar_servidor')),
        findsOneWidget,
      );
    });

    testWidgets('sin configuración persistente no se ofrece cambiarlo', (
      tester,
    ) async {
      await abrir(
        tester,
        con: ClienteAuth(
          urlBase: 'http://fijo.test',
          cliente: MockClient((_) async => http.Response('{}', 200)),
        ),
      );
      expect(textoDe('servidor_actual'), contains('http://fijo.test'));
      expect(find.byKey(const Key('boton_configurar_servidor')), findsNothing);
    });

    testWidgets('el diálogo parte de la dirección vigente', (tester) async {
      await abrir(tester);
      await abrirDialogo(tester);
      final campo = tester.widget<TextField>(
        find.byKey(const Key('campo_url_servidor')),
      );
      expect(campo.controller!.text, 'http://viejo.test:8080');
      expect(find.byKey(const Key('boton_probar_servidor')), findsOneWidget);
      expect(find.byKey(const Key('boton_guardar_servidor')), findsOneWidget);
      expect(find.byKey(const Key('boton_cancelar_servidor')), findsOneWidget);
    });
  });

  group('Errores de entrada', () {
    for (final (entrada, mensaje) in [
      ('', 'Escribe la dirección'),
      ('192.168.1.10:8080', 'Empieza por http://'),
      ('ftp://x.com', 'http:// o https://'),
      ('http://u:p@x.com', 'usuario ni contraseña'),
      ('http://x.com?a=1', 'parámetros'),
      ('http://x.com#x', 'fragmento'),
      ('http://x.com:99999', 'puerto'),
    ]) {
      testWidgets('"$entrada" no se guarda y muestra el error', (tester) async {
        await abrir(tester);
        await abrirDialogo(tester);
        await escribirUrl(tester, entrada);
        await tocar(tester, find.byKey(const Key('boton_guardar_servidor')));
        expect(find.textContaining(mensaje), findsOneWidget);
        // El diálogo sigue abierto y nada cambió.
        expect(find.byKey(const Key('campo_url_servidor')), findsOneWidget);
        expect(auth.urlBase.toString(), 'http://viejo.test:8080');
        expect(almacen.valor, isNull);
      });
    }

    testWidgets('también valida al probar y no lanza ninguna prueba', (
      tester,
    ) async {
      await abrir(tester);
      await abrirDialogo(tester);
      await escribirUrl(tester, 'basura');
      await tocar(tester, find.byKey(const Key('boton_probar_servidor')));
      expect(find.textContaining('Empieza por http://'), findsOneWidget);
      expect(pruebas, isEmpty);
    });

    testWidgets('el error desaparece al seguir escribiendo', (tester) async {
      await abrir(tester);
      await abrirDialogo(tester);
      await escribirUrl(tester, 'basura');
      await tocar(tester, find.byKey(const Key('boton_guardar_servidor')));
      expect(find.textContaining('Empieza por http://'), findsOneWidget);
      await escribirUrl(tester, 'http://');
      expect(find.textContaining('Empieza por http://'), findsNothing);
    });
  });

  group('Probar conexión', () {
    Future<void> probar(WidgetTester tester, String url) async {
      await escribirUrl(tester, url);
      await tocar(tester, find.byKey(const Key('boton_probar_servidor')));
    }

    for (final (resultado, mensaje) in [
      (ResultadoPrueba.correcta, 'Conexión correcta'),
      (ResultadoPrueba.tiempoAgotado, 'tardó demasiado'),
      (ResultadoPrueba.sinConexion, 'No se pudo conectar'),
      (ResultadoPrueba.incompatible, 'no es un servidor Brilliant'),
    ]) {
      testWidgets('muestra el resultado ${resultado.name}', (tester) async {
        await abrir(tester);
        await abrirDialogo(tester);
        await probar(tester, ' http://nuevo.test:9000/ ');
        // Se prueba la dirección normalizada y se ve "Probando…".
        expect(pruebas.single.$1.toString(), 'http://nuevo.test:9000');
        expect(find.text('Probando…'), findsOneWidget);
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const Key('boton_probar_servidor')),
              )
              .onPressed,
          isNull,
          reason: 'no se lanzan pruebas duplicadas',
        );
        pruebas.single.$2.complete(
          PruebaServidor(resultado, switch (resultado) {
            ResultadoPrueba.correcta =>
              'Conexión correcta: servidor Brilliant compatible.',
            ResultadoPrueba.tiempoAgotado =>
              'El servidor tardó demasiado en responder.',
            ResultadoPrueba.sinConexion => 'No se pudo conectar.',
            ResultadoPrueba.incompatible =>
              'Respondió algo, pero no es un servidor Brilliant.',
          }),
        );
        await tester.pump();
        expect(find.textContaining(mensaje), findsOneWidget);
        expect(find.text('Probar conexión'), findsOneWidget);
        // Probar no cambia nada por sí solo.
        expect(auth.urlBase.toString(), 'http://viejo.test:8080');
        expect(almacen.valor, isNull);
      });
    }

    testWidgets('un resultado tardío de otra dirección se ignora', (
      tester,
    ) async {
      await abrir(tester);
      await abrirDialogo(tester);
      await probar(tester, 'http://uno.test');
      await escribirUrl(tester, 'http://dos.test'); // cambia la dirección
      pruebas.single.$2.complete(
        const PruebaServidor(ResultadoPrueba.correcta, 'Conexión correcta'),
      );
      await tester.pump();
      expect(find.textContaining('Conexión correcta'), findsNothing);
      expect(find.text('Probar conexión'), findsOneWidget);
    });

    testWidgets('si se prueba otra dirección, vale la última', (tester) async {
      await abrir(tester);
      await abrirDialogo(tester);
      await probar(tester, 'http://uno.test');
      await escribirUrl(tester, 'http://dos.test');
      await tocar(tester, find.byKey(const Key('boton_probar_servidor')));
      expect(pruebas, hasLength(2));
      pruebas[1].$2.complete(
        const PruebaServidor(
          ResultadoPrueba.correcta,
          'Resultado de la prueba B',
        ),
      );
      pruebas[0].$2.complete(
        const PruebaServidor(
          ResultadoPrueba.sinConexion,
          'Resultado de la prueba A',
        ),
      );
      await tester.pump();
      expect(find.textContaining('prueba B'), findsOneWidget);
      expect(find.textContaining('prueba A'), findsNothing);
    });

    testWidgets('un resultado tardío tras cerrar el diálogo no hace nada', (
      tester,
    ) async {
      await abrir(tester);
      await abrirDialogo(tester);
      await probar(tester, 'http://uno.test');
      await tocar(tester, find.byKey(const Key('boton_cancelar_servidor')));
      expect(find.byKey(const Key('campo_url_servidor')), findsNothing);
      pruebas.single.$2.complete(
        const PruebaServidor(ResultadoPrueba.correcta, 'Conexión correcta'),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(auth.urlBase.toString(), 'http://viejo.test:8080');
    });

    testWidgets('un resultado tardío tras guardar no actualiza el diálogo', (
      tester,
    ) async {
      await abrir(tester);
      await abrirDialogo(tester);
      await probar(tester, 'http://uno.test');
      await tocar(tester, find.byKey(const Key('boton_guardar_servidor')));
      expect(find.byKey(const Key('campo_url_servidor')), findsNothing);
      pruebas.single.$2.complete(
        const PruebaServidor(ResultadoPrueba.correcta, 'Conexión correcta'),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('Guardar y cancelar', () {
    testWidgets('cancelar no produce ningún cambio', (tester) async {
      await abrir(tester);
      await abrirDialogo(tester);
      await escribirUrl(tester, 'http://otro.test:1234');
      await tocar(tester, find.byKey(const Key('boton_cancelar_servidor')));
      expect(find.byKey(const Key('campo_url_servidor')), findsNothing);
      expect(auth.urlBase.toString(), 'http://viejo.test:8080');
      expect(config.url.toString(), 'http://viejo.test:8080');
      expect(almacen.valor, isNull);
      expect(textoDe('servidor_actual'), 'Servidor: http://viejo.test:8080');
    });

    testWidgets('guardar normaliza, persiste y actualiza la pantalla', (
      tester,
    ) async {
      await abrir(tester);
      await abrirDialogo(tester);
      await escribirUrl(tester, '  HTTP://192.168.1.77:8080/  ');
      await tocar(tester, find.byKey(const Key('boton_guardar_servidor')));
      expect(find.byKey(const Key('campo_url_servidor')), findsNothing);
      expect(almacen.valor, 'http://192.168.1.77:8080');
      expect(auth.urlBase.toString(), 'http://192.168.1.77:8080');
      expect(textoDe('servidor_actual'), 'Servidor: http://192.168.1.77:8080');
      // Los siguientes accesos van al nuevo servidor.
      await iniciarSesion(tester);
      expect(peticiones.last.url.host, '192.168.1.77');
    });

    testWidgets('guardar la misma dirección no cambia nada', (tester) async {
      await abrir(tester);
      await abrirDialogo(tester);
      await tocar(tester, find.byKey(const Key('boton_guardar_servidor')));
      expect(find.byKey(const Key('campo_url_servidor')), findsNothing);
      expect(almacen.valor, isNull);
    });

    testWidgets('si falla el guardado se avisa y no cambia la dirección', (
      tester,
    ) async {
      almacen.fallaAlGuardar = true;
      await abrir(tester);
      await abrirDialogo(tester);
      await escribirUrl(tester, 'http://otro.test');
      await tocar(tester, find.byKey(const Key('boton_guardar_servidor')));
      expect(find.textContaining('No se pudo guardar'), findsOneWidget);
      expect(auth.urlBase.toString(), 'http://viejo.test:8080');
    });
  });

  group('Con sesión activa', () {
    Future<void> conSesion(WidgetTester tester) async {
      await abrir(tester);
      await iniciarSesion(tester);
      expect(auth.haySesion, isTrue);
    }

    Future<void> abrirDesdeMenu(WidgetTester tester) async {
      await tocar(tester, find.byKey(const Key('menu_cuenta')));
      await tocar(tester, find.byKey(const Key('menu_servidor')));
    }

    testWidgets('cambiar de servidor pide confirmar y cierra la sesión', (
      tester,
    ) async {
      await conSesion(tester);
      await abrirDesdeMenu(tester);
      await escribirUrl(tester, 'http://nuevo.test:8080');
      await tocar(tester, find.byKey(const Key('boton_guardar_servidor')));
      expect(find.text('¿Cambiar de servidor?'), findsOneWidget);
      expect(auth.haySesion, isTrue, reason: 'aún no se confirmó');

      await tocar(tester, find.byKey(const Key('confirmar_si')));
      expect(auth.haySesion, isFalse);
      expect(auth.token, isNull);
      expect(auth.urlBase.toString(), 'http://nuevo.test:8080');
      expect(almacen.valor, 'http://nuevo.test:8080');
      // Se vuelve a la pantalla de acceso con el nuevo servidor.
      expect(find.byKey(const Key('boton_enviar_acceso')), findsOneWidget);
      expect(textoDe('servidor_actual'), 'Servidor: http://nuevo.test:8080');
    });

    testWidgets('rechazar la confirmación deja sesión y servidor intactos', (
      tester,
    ) async {
      await conSesion(tester);
      final token = auth.token;
      await abrirDesdeMenu(tester);
      await escribirUrl(tester, 'http://nuevo.test:8080');
      await tocar(tester, find.byKey(const Key('boton_guardar_servidor')));
      await tocar(tester, find.byKey(const Key('confirmar_no')));
      expect(auth.haySesion, isTrue);
      expect(auth.token, token);
      expect(auth.urlBase.toString(), 'http://viejo.test:8080');
      expect(almacen.valor, isNull);
      // El diálogo sigue abierto y se puede cancelar sin cambios.
      await tocar(tester, find.byKey(const Key('boton_cancelar_servidor')));
      expect(auth.haySesion, isTrue);
    });

    testWidgets('cancelar el diálogo no cierra la sesión', (tester) async {
      await conSesion(tester);
      await abrirDesdeMenu(tester);
      await escribirUrl(tester, 'http://nuevo.test:8080');
      await tocar(tester, find.byKey(const Key('boton_cancelar_servidor')));
      expect(auth.haySesion, isTrue);
      expect(auth.urlBase.toString(), 'http://viejo.test:8080');
    });

    testWidgets('no se pide confirmar si la dirección es la misma', (
      tester,
    ) async {
      await conSesion(tester);
      await abrirDesdeMenu(tester);
      await tocar(tester, find.byKey(const Key('boton_guardar_servidor')));
      expect(find.text('¿Cambiar de servidor?'), findsNothing);
      expect(auth.haySesion, isTrue);
    });
  });

  group('Pantallas pequeñas', () {
    testWidgets('el diálogo con error y resultado no desborda en 320x568', (
      tester,
    ) async {
      await fijarPantalla(tester);
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(AplicacionBrilliant(auth: auth));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await abrirDialogo(tester);
      await escribirUrl(tester, 'http://usuario:clave@muy-largo.example.com');
      await tocar(tester, find.byKey(const Key('boton_guardar_servidor')));
      expect(find.textContaining('usuario ni contraseña'), findsOneWidget);
      await escribirUrl(
        tester,
        'http://un-nombre-de-host-bastante-largo.ejemplo.com:8080/prefijo',
      );
      await tocar(tester, find.byKey(const Key('boton_probar_servidor')));
      pruebas.single.$2.complete(
        const PruebaServidor(
          ResultadoPrueba.sinConexion,
          'No se pudo conectar. Revisa la dirección, que el servidor esté '
          'encendido y que estén en la misma red.',
        ),
      );
      await tester.pump();
      expect(find.textContaining('No se pudo conectar'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Con el teclado abierto los botones siguen alcanzables.
      tester.view.viewInsets = FakeViewPadding(
        bottom: 260 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('boton_guardar_servidor')), findsOneWidget);
    });

    testWidgets('la pantalla de acceso con una dirección larga no desborda', (
      tester,
    ) async {
      final larga = ClienteAuth(
        config: ConfigServidor.fija(
          Uri.parse(
            'https://un-servidor-con-un-nombre-extremadamente-largo.ejemplo.com:8443/prefijo/largo',
          ),
        ),
        cliente: MockClient((_) async => http.Response('{}', 200)),
      );
      await fijarPantalla(tester);
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(AplicacionBrilliant(auth: larga));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('servidor_actual')), findsOneWidget);
    });
  });
}
