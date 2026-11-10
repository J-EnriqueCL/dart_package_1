import 'dart:math';

import 'package:brilliant_nucleo/brilliant_nucleo.dart';
import 'package:servidor_brilliant/servidor_brilliant.dart';
import 'package:test/test.dart';

import 'ayudas.dart';

const _larga = Duration(minutes: 5);

Future<void> esperar(int ms) =>
    Future<void>.delayed(Duration(milliseconds: ms));

/// Un jugador de prueba: su usuario y su conexión actual.
class Jugador {
  Jugador(this.g, String nombre) : usuario = usuarioFalso(nombre) {
    canal = CanalFalso();
    g.conectar(usuario, canal);
  }

  final GestorSalas g;
  final Usuario usuario;
  late CanalFalso canal;

  String get id => usuario.id;
  EstadoSala get estado => canal.estado!;

  void enviar(Map<String, Object?> msg) => g.manejar(id, canal, msg);

  void crearSala({int mapa = 0}) =>
      enviar({'tipo': MsgCliente.crearSala, 'mapa': mapa});
  void unirse(String codigo) =>
      enviar({'tipo': MsgCliente.unirse, 'codigo': codigo});
  void accion(String tipo) => enviar({'tipo': tipo});

  void caer() => g.desconectar(id, canal);

  void volver() {
    canal = CanalFalso();
    g.conectar(usuario, canal);
  }
}

/// Tira y coloca (o pasa si no hay movimientos) en nombre de [j].
void jugarTurno(Jugador j) {
  j.accion(MsgCliente.tirar);
  final e = j.estado;
  final ctl = e.crearControlador();
  for (var pos = 0; pos < 2; pos++) {
    final destinos = ctl.destinosPosibles(
      ancla: e.dados![pos],
      colocar: e.dados![1 - pos],
    );
    if (destinos.isNotEmpty) {
      j.enviar({
        'tipo': MsgCliente.colocar,
        'indice': destinos.first,
        'ancla': pos,
      });
      return;
    }
  }
  j.accion(MsgCliente.pasar);
}

