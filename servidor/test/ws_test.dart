import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:brilliant_nucleo/brilliant_nucleo.dart';
import 'package:servidor_brilliant/servidor_brilliant.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Cliente de prueba que guarda todo lo que llega.
class Cx {
  Cx(int puerto)
    : ch = WebSocketChannel.connect(Uri.parse('ws://127.0.0.1:$puerto/ws')) {
    ch.stream.listen(
      (d) => recibidos.add((jsonDecode(d as String) as Map).cast()),
      onDone: () => cerrada.complete(),
      onError: (_) {},
    );
  }

  final WebSocketChannel ch;
  final recibidos = <Map<String, Object?>>[];
  final cerrada = Completer<void>();
  int _leidos = 0;

  void enviar(Map<String, Object?> m) => ch.sink.add(jsonEncode(m));

  /// Espera el siguiente mensaje (a partir del último consumido) que cumpla.
  Future<Map<String, Object?>> esperar(
    bool Function(Map<String, Object?>) cumple, {
    String? que,
  }) async {
    final limite = DateTime.now().add(const Duration(seconds: 4));
    while (DateTime.now().isBefore(limite)) {
      while (_leidos < recibidos.length) {
        final m = recibidos[_leidos++];
        if (cumple(m)) return m;
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    throw TimeoutException('No llegó: ${que ?? '?'}. Recibido: $recibidos');
  }

  Future<Map<String, Object?>> tipo(String t) =>
      esperar((m) => m['tipo'] == t, que: t);

  Future<EstadoSala> estado(bool Function(EstadoSala) cumple) async {
    final m = await esperar((m) {
      if (m['tipo'] != MsgServidor.estado) return false;
      return cumple(
        EstadoSala.fromJson((m['sala'] as Map).cast<String, Object?>()),
      );
    }, que: 'estado');
    return EstadoSala.fromJson((m['sala'] as Map).cast<String, Object?>());
  }

  Future<void> cerrar() async {
    await ch.sink.close();
  }
}

void main() {
  late ServicioAuth auth;
  late GestorSalas gestor;
  late HttpServer servidor;
  final abiertas = <Cx>[];

  Cx conectar() {
    final c = Cx(servidor.port);
    abiertas.add(c);
    return c;
  }

  Future<String> token(String correo) async {
    await auth.registrar(correo, 'clave1234');
    return auth.iniciarSesion(correo, 'clave1234');
  }

  Future<void> levantar(Handler Function() crear) async {
    servidor = await io.serve(crear(), InternetAddress.loopbackIPv4, 0);
  }

  setUp(() async {
    auth = ServicioAuth(
      almacen: AlmacenMemoria(),
      secretoJwt: 'secreto-de-prueba-con-mas-de-32-caracteres',
      costoBcrypt: 4,
    );
    gestor = GestorSalas();
  });

  tearDown(() async {
    for (final c in abiertas) {
      unawaited(c.cerrar());
    }
    abiertas.clear();
    gestor.cerrar();
    await servidor.close(force: true);
  });

  group('Con la API completa', () {
    setUp(() => levantar(() => crearApi(auth, gestor: gestor)));

    test('dos jugadores: sala, partida, caída real y vuelta', () async {
      final ta = await token('ana@x.com');
      final tb = await token('beto@x.com');

      final a = conectar()..enviar({'tipo': MsgCliente.auth, 'token': ta});
      await a.tipo(MsgServidor.sinSala);
      a.enviar({'tipo': MsgCliente.crearSala, 'mapa': 1});
      final sala = await a.estado((e) => e.fase == FaseSala.lobby);
      expect(sala.mapa, 1);

      final b = conectar()..enviar({'tipo': MsgCliente.auth, 'token': tb});
      await b.tipo(MsgServidor.sinSala);
      b.enviar({'tipo': MsgCliente.unirse, 'codigo': sala.codigo});
      await b.estado((e) => e.jugadores.length == 2);
      await a.estado((e) => e.jugadores.length == 2);

      a.enviar({'tipo': MsgCliente.empezar});
      final prep = await b.estado((e) => e.fase == FaseSala.preparacion);
      expect(prep.tablero.where((v) => v != null), isEmpty);

      // Cada uno reparte el 1..6 a su manera y confirma.
      final ini = prep.mapaOficial.indicesIniciales;
      for (var k = 0; k < 6; k++) {
        a.enviar({
          'tipo': MsgCliente.colocarInicial,
          'indice': ini[k],
          'numero': k + 1,
        });
        b.enviar({
          'tipo': MsgCliente.colocarInicial,
          'indice': ini[k],
          'numero': 6 - k,
        });
      }
      a.enviar({'tipo': MsgCliente.confirmarDistribucion});
      await b.estado(
        (e) => e.jugador(e.anfitrion)!.estado == EstadoJugador.listo,
      );
      b.enviar({'tipo': MsgCliente.confirmarDistribucion});
      final jugando = await b.estado((e) => e.fase == FaseSala.jugando);
      expect(jugando.tablero.where((v) => v != null), hasLength(6));
      expect([for (final i in ini) jugando.tablero[i]], [6, 5, 4, 3, 2, 1]);

      // Beto pierde la conexión: Ana lo ve caído.
      await b.cerrar();
      final caido = await a.estado((e) => e.jugadores.any((j) => !j.conectado));
      expect(caido.fase, FaseSala.jugando);

      // Beto vuelve con el mismo token y recupera su partida.
      final b2 = conectar()..enviar({'tipo': MsgCliente.auth, 'token': tb});
      final vuelto = await b2.estado((e) => e.fase == FaseSala.jugando);
      expect(vuelto.codigo, sala.codigo);
      expect(vuelto.tablero, jugando.tablero);
      await a.estado((e) => e.jugadores.every((j) => j.conectado));

      // Ana se rinde y ambos lo ven.
      a.enviar({'tipo': MsgCliente.conceder});
      final fin = await b2.estado((e) => e.fase == FaseSala.terminada);
      expect(fin.resultado!.motivo, MotivoFin.rendicion);
      expect(fin.resultado!.ganadores, [fin.yo]);
    });

    test('abrir la sesión en otra pestaña cierra la anterior', () async {
      final t = await token('ana@x.com');
      final vieja = conectar()..enviar({'tipo': MsgCliente.auth, 'token': t});
      await vieja.tipo(MsgServidor.sinSala);
      final nueva = conectar()..enviar({'tipo': MsgCliente.auth, 'token': t});
      await nueva.tipo(MsgServidor.sinSala);
      await vieja.tipo(MsgServidor.sesionReemplazada);
      await vieja.cerrada.future.timeout(const Duration(seconds: 3));
      expect(vieja.ch.closeCode, 4003);
    });

    test('un token falso recibe error fatal y se cierra la conexión', () async {
      final c = conectar()..enviar({'tipo': MsgCliente.auth, 'token': 'a.b.c'});
      final e = await c.tipo(MsgServidor.error);
      expect(e['codigo'], CodigoError.autenticacion);
      expect(e['fatal'], isTrue);
      await c.cerrada.future.timeout(const Duration(seconds: 3));
      expect(c.ch.closeCode, 4001);
    });

    test('lo primero debe ser autenticarse', () async {
      final c = conectar()..enviar({'tipo': MsgCliente.crearSala});
      final e = await c.tipo(MsgServidor.error);
      expect(e['fatal'], isTrue);
      await c.cerrada.future.timeout(const Duration(seconds: 3));
      expect(gestor.totalSalas, 0);
    });

    test('un mensaje inválido da error pero no cierra la conexión', () async {
      final c = conectar()
        ..enviar({'tipo': MsgCliente.auth, 'token': await token('a@x.com')});
      await c.tipo(MsgServidor.sinSala);
      c.ch.sink.add('esto no es json');
      c.ch.sink.add('[1,2,3]');
      final e = await c.tipo(MsgServidor.error);
      expect(e['fatal'], isNull);
      c.enviar({'tipo': MsgCliente.ping});
      await c.tipo(MsgServidor.pong);
    });

    test('un mensaje enorme cierra la conexión', () async {
      final c = conectar()
        ..enviar({'tipo': MsgCliente.auth, 'token': await token('a@x.com')});
      await c.tipo(MsgServidor.sinSala);
      c.ch.sink.add('x' * 10000);
      await c.cerrada.future.timeout(const Duration(seconds: 3));
      expect(c.ch.closeCode, 4009);
    });

    test(
      'la ruta /ws sin ser WebSocket se rechaza sin tumbar el servidor',
      () async {
        final cliente = HttpClient();
        final req = await cliente.get('127.0.0.1', servidor.port, '/ws');
        final resp = await req.close();
        expect(resp.statusCode, 404); // solo atiende peticiones de WebSocket
        await resp.drain<void>();
        cliente.close();
        // El servidor sigue atendiendo.
        final c = conectar()
          ..enviar({'tipo': MsgCliente.auth, 'token': await token('b@x.com')});
        await c.tipo(MsgServidor.sinSala);
      },
    );
  });

  group('Con límites ajustados', () {
    test('sin autenticarse a tiempo se cierra la conexión', () async {
      await levantar(
        () => crearManejadorWs(
          auth,
          gestor,
          plazoAuth: const Duration(milliseconds: 100),
        ),
      );
      final c = conectar();
      final e = await c.tipo(MsgServidor.error);
      expect(e['fatal'], isTrue);
      await c.cerrada.future.timeout(const Duration(seconds: 3));
    });

    test('inundar de mensajes cierra la conexión', () async {
      await levantar(
        () => crearManejadorWs(auth, gestor, maxMensajesPorSegundo: 10),
      );
      final c = conectar()
        ..enviar({'tipo': MsgCliente.auth, 'token': await token('a@x.com')});
      await c.tipo(MsgServidor.sinSala);
      for (var i = 0; i < 40; i++) {
        c.enviar({'tipo': MsgCliente.ping});
      }
      final e = await c.esperar(
        (m) => m['tipo'] == MsgServidor.error,
        que: 'error de límite',
      );
      expect(e['codigo'], CodigoError.limite);
      await c.cerrada.future.timeout(const Duration(seconds: 3));
      expect(c.ch.closeCode, 4002);
    });
  });
}
