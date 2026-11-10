import 'package:dart_package_1/dart_package_1.dart';
import 'package:dart_package_1/online/cliente_multijugador.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import 'ayudas_online.dart';

Future<void> esperar(int ms) =>
    Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late ServidorFalso servidor;
  late ClienteMultijugador cliente;
  ClienteMultijugador? creado;
  String? jwt;
  late List<String> avisos;

  ClienteMultijugador crear({
    int maxIntentos = 10,
    Duration ping = const Duration(minutes: 5),
    Duration silencio = const Duration(minutes: 5),
    Duration espera = const Duration(seconds: 10),
    Duration umbral = const Duration(milliseconds: 30),
  }) {
    avisos = [];
    cliente = ClienteMultijugador(
      url: Uri.parse('ws://localhost:8080/ws'),
      token: () => jwt,
      fabrica: servidor.fabrica,
      intervaloPing: ping,
      silencioMaximo: silencio,
      esperaRespuesta: espera,
      esperasReintento: const [Duration(milliseconds: 20)],
      maxIntentos: maxIntentos,
      umbralSegundoPlano: umbral,
    );
    cliente.avisos.listen(avisos.add);
    creado = cliente;
    return cliente;
  }

  setUp(() {
    servidor = ServidorFalso();
    jwt = 'jwt-de-prueba';
  });

  tearDown(() {
    creado?.dispose();
    creado = null;
  });

  /// Conecta y deja al cliente autenticado y sin sala.
  Future<CanalWsFalso> conectado() async {
    crear();
    cliente.conectar();
    await esperar(5);
    servidor.ultima.servidorEnvia({'tipo': MsgServidor.sinSala});
    await esperar(5);
    return servidor.ultima;
  }

  group('Conexión', () {
    test('se autentica con el token nada más conectar', () async {
      crear();
      cliente.conectar();
      expect(cliente.conexion, EstadoConexion.conectando);
      await esperar(5);
      expect(servidor.ultima.enviados, [
        {'tipo': MsgCliente.auth, 'token': 'jwt-de-prueba'},
      ]);
      expect(cliente.autenticado, isFalse);

      servidor.ultima.servidorEnvia({'tipo': MsgServidor.sinSala});
      await esperar(5);
      expect(cliente.conexion, EstadoConexion.conectado);
      expect(cliente.autenticado, isTrue);
      expect(cliente.sala, isNull);
    });

    test('guarda el estado de la sala que manda el servidor', () async {
      final canal = await conectado();
      canal.servidorEstado(estadoSala());
      await esperar(5);
      expect(cliente.sala!.codigo, 'ABC234');
      expect(cliente.sala!.jugadores, hasLength(2));

      canal.servidorEnvia({'tipo': MsgServidor.sinSala});
      await esperar(5);
      expect(cliente.sala, isNull);
    });

    test('sin sesión no intenta conectar y avisa de que hay que entrar', () {
      jwt = null;
      crear();
      cliente.conectar();
      expect(servidor.conexiones, isEmpty);
      expect(cliente.errorFatal, contains('sesión'));
      expect(cliente.sesionInvalida, isTrue);
    });

    test('un token rechazado es un fallo fatal y no se reintenta', () async {
      crear();
      cliente.conectar();
      await esperar(5);
      servidor.ultima.servidorEnvia({
        'tipo': MsgServidor.error,
        'codigo': CodigoError.autenticacion,
        'mensaje': 'Sesión inválida o expirada.',
        'fatal': true,
      });
      await esperar(80);
      expect(cliente.errorFatal, 'Sesión inválida o expirada.');
      expect(cliente.sesionInvalida, isTrue);
      expect(cliente.conexion, EstadoConexion.desconectado);
      expect(servidor.conexiones, hasLength(1));
    });

    test(
      'abrir la cuenta en otro sitio no provoca una guerra de reconexiones',
      () async {
        final canal = await conectado();
        canal.servidorEnvia({'tipo': MsgServidor.sesionReemplazada});
        canal.servidorCierra();
        await esperar(80);
        expect(cliente.errorFatal, contains('otro lugar'));
        expect(cliente.sesionInvalida, isFalse);
        expect(servidor.conexiones, hasLength(1));
      },
    );

    test('tras un fallo fatal se puede reintentar a mano', () async {
      final canal = await conectado();
      canal.servidorEnvia({'tipo': MsgServidor.sesionReemplazada});
      await esperar(10);
      expect(cliente.errorFatal, isNotNull);
      cliente.conectar();
      expect(cliente.errorFatal, isNull);
      await esperar(5);
      expect(servidor.conexiones, hasLength(2));
    });
  });

  group('Cortes de conexión', () {
    test('si se cae, reconecta solo y recupera la sala', () async {
      final canal = await conectado();
      canal.servidorEstado(
        estadoSala(
          fase: FaseSala.jugando,
          turnoDe: 'b',
          mensaje: 'Antes del corte',
        ),
      );
      await esperar(5);

      canal.servidorCierra();
      await esperar(5);
      expect(cliente.conexion, EstadoConexion.reconectando);
      expect(cliente.intento, 1);
      expect(cliente.sala, isNotNull, reason: 'se conserva la última foto');

      await esperar(60);
      expect(servidor.conexiones, hasLength(2));
      expect(servidor.ultima.enviados.first['tipo'], MsgCliente.auth);

      servidor.ultima.servidorEstado(
        estadoSala(
          fase: FaseSala.jugando,
          turnoDe: 'a',
          turno: 4,
          mensaje: 'Después del corte',
        ),
      );
      await esperar(5);
      expect(cliente.conexion, EstadoConexion.conectado);
      expect(cliente.intento, 0);
      expect(cliente.sala!.turno, 4);
    });

    test('reintenta varias veces si el servidor sigue sin responder', () async {
      final canal = await conectado();
      servidor.fallos = 3;
      canal.servidorCierra();
      await esperar(300);
      expect(servidor.conexiones.length, greaterThanOrEqualTo(4));
      // La cuarta conexión sí funciona.
      servidor.ultima.servidorEnvia({'tipo': MsgServidor.sinSala});
      await esperar(5);
      expect(cliente.conexion, EstadoConexion.conectado);
      expect(cliente.errorFatal, isNull);
    });

    test('se rinde tras demasiados intentos fallidos', () async {
      crear(maxIntentos: 3);
      servidor.fallos = 100;
      cliente.conectar();
      await esperar(300);
      expect(cliente.errorFatal, contains('reconectar'));
      expect(cliente.conexion, EstadoConexion.desconectado);
      expect(servidor.conexiones, hasLength(4)); // 1 inicial + 3 reintentos

      // Y se puede volver a intentar.
      servidor.fallos = 0;
      cliente.conectar();
      await esperar(10);
      servidor.ultima.servidorEnvia({'tipo': MsgServidor.sinSala});
      await esperar(5);
      expect(cliente.conexion, EstadoConexion.conectado);
    });

    test('si el servidor calla demasiado, da la conexión por muerta', () async {
      crear(
        ping: const Duration(milliseconds: 20),
        silencio: const Duration(milliseconds: 70),
      );
      cliente.conectar();
      await esperar(5);
      servidor.ultima.servidorEnvia({'tipo': MsgServidor.sinSala});
      await esperar(45);
      expect(servidor.ultima.tiposEnviados, contains(MsgCliente.ping));

      // Silencio total: ni siquiera pong.
      await esperar(200);
      expect(servidor.conexiones.length, greaterThanOrEqualTo(2));
    });

    test(
      'con respuestas del servidor no se corta aunque pase el tiempo',
      () async {
        crear(
          ping: const Duration(milliseconds: 20),
          silencio: const Duration(milliseconds: 70),
        );
        cliente.conectar();
        await esperar(5);
        final canal = servidor.ultima;
        canal.servidorEnvia({'tipo': MsgServidor.sinSala});
        for (var i = 0; i < 10; i++) {
          await esperar(20);
          canal.servidorEnvia({'tipo': MsgServidor.pong});
        }
        expect(servidor.conexiones, hasLength(1));
        expect(cliente.conexion, EstadoConexion.conectado);
      },
    );

    test('una acción con la conexión caída avisa y no se envía', () async {
      final canal = await conectado();
      canal.servidorCierra();
      await esperar(5);
      expect(cliente.crearSala(0), isFalse);
      await esperar(5);
      expect(avisos.single, contains('Sin conexión'));
      expect(canal.tiposEnviados, [MsgCliente.auth]);
    });

    test('al caerse se libera una acción que esperaba respuesta', () async {
      final canal = await conectado();
      expect(cliente.tirar(), isTrue);
      expect(cliente.esperando, isTrue);
      canal.servidorCierra();
      await esperar(5);
      expect(cliente.esperando, isFalse);
    });
  });

  group('Segundo plano', () {
    Future<CanalWsFalso> enPartida() async {
      final canal = await conectado();
      canal.servidorEstado(estadoSala(fase: FaseSala.jugando, turnoDe: 'a'));
      await esperar(5);
      return canal;
    }

    test(
      'tras un rato en segundo plano, al volver abre otra conexión',
      () async {
        final canal = await enPartida();
        cliente.cicloDeVida(AppLifecycleState.inactive);
        cliente.cicloDeVida(AppLifecycleState.hidden);
        cliente.cicloDeVida(AppLifecycleState.paused);
        await esperar(60);
        cliente.cicloDeVida(AppLifecycleState.resumed);

        expect(cliente.conexion, EstadoConexion.reconectando);
        expect(cliente.sala, isNotNull, reason: 'no se pierde la partida');
        await esperar(5);
        expect(servidor.conexiones, hasLength(2));
        expect(canal.cerradoPorCliente, isTrue);
        expect(servidor.ultima.enviados.first['tipo'], MsgCliente.auth);

        servidor.ultima.servidorEstado(
          estadoSala(fase: FaseSala.jugando, turnoDe: 'b', turno: 7),
        );
        await esperar(5);
        expect(cliente.conexion, EstadoConexion.conectado);
        expect(cliente.sala!.turno, 7);
      },
    );

    test('una pausa breve no reconecta', () async {
      await enPartida();
      cliente.cicloDeVida(AppLifecycleState.paused);
      cliente.cicloDeVida(AppLifecycleState.resumed);
      await esperar(40);
      expect(servidor.conexiones, hasLength(1));
      expect(cliente.conexion, EstadoConexion.conectado);
    });

    test('volver sin haberse ido (solo inactive) no hace nada', () async {
      await enPartida();
      cliente.cicloDeVida(AppLifecycleState.inactive);
      await esperar(60);
      cliente.cicloDeVida(AppLifecycleState.resumed);
      await esperar(20);
      expect(servidor.conexiones, hasLength(1));
    });

    test('si hubo un fallo fatal, volver no reconecta', () async {
      final canal = await enPartida();
      canal.servidorEnvia({'tipo': MsgServidor.sesionReemplazada});
      await esperar(10);
      cliente.cicloDeVida(AppLifecycleState.paused);
      await esperar(60);
      cliente.cicloDeVida(AppLifecycleState.resumed);
      await esperar(40);
      expect(servidor.conexiones, hasLength(1));
      expect(cliente.errorFatal, isNotNull);
    });

    test(
      'si ya estaba reintentando, volver no abre conexiones de más',
      () async {
        crear(umbral: const Duration(milliseconds: 10));
        cliente.conectar();
        await esperar(5);
        servidor.ultima.servidorEnvia({'tipo': MsgServidor.sinSala});
        await esperar(5);
        servidor.ultima.servidorCierra(); // reintento programado a los 20 ms
        await esperar(2);
        cliente.cicloDeVida(AppLifecycleState.paused);
        await esperar(30);
        cliente.cicloDeVida(AppLifecycleState.resumed);
        await esperar(2);
        expect(servidor.conexiones.length, lessThanOrEqualTo(3));
        servidor.ultima.servidorEnvia({'tipo': MsgServidor.sinSala});
        await esperar(60);
        expect(cliente.conexion, EstadoConexion.conectado);
      },
    );

    test(
      'los cuentas atrás usan un reloj propio, no la hora del móvil',
      () async {
        final canal = await enPartida();
        final antes = cliente.desdeUltimoEstado;
        await esperar(40);
        expect(cliente.desdeUltimoEstado, greaterThan(antes));
        canal.servidorEstado(estadoSala(fase: FaseSala.jugando, turnoDe: 'a'));
        await esperar(5);
        expect(
          cliente.desdeUltimoEstado,
          lessThan(const Duration(milliseconds: 30)),
          reason: 'cada estado del servidor reinicia la cuenta',
        );
      },
    );
  });

  group('Acciones', () {
    test('se envía una a la vez hasta recibir respuesta', () async {
      final canal = await conectado();
      expect(cliente.crearSala(2), isTrue);
      expect(cliente.esperando, isTrue);
      expect(cliente.crearSala(2), isFalse);
      expect(canal.enviados.last, {'tipo': MsgCliente.crearSala, 'mapa': 2});
      expect(
        canal.tiposEnviados.where((t) => t == MsgCliente.crearSala),
        hasLength(1),
      );

      canal.servidorEstado(estadoSala());
      await esperar(5);
      expect(cliente.esperando, isFalse);
    });

    test('un error del servidor llega como aviso y libera la acción', () async {
      final canal = await conectado();
      cliente.unirse('ZZZZZZ');
      canal.servidorEnvia({
        'tipo': MsgServidor.error,
        'codigo': CodigoError.generico,
        'mensaje': 'No existe ninguna sala con ese código.',
      });
      await esperar(5);
      expect(avisos, ['No existe ninguna sala con ese código.']);
      expect(cliente.esperando, isFalse);
      expect(cliente.errorFatal, isNull);
    });

    test('si el servidor nunca responde, la acción se libera sola', () async {
      crear(espera: const Duration(milliseconds: 40));
      cliente.conectar();
      await esperar(5);
      servidor.ultima.servidorEnvia({'tipo': MsgServidor.sinSala});
      await esperar(5);
      cliente.tirar();
      expect(cliente.esperando, isTrue);
      await esperar(80);
      expect(cliente.esperando, isFalse);
    });

    test('colocar manda casilla y dado ancla', () async {
      final canal = await conectado();
      cliente.colocar(17, 1);
      expect(canal.enviados.last, {
        'tipo': MsgCliente.colocar,
        'indice': 17,
        'ancla': 1,
      });
    });

    test('perder la sala sin pedirlo (servidor reiniciado) avisa', () async {
      final canal = await conectado();
      canal.servidorEstado(estadoSala());
      await esperar(5);
      canal.servidorCierra();
      await esperar(40);
      servidor.ultima.servidorEnvia({'tipo': MsgServidor.sinSala});
      await esperar(5);
      expect(cliente.sala, isNull);
      expect(avisos.single, contains('Ya no estás en la sala'));
    });

    test('salir por propia voluntad no avisa de ninguna pérdida', () async {
      final canal = await conectado();
      canal.servidorEstado(estadoSala());
      await esperar(5);
      cliente.salirSala();
      canal.servidorEnvia({'tipo': MsgServidor.sinSala});
      await esperar(5);
      expect(cliente.sala, isNull);
      expect(avisos, isEmpty);
    });

    test('la expulsión saca de la sala y avisa', () async {
      final canal = await conectado();
      canal.servidorEstado(estadoSala());
      await esperar(5);
      canal.servidorEnvia({'tipo': MsgServidor.expulsado});
      await esperar(5);
      expect(cliente.sala, isNull);
      expect(avisos.single, contains('sacó'));
    });

    test('datos de sala ilegibles se ignoran sin romper la conexión', () async {
      final canal = await conectado();
      canal.servidorEstado(estadoSala());
      await esperar(5);
      canal.servidorEnvia({
        'tipo': MsgServidor.estado,
        'sala': {'basura': true},
      });
      canal.servidorEnviaTexto('no es json');
      canal.servidorEnviaTexto('[1,2]');
      await esperar(5);
      expect(cliente.sala!.codigo, 'ABC234');
      expect(cliente.conexion, EstadoConexion.conectado);
      expect(avisos, hasLength(1));
    });
  });

  group('Salir', () {
    test('al cerrar estando en una sala avisa al servidor', () async {
      final canal = await conectado();
      canal.servidorEstado(estadoSala());
      await esperar(5);
      cliente.cerrar();
      expect(canal.tiposEnviados.last, MsgCliente.salirSala);
      expect(canal.cerradoPorCliente, isTrue);
      expect(cliente.conexion, EstadoConexion.desconectado);
    });

    test('al cerrar sin sala no envía nada más y no reconecta', () async {
      final canal = await conectado();
      cliente.cerrar();
      canal.servidorCierra();
      await esperar(80);
      expect(canal.tiposEnviados, [MsgCliente.auth]);
      expect(servidor.conexiones, hasLength(1));
    });

    test('cerrar dos veces es inofensivo', () async {
      await conectado();
      cliente.cerrar();
      cliente.cerrar();
    });
  });

  test('la URL del WebSocket sale de la del servidor', () {
    expect(
      urlWebSocket(Uri.parse('http://localhost:8080')).toString(),
      'ws://localhost:8080/ws',
    );
    expect(
      urlWebSocket(Uri.parse('https://juego.example.com/')).toString(),
      'wss://juego.example.com/ws',
    );
  });
}