void main() {
  late GestorSalas g;

  GestorSalas nuevo({
    Duration turno = _larga,
    Duration graciaPartida = _larga,
    Duration graciaLobby = _larga,
    int max = 4,
    int fallos = 8,
  }) => g = GestorSalas(
    config: ConfigSalas(
      tiempoTurno: turno,
      graciaPartida: graciaPartida,
      graciaLobby: graciaLobby,
      maxJugadores: max,
      maxFallosUnirse: fallos,
    ),
    azar: Random(7),
  );

  setUp(() => nuevo());
  tearDown(() => g.cerrar());

  /// Ana crea una sala y Beto se une.
  (Jugador, Jugador, String) parejaEnLobby() {
    final ana = Jugador(g, 'ana');
    final beto = Jugador(g, 'beto');
    ana.crearSala();
    final codigo = ana.estado.codigo;
    beto.unirse(codigo);
    return (ana, beto, codigo);
  }

  (Jugador, Jugador) parejaJugando() {
    final (ana, beto, _) = parejaEnLobby();
    ana.accion(MsgCliente.empezar);
    return (ana, beto);
  }

  group('Lobby e invitación', () {
    test('crear sala da un código de 6 caracteres y hace anfitrión', () {
      final ana = Jugador(g, 'ana');
      expect(ana.canal.tipos, [MsgServidor.sinSala]);
      ana.crearSala(mapa: 2);
      final e = ana.estado;
      expect(e.codigo, matches(RegExp(r'^[A-HJKMNP-Z2-9]{6}$')));
      expect(e.fase, FaseSala.lobby);
      expect(e.mapa, 2);
      expect(e.soyAnfitrion, isTrue);
      expect([for (final j in e.jugadores) j.nombre], ['ana']);
      expect(g.totalSalas, 1);
    });

    test('los códigos no se repiten entre salas', () {
      final codigos = <String>{};
      for (var i = 0; i < 50; i++) {
        final j = Jugador(g, 'u$i')..crearSala();
        codigos.add(j.estado.codigo);
      }
      expect(codigos, hasLength(50));
    });

    test('unirse acepta el código en minúsculas, con espacios y guion', () {
      final ana = Jugador(g, 'ana')..crearSala();
      final c = ana.estado.codigo;
      final beto = Jugador(g, 'beto');
      beto.unirse(' ${c.substring(0, 3).toLowerCase()}-${c.substring(3)} ');
      expect(beto.estado.codigo, c);
      expect(ana.estado.jugadores.map((j) => j.nombre), ['ana', 'beto']);
      expect(beto.estado.soyAnfitrion, isFalse);
    });

    test('los nombres repetidos se distinguen', () {
      final ana = Jugador(g, 'ana')..crearSala();
      final otra = Jugador(g, 'ana2');
      // Mismo nombre público con distinto usuario.
      final gemela = Usuario(
        id: 'otra',
        correo: 'ana@otro.com',
        hashContrasena: 'x',
        creado: DateTime(2026),
      );
      final c = CanalFalso();
      g.conectar(gemela, c);
      g.manejar(gemela.id, c, {
        'tipo': MsgCliente.unirse,
        'codigo': ana.estado.codigo,
      });
      expect(c.estado!.jugadores.map((j) => j.nombre), ['ana', 'ana (2)']);
      expect(otra.canal.estado, isNull);
    });

    test('un código inexistente da error', () {
      final beto = Jugador(g, 'beto')..unirse('ZZZZZZ');
      expect(beto.canal.ultimoError, contains('No existe'));
    });

    test('los intentos con códigos erróneos se limitan', () {
      nuevo(fallos: 3);
      final ana = Jugador(g, 'ana')..crearSala();
      final intruso = Jugador(g, 'intruso');
      for (var i = 0; i < 3; i++) {
        intruso.unirse('AAAAA$i');
        expect(intruso.canal.ultimoError, contains('No existe'));
      }
      // Ya bloqueado: ni siquiera el código correcto vale.
      intruso.unirse(ana.estado.codigo);
      expect(intruso.canal.ultimoError, contains('Demasiados'));
      expect(ana.estado.jugadores, hasLength(1));
    });

    test('una sala llena rechaza a más jugadores', () {
      nuevo(max: 2);
      final (_, _, codigo) = parejaEnLobby();
      final caro = Jugador(g, 'caro')..unirse(codigo);
      expect(caro.canal.ultimoError, contains('llena'));
    });

    test('no se puede estar en dos salas a la vez', () {
      final ana = Jugador(g, 'ana')..crearSala();
      final otro = Jugador(g, 'otro')..crearSala();
      ana.crearSala();
      expect(ana.canal.ultimoError, contains('Ya estás en una sala'));
      ana.unirse(otro.estado.codigo);
      expect(ana.canal.ultimoError, contains('otra sala'));
      // Unirse a la propia sala otra vez es inofensivo.
      ana.unirse(ana.estado.codigo);
      expect(ana.estado.jugadores, hasLength(1));
    });

    test('solo el anfitrión elige mapa, expulsa y empieza', () {
      final (ana, beto, _) = parejaEnLobby();
      beto.enviar({'tipo': MsgCliente.elegirMapa, 'mapa': 1});
      expect(beto.canal.ultimoError, contains('anfitrión'));
      beto.enviar({'tipo': MsgCliente.expulsar, 'id': ana.id});
      expect(beto.canal.ultimoError, contains('anfitrión'));
      beto.accion(MsgCliente.empezar);
      expect(beto.canal.ultimoError, contains('anfitrión'));

      ana.enviar({'tipo': MsgCliente.elegirMapa, 'mapa': 3});
      expect(ana.estado.mapa, 3);
      expect(beto.estado.mapa, 3);
      ana.enviar({'tipo': MsgCliente.elegirMapa, 'mapa': 99});
      expect(ana.canal.ultimoError, contains('Mapa inválido'));
      expect(beto.estado.mapa, 3);
    });

    test('no se empieza sin suficientes jugadores ni con alguien caído', () {
      final ana = Jugador(g, 'ana')..crearSala();
      ana.accion(MsgCliente.empezar);
      expect(ana.canal.ultimoError, contains('al menos 2'));

      final beto = Jugador(g, 'beto')..unirse(ana.estado.codigo);
      beto.caer();
      ana.accion(MsgCliente.empezar);
      expect(ana.canal.ultimoError, contains('desconectados'));
      expect(ana.estado.fase, FaseSala.lobby);
    });

    test('expulsar saca al jugador, que puede volver a unirse', () {
      final (ana, beto, codigo) = parejaEnLobby();
      ana.enviar({'tipo': MsgCliente.expulsar, 'id': beto.id});
      expect(beto.canal.tipos, contains(MsgServidor.expulsado));
      expect(ana.estado.jugadores, hasLength(1));
      expect(g.salaDeUsuario(beto.id), isNull);
      beto.unirse(codigo);
      expect(ana.estado.jugadores, hasLength(2));
    });

    test('el anfitrión no puede expulsarse a sí mismo ni a desconocidos', () {
      final (ana, _, _) = parejaEnLobby();
      ana.enviar({'tipo': MsgCliente.expulsar, 'id': ana.id});
      expect(ana.canal.ultimoError, isNotNull);
      ana.enviar({'tipo': MsgCliente.expulsar, 'id': 'nadie'});
      expect(ana.canal.ultimoError, contains('no encontrado'));
    });

    test('si el anfitrión sale, el cargo pasa al siguiente', () {
      final (ana, beto, _) = parejaEnLobby();
      ana.accion(MsgCliente.salirSala);
      expect(ana.canal.tipos.last, MsgServidor.sinSala);
      expect(beto.estado.anfitrion, beto.id);
      expect(beto.estado.jugadores, hasLength(1));
    });

    test('la sala desaparece cuando sale el último', () {
      final (ana, beto, codigo) = parejaEnLobby();
      ana.accion(MsgCliente.salirSala);
      beto.accion(MsgCliente.salirSala);
      expect(g.totalSalas, 0);
      final caro = Jugador(g, 'caro')..unirse(codigo);
      expect(caro.canal.ultimoError, contains('No existe'));
    });

    test('no se puede entrar a una partida ya empezada', () {
      final (ana, _) = parejaJugando();
      final caro = Jugador(g, 'caro')..unirse(ana.estado.codigo);
      expect(caro.canal.ultimoError, contains('ya empezó'));
    });
  });

  group('Partida', () {
    test('empezar reparte tablero y turno; solo juega quien toca', () {
      final (ana, beto) = parejaJugando();
      final e = ana.estado;
      expect(e.fase, FaseSala.jugando);
      expect(e.tablero.where((v) => v != null), hasLength(6));
      expect(e.turnoDe, anyOf(ana.id, beto.id));
      expect(e.segundosTurno, isNotNull);
      expect(beto.estado.tablero, e.tablero);

      final otro = e.turnoDe == ana.id ? beto : ana;
      otro.accion(MsgCliente.tirar);
      expect(otro.canal.ultimoError, 'No es tu turno.');
      expect(otro.estado.dados, isNull);
    });

    test('un turno completo por mensajes cambia el tablero y el turno', () {
      final (ana, beto) = parejaJugando();
      final porId = {ana.id: ana, beto.id: beto};
      final primero = porId[ana.estado.turnoDe]!;

      primero.accion(MsgCliente.tirar);
      final e = primero.estado;
      expect(e.dados, hasLength(2));
      expect(porId[e.turnoDe] == primero, isTrue);
      final rival = primero == ana ? beto : ana;
      expect(rival.estado.dados, e.dados, reason: 'el rival ve los dados');

      final ctl = e.crearControlador();
      final opciones = [
        for (var pos = 0; pos < 2; pos++)
          for (final c in ctl.destinosPosibles(
            ancla: e.dados![pos],
            colocar: e.dados![1 - pos],
          ))
            (pos, c),
      ];
      if (opciones.isEmpty) {
        primero.accion(MsgCliente.pasar);
      } else {
        final (pos, c) = opciones.first;
        primero.enviar({'tipo': MsgCliente.colocar, 'indice': c, 'ancla': pos});
        expect(primero.estado.tablero[c], e.dados![1 - pos]);
      }
      expect(primero.estado.turnoDe, rival.id);
      expect(primero.estado.turno, 2);
      expect(rival.estado.dados, isNull);
    });

    test('mensajes mal formados dan error y no rompen la partida', () {
      final (ana, beto) = parejaJugando();
      final primero = ana.estado.turnoDe == ana.id ? ana : beto;
      primero.accion(MsgCliente.tirar);
      primero.enviar({'tipo': MsgCliente.colocar});
      expect(primero.canal.ultimoError, contains('indice'));
      primero.enviar({'tipo': MsgCliente.colocar, 'indice': 'x', 'ancla': 0});
      expect(primero.canal.ultimoError, contains('indice'));
      primero.enviar({'tipo': MsgCliente.colocar, 'indice': 1.5, 'ancla': 0});
      expect(primero.canal.ultimoError, contains('indice'));
      primero.enviar({'tipo': 'inventado'});
      expect(primero.canal.ultimoError, contains('desconocido'));
      primero.enviar({'tipo': MsgCliente.crearSala, 'mapa': 'uno'});
      expect(primero.canal.ultimoError, isNotNull);
      expect(primero.estado.fase, FaseSala.jugando);
    });

    test('conceder da la victoria al otro y el anfitrión reabre el lobby', () {
      final (ana, beto) = parejaJugando();
      beto.accion(MsgCliente.conceder);
      for (final j in [ana, beto]) {
        final e = j.estado;
        expect(e.fase, FaseSala.terminada);
        expect(e.resultado!.motivo, MotivoFin.rendicion);
        expect(e.resultado!.ganadores, [ana.id]);
        expect(e.jugador(beto.id)!.estado, EstadoJugador.concedio);
        expect(e.turnoDe, isNull);
      }
      beto.accion(MsgCliente.conceder);
      expect(beto.canal.ultimoError, contains('terminó'));

      beto.accion(MsgCliente.volverAlLobby);
      expect(beto.canal.ultimoError, contains('anfitrión'));
      ana.accion(MsgCliente.volverAlLobby);
      expect(ana.estado.fase, FaseSala.lobby);
      expect(beto.estado.fase, FaseSala.lobby);
      expect(ana.estado.jugadores, hasLength(2));
      expect(ana.estado.tablero, isEmpty);
    });

    test('volver al lobby antes de que termine la partida no vale', () {
      final (ana, _) = parejaJugando();
      ana.accion(MsgCliente.volverAlLobby);
      expect(ana.canal.ultimoError, contains('no terminó'));
      expect(ana.estado.fase, FaseSala.jugando);
    });

    test('salir en plena partida equivale a rendirse', () {
      final (ana, beto) = parejaJugando();
      beto.accion(MsgCliente.salirSala);
      expect(beto.canal.tipos.last, MsgServidor.sinSala);
      expect(g.salaDeUsuario(beto.id), isNull);
      final e = ana.estado;
      expect(e.fase, FaseSala.terminada);
      expect(e.resultado!.ganadores, [ana.id]);
      expect(e.jugador(beto.id)!.estado, EstadoJugador.concedio);
      expect(e.jugador(beto.id)!.conectado, isFalse);

      // El que se fue puede abrir otra sala sin problema.
      beto.crearSala();
      expect(beto.estado.jugadores, hasLength(1));

      ana.accion(MsgCliente.salirSala);
      expect(g.totalSalas, 1); // solo la nueva de Beto
    });

    test('con tres jugadores, rendirse no termina la partida', () {
      final (ana, beto, codigo) = parejaEnLobby();
      final caro = Jugador(g, 'caro')..unirse(codigo);
      ana.accion(MsgCliente.empezar);
      caro.accion(MsgCliente.conceder);
      expect(ana.estado.fase, FaseSala.jugando);
      expect(ana.estado.turnoDe, isNot(caro.id));
      beto.accion(MsgCliente.conceder);
      expect(ana.estado.fase, FaseSala.terminada);
      expect(ana.estado.resultado!.ganadores, [ana.id]);
    });

    test('si se rinde el anfitrión, el cargo pasa a un jugador activo', () {
      final (ana, beto, codigo) = parejaEnLobby();
      final caro = Jugador(g, 'caro')..unirse(codigo);
      ana.accion(MsgCliente.empezar);
      ana.accion(MsgCliente.conceder);
      expect(beto.estado.anfitrion, isNot(ana.id));
      expect(beto.estado.jugador(beto.estado.anfitrion)!.activo, isTrue);
      expect(caro.estado.fase, FaseSala.jugando);
    });
  });

  group('Desconexión y reconexión', () {
    test('en el lobby se conserva el sitio si vuelve a tiempo', () async {
      nuevo(graciaLobby: const Duration(milliseconds: 200));
      final (ana, beto, _) = parejaEnLobby();
      beto.caer();
      var vista = ana.estado.jugador(beto.id)!;
      expect(vista.conectado, isFalse);
      expect(vista.graciaRestante, greaterThan(0));

      await esperar(60);
      beto.volver();
      expect(beto.estado.codigo, ana.estado.codigo);
      expect(ana.estado.jugador(beto.id)!.conectado, isTrue);
      await esperar(300); // pasado el plazo original no pasa nada
      expect(ana.estado.jugadores, hasLength(2));
    });

    test('en el lobby se pierde el sitio si no vuelve', () async {
      nuevo(graciaLobby: const Duration(milliseconds: 80));
      final (ana, beto, _) = parejaEnLobby();
      beto.caer();
      await esperar(200);
      expect(ana.estado.jugadores.map((j) => j.id), [ana.id]);
      expect(g.salaDeUsuario(beto.id), isNull);
      beto.volver();
      expect(beto.canal.tipos, [MsgServidor.sinSala]);
    });

    test(
      'si el anfitrión cae en el lobby y no vuelve, otro toma el cargo',
      () async {
        nuevo(graciaLobby: const Duration(milliseconds: 80));
        final (ana, beto, _) = parejaEnLobby();
        ana.caer();
        await esperar(200);
        expect(beto.estado.anfitrion, beto.id);
      },
    );

    test('en partida el rival ve la desconexión y la vuelta', () {
      final (ana, beto) = parejaJugando();
      final tablero = ana.estado.tablero;
      beto.caer();
      final caido = ana.estado.jugador(beto.id)!;
      expect(caido.conectado, isFalse);
      expect(caido.graciaRestante, isNotNull);
      expect(ana.estado.fase, FaseSala.jugando);

      beto.volver();
      final e = beto.estado;
      expect(e.fase, FaseSala.jugando);
      expect(e.tablero, tablero);
      expect(e.yo, beto.id);
      expect(ana.estado.jugador(beto.id)!.conectado, isTrue);
      expect(ana.estado.jugador(beto.id)!.graciaRestante, isNull);
    });

    test('quien vuelve a tiempo conserva sus puntos y su turno', () async {
      nuevo(graciaPartida: const Duration(milliseconds: 300));
      final (ana, beto) = parejaJugando();
      final turno = ana.estado.turnoDe;
      final (caido, otro) = turno == ana.id ? (ana, beto) : (beto, ana);
      caido.caer();
      await esperar(100);
      caido.volver();
      await esperar(400);
      expect(otro.estado.fase, FaseSala.jugando);
      expect(caido.estado.turnoDe, turno);
    });

    test('en partida, no volver a tiempo cuenta como abandono', () async {
      nuevo(graciaPartida: const Duration(milliseconds: 80));
      final (ana, beto) = parejaJugando();
      beto.caer();
      await esperar(200);
      final e = ana.estado;
      expect(e.fase, FaseSala.terminada);
      expect(e.resultado!.motivo, MotivoFin.abandono);
      expect(e.resultado!.ganadores, [ana.id]);
      expect(e.jugador(beto.id)!.estado, EstadoJugador.abandono);
      expect(e.mensaje, contains('Gana ana'));

      // Si Beto vuelve tarde, ya no tiene sala.
      beto.volver();
      expect(beto.canal.tipos, [MsgServidor.sinSala]);
    });

    test(
      'con tres jugadores, el que se pierde no detiene la partida',
      () async {
        nuevo(graciaPartida: const Duration(milliseconds: 80));
        final (ana, beto, codigo) = parejaEnLobby();
        final caro = Jugador(g, 'caro')..unirse(codigo);
        ana.accion(MsgCliente.empezar);
        caro.caer();
        await esperar(200);
        final e = ana.estado;
        expect(e.fase, FaseSala.jugando);
        expect(e.jugador(caro.id)!.estado, EstadoJugador.abandono);
        expect(e.turnoDe, anyOf(ana.id, beto.id));
        expect(beto.estado.fase, FaseSala.jugando);
      },
    );

    test('si todos se desconectan la sala se elimina sin errores', () async {
      nuevo(graciaPartida: const Duration(milliseconds: 60));
      final (ana, beto) = parejaJugando();
      ana.caer();
      beto.caer();
      await esperar(200);
      expect(g.totalSalas, 0);
      expect(g.salaDeUsuario(ana.id), isNull);
    });

    test('un mensaje de una conexión ya caída se ignora', () {
      final (ana, beto) = parejaJugando();
      final vieja = beto.canal;
      beto.caer();
      g.manejar(beto.id, vieja, {'tipo': MsgCliente.conceder});
      expect(ana.estado.fase, FaseSala.jugando);
    });

    test('abrir la cuenta en otro sitio reemplaza la conexión anterior', () {
      final (ana, beto) = parejaJugando();
      final vieja = beto.canal;
      beto.volver(); // segunda conexión de Beto, sin caer la primera
      expect(vieja.tipos, contains(MsgServidor.sesionReemplazada));
      expect(vieja.cerrado, isTrue);
      expect(vieja.codigoCierre, 4003);
      expect(beto.estado.fase, FaseSala.jugando);

      // La conexión vieja ya no manda; si su cierre llega tarde, tampoco
      // cuenta como desconexión del jugador.
      g.manejar(beto.id, vieja, {'tipo': MsgCliente.conceder});
      g.desconectar(beto.id, vieja);
      expect(ana.estado.fase, FaseSala.jugando);
      expect(ana.estado.jugador(beto.id)!.conectado, isTrue);
    });

    test('un usuario sin sala recibe sin_sala al conectar', () {
      final ana = Jugador(g, 'ana');
      expect(ana.canal.tipos, [MsgServidor.sinSala]);
      ana.accion(MsgCliente.tirar);
      expect(ana.canal.ultimoError, contains('ninguna sala'));
    });
  });

  group('Reloj de turno', () {
    test('si no juega, el turno pasa solo', () async {
      nuevo(turno: const Duration(milliseconds: 150));
      final (ana, _) = parejaJugando();
      final primero = ana.estado.turnoDe;
      await esperar(220); // se agota una vez (a los 150 ms), no dos
      expect(ana.estado.turno, greaterThan(1));
      expect(ana.estado.turnoDe, isNot(primero));
      expect(ana.estado.mensaje, contains('Se agotó el tiempo'));
    });

    test('jugar a tiempo reinicia el reloj para el siguiente turno', () async {
      nuevo(turno: const Duration(milliseconds: 300));
      final (ana, beto) = parejaJugando();
      final porId = {ana.id: ana, beto.id: beto};
      await esperar(200);
      jugarTurno(porId[ana.estado.turnoDe]!); // turno 2 empieza a los 200 ms
      expect(ana.estado.turno, 2);
      await esperar(200); // 400 ms: el reloj original ya habría saltado
      expect(ana.estado.turno, 2);
      await esperar(250); // 650 ms > 200 + 300
      expect(ana.estado.turno, greaterThan(2));
    });

    test('los eventos ajenos no alargan el turno', () async {
      nuevo(turno: const Duration(milliseconds: 400));
      final (ana, beto) = parejaJugando();
      final turno = ana.estado.turnoDe;
      final (_, otro) = turno == ana.id ? (ana, beto) : (beto, ana);
      await esperar(200);
      otro.caer();
      otro.volver(); // cada evento difunde estado, pero no reinicia el reloj
      expect(ana.estado.turno, 1);
      await esperar(320); // 520 ms desde el inicio > 400 ms del turno
      expect(ana.estado.turno, 2);
    });

    test('el segundosTurno baja con el tiempo', () async {
      nuevo(turno: const Duration(seconds: 30));
      final (ana, _) = parejaJugando();
      expect(ana.estado.segundosTurno, inInclusiveRange(29, 30));
    });
  });
}
