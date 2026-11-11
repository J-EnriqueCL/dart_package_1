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

  /// Id de la ronda que muestra mi último estado.
  int get ronda => estado.ronda!.id;

  /// Pide lanzar los dados de la ronda actual (o de [de], si se da).
  void tirar({int? de}) =>
      enviar({'tipo': MsgCliente.tirar, 'ronda': de ?? ronda});
  void confirmar(int indice, int ancla, {int? de}) => enviar({
    'tipo': MsgCliente.confirmarJugada,
    'ronda': de ?? ronda,
    'indice': indice,
    'ancla': ancla,
  });
  void pasarRonda({int? de}) =>
      enviar({'tipo': MsgCliente.pasarRonda, 'ronda': de ?? ronda});

  /// Primera jugada posible con los dados actuales: (casilla, ancla).
  (int, int)? jugadaPosible() {
    final e = estado;
    final ctl = e.crearControlador();
    for (var pos = 0; pos < 2; pos++) {
      final d = ctl.destinosPosibles(
        ancla: e.dados![pos],
        colocar: e.dados![1 - pos],
      );
      if (d.isNotEmpty) return (d.first, pos);
    }
    return null;
  }

  /// Pone el 1..6 (o [orden]) en las posiciones iniciales de mi tablero.
  void colocarIniciales({List<int>? orden}) {
    final ini = estado.mapaOficial.indicesIniciales;
    final numeros = orden ?? const [1, 2, 3, 4, 5, 6];
    for (var k = 0; k < ini.length; k++) {
      enviar({
        'tipo': MsgCliente.colocarInicial,
        'indice': ini[k],
        'numero': numeros[k],
      });
    }
  }

  void distribuir({List<int>? orden}) {
    colocarIniciales(orden: orden);
    accion(MsgCliente.confirmarDistribucion);
  }

  void caer() => g.desconectar(id, canal);

  void volver() {
    canal = CanalFalso();
    g.conectar(usuario, canal);
  }
}

/// Resuelve la ronda abierta en nombre de [j]: confirma una jugada si hay y si
/// no, pasa. No hace nada si [j] no está pendiente.
void resolver(Jugador j) {
  final e = j.estado;
  if (!e.estoyPendiente) return;
  final ctl = e.crearControlador();
  for (var pos = 0; pos < 2; pos++) {
    final destinos = ctl.destinosPosibles(
      ancla: e.dados![pos],
      colocar: e.dados![1 - pos],
    );
    if (destinos.isNotEmpty) {
      j.confirmar(destinos.first, pos);
      return;
    }
  }
  j.pasarRonda();
}

/// Una ronda completa: el primero tira y todos los pendientes resuelven.
void jugarRonda(List<Jugador> js) {
  js.first.tirar();
  for (final j in js) {
    resolver(j);
  }
}

void main() {
  late GestorSalas g;

  GestorSalas nuevo({
    Duration ronda = _larga,
    Duration graciaPartida = _larga,
    Duration graciaLobby = _larga,
    int max = maxJugadoresEnLinea,
    int fallos = 8,
    DateTime Function()? ahora,
  }) => g = GestorSalas(
    config: ConfigSalas(
      tiempoRonda: ronda,
      graciaPartida: graciaPartida,
      graciaLobby: graciaLobby,
      maxJugadores: max,
      maxFallosUnirse: fallos,
    ),
    azar: Random(7),
    ahora: ahora,
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

  /// Pareja en la fase de preparación (el anfitrión ya pulsó empezar).
  (Jugador, Jugador) parejaPreparando() {
    final (ana, beto, _) = parejaEnLobby();
    ana.accion(MsgCliente.empezar);
    return (ana, beto);
  }

  (Jugador, Jugador) otraParejaPreparando() {
    final ana = Jugador(g, 'ana2');
    final beto = Jugador(g, 'beto2');
    ana.crearSala();
    beto.unirse(ana.estado.codigo);
    ana.accion(MsgCliente.empezar);
    return (ana, beto);
  }

  /// Pareja ya jugando: ambos confirmaron su distribución.
  (Jugador, Jugador) parejaJugando() {
    final (ana, beto) = parejaPreparando();
    ana.distribuir();
    beto.distribuir(orden: const [6, 5, 4, 3, 2, 1]);
    return (ana, beto);
  }

  group('Lobby e invitación', () {
    test('crear sala da un código de 6 caracteres y hace anfitrión', () {
      final ana = Jugador(g, 'ana');
      expect(ana.canal.tipos, [MsgServidor.sinSala]);
      ana.crearSala();
      final e = ana.estado;
      expect(e.codigo, matches(RegExp(r'^[A-HJKMNP-Z2-9]{6}$')));
      expect(e.fase, FaseSala.lobby);
      expect(e.mapa, 0);
      expect(e.maxJugadores, 5);
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

      ana.enviar({'tipo': MsgCliente.elegirMapa, 'mapa': 0});
      expect(ana.estado.mapa, 0);
      // Los niveles 2, 3 y 4 no están disponibles en línea todavía.
      for (final m in [1, 2, 3]) {
        ana.enviar({'tipo': MsgCliente.elegirMapa, 'mapa': m});
        expect(ana.canal.ultimoError, contains('no está disponible'));
      }
      ana.enviar({'tipo': MsgCliente.elegirMapa, 'mapa': 99});
      expect(ana.canal.ultimoError, contains('Mapa inválido'));
      expect(beto.estado.mapa, 0);
      Jugador(g, 'otro').crearSala(mapa: 2);
      expect(g.salaDeUsuario(usuarioFalso('otro').id), isNull);
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
    test(
      'al confirmar todos: ronda 1 esperando tirada, cada uno ve lo suyo',
      () {
        final (ana, beto) = parejaJugando();
        final e = ana.estado;
        expect(e.fase, FaseSala.jugando);
        expect(e.tablero.where((v) => v != null), hasLength(6));
        expect(e.ronda!.id, 1);
        expect(e.ronda!.fase, FaseRonda.esperandoTirada);
        expect(e.dados, isNull, reason: 'no se tira nada automáticamente');
        expect(e.ronda!.segundos, isNull);
        expect(e.ronda!.resoluciones, isEmpty);
        expect(ana.estado.puedoTirar && beto.estado.puedoTirar, isTrue);
        final ini = e.mapaOficial.indicesIniciales;
        expect([for (final i in ini) e.tablero[i]], [1, 2, 3, 4, 5, 6]);
        expect(
          [for (final i in ini) beto.estado.tablero[i]],
          [6, 5, 4, 3, 2, 1],
          reason: 'Beto repartió distinto y solo ve el suyo',
        );
      },
    );

    test('cualquiera puede tirar; todos reciben los mismos dados', () {
      final (ana, beto) = parejaJugando();
      beto.tirar(); // no es el anfitrión: no importa
      final d = beto.estado.dados!;
      expect(d, hasLength(2));
      expect(ana.estado.dados, d);
      expect(ana.estado.ronda!.fase, FaseRonda.resolviendo);
      expect(ana.estado.ronda!.resoluciones, {
        ana.id: Resolucion.pendiente,
        beto.id: Resolucion.pendiente,
      });
      expect(ana.estado.ronda!.segundos, isNotNull);
      expect(ana.estado.puedoTirar, isFalse);
    });

    test('dos solicitudes de tirada seguidas generan una sola tirada', () {
      final (ana, beto) = parejaJugando();
      ana.tirar();
      final d = ana.estado.dados;
      beto.tirar(); // llega con la ronda ya abierta: no hace nada
      ana.tirar();
      expect(ana.estado.dados, d);
      expect(beto.estado.dados, d);
      expect(beto.canal.ultimoError, isNull);
      expect(ana.estado.ronda!.id, 1);
    });

    test(
      'una ronda: todos confirman o pasan, y la siguiente espera tirada',
      () {
        final (ana, beto) = parejaJugando();
        ana.tirar();
        final antesBeto = beto.estado.tablero;
        final jugada = ana.jugadaPosible();
        if (jugada == null) {
          ana.pasarRonda();
        } else {
          ana.confirmar(jugada.$1, jugada.$2);
          expect(
            ana.estado.tablero[jugada.$1],
            ana.estado.dados![1 - jugada.$2],
          );
        }
        expect(
          ana.estado.miResolucion,
          anyOf(Resolucion.confirmo, Resolucion.paso),
        );
        expect(beto.estado.miResolucion, Resolucion.pendiente);
        expect(beto.estado.tablero, antesBeto, reason: 'tablero ajeno intacto');
        expect(
          beto.estado.ronda!.fase,
          FaseRonda.resolviendo,
          reason: 'falta Beto',
        );
        expect(ana.estado.ronda!.pendientes, [beto.id]);

        beto.pasarRonda();
        for (final j in [ana, beto]) {
          final r = j.estado.ronda!;
          expect(r.id, 2);
          expect(r.fase, FaseRonda.esperandoTirada);
          expect(r.dados, isNull);
          expect(r.segundos, isNull);
          expect(r.resoluciones, isEmpty);
        }
      },
    );

    test(
      'se puede pasar aunque haya jugadas, y confirmar tras pasar no vale',
      () {
        final (ana, beto) = parejaJugando();
        ana.tirar();
        final jugada = beto.jugadaPosible();
        ana.pasarRonda();
        expect(ana.estado.miResolucion, Resolucion.paso);
        if (jugada != null) {
          ana.confirmar(jugada.$1, jugada.$2);
          expect(ana.canal.ultimoError, contains('pasaste'));
          expect(ana.estado.tablero.where((v) => v != null), hasLength(6));
        }
      },
    );

    test(
      'resolver dos veces o con acciones contradictorias no cambia nada',
      () {
        final (ana, beto) = parejaJugando();
        ana.tirar();
        final jugada = ana.jugadaPosible()!;
        ana.confirmar(jugada.$1, jugada.$2);
        final tablero = ana.estado.tablero;
        final puntos = ana.estado.miJugador!.puntos;
        ana.confirmar(jugada.$1, jugada.$2); // duplicado
        ana.confirmar(jugada.$1, 1 - jugada.$2); // otra jugada
        ana.pasarRonda(); // contradictorio
        expect(ana.canal.ultimoError, contains('confirmaste'));
        expect(ana.estado.tablero, tablero);
        expect(ana.estado.miJugador!.puntos, puntos);
        expect(ana.estado.miResolucion, Resolucion.confirmo);

        beto.pasarRonda();
        beto.pasarRonda(de: 1); // duplicado con la ronda ya cerrada
        expect(beto.canal.ultimoError, contains('ronda'));
        expect(beto.estado.ronda!.id, 2, reason: 'se cerró una sola vez');
      },
    );

    test('las acciones de una ronda anterior se rechazan', () {
      final (ana, beto) = parejaJugando();
      jugarRonda([ana, beto]);
      expect(ana.estado.ronda!.id, 2);
      ana.tirar(de: 1);
      expect(ana.canal.ultimoError, contains('ronda'));
      expect(ana.estado.dados, isNull);
      ana.pasarRonda(de: 1);
      expect(ana.canal.ultimoError, contains('ronda'));
      ana.tirar(de: 7); // de una ronda que aún no existe
      expect(ana.canal.ultimoError, contains('ronda'));
      expect(ana.estado.ronda!.fase, FaseRonda.esperandoTirada);
    });

    test('un error reenvía el estado real al que estaba desactualizado', () {
      final (ana, beto) = parejaJugando();
      jugarRonda([ana, beto]);
      final antes = ana.canal.recibidos.length;
      ana.tirar(de: 1);
      final nuevos = ana.canal.recibidos.skip(antes).toList();
      expect(nuevos.map((m) => m['tipo']), [
        MsgServidor.estado,
        MsgServidor.error,
      ]);
    });

    test('sin tirada previa no se puede confirmar ni pasar', () {
      final (ana, _) = parejaJugando();
      ana.pasarRonda();
      expect(ana.canal.ultimoError, contains('dados'));
      ana.confirmar(1, 0);
      expect(ana.canal.ultimoError, contains('dados'));
      expect(ana.estado.dados, isNull);
    });

    test('mensajes mal formados dan error y no rompen la partida', () {
      final (ana, _) = parejaJugando();
      ana.tirar();
      ana.enviar({'tipo': MsgCliente.confirmarJugada});
      expect(ana.canal.ultimoError, contains('ronda'));
      ana.enviar({'tipo': MsgCliente.confirmarJugada, 'ronda': 1});
      expect(ana.canal.ultimoError, contains('indice'));
      ana.enviar({
        'tipo': MsgCliente.confirmarJugada,
        'ronda': 1,
        'indice': 'x',
        'ancla': 0,
      });
      expect(ana.canal.ultimoError, contains('indice'));
      ana.enviar({
        'tipo': MsgCliente.confirmarJugada,
        'ronda': 1.5,
        'indice': 1,
        'ancla': 0,
      });
      expect(ana.canal.ultimoError, contains('ronda'));
      ana.enviar({'tipo': MsgCliente.pasarRonda, 'ronda': '1'});
      expect(ana.canal.ultimoError, contains('ronda'));
      ana.enviar({'tipo': 'inventado'});
      expect(ana.canal.ultimoError, contains('desconocido'));
      ana.enviar({'tipo': MsgCliente.crearSala, 'mapa': 'uno'});
      expect(ana.canal.ultimoError, isNotNull);
      expect(ana.estado.fase, FaseSala.jugando);
      expect(ana.estado.miResolucion, Resolucion.pendiente);
    });

    test('un dado enviado por el cliente no se usa', () {
      final (ana, _) = parejaJugando();
      ana.enviar({
        'tipo': MsgCliente.tirar,
        'ronda': 1,
        'dados': [6, 6],
        'dado': 6,
      });
      expect(ana.estado.dados, hasLength(2));
      // (con azar real casi nunca salen justo [6, 6]; basta con que se ignore
      // el campo: el servidor no lo lee).
      expect(ana.canal.ultimoError, isNull);
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
        expect(e.ronda, isNull);
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
      for (final j in [ana, beto, caro]) {
        j.distribuir();
      }
      caro.accion(MsgCliente.conceder);
      expect(ana.estado.fase, FaseSala.jugando);
      ana.tirar();
      expect(
        ana.estado.ronda!.resoluciones.keys,
        isNot(contains(caro.id)),
        reason: 'el rendido no debe resolver rondas',
      );
      caro.tirar();
      expect(caro.canal.ultimoError, isNotNull);
      beto.accion(MsgCliente.conceder);
      expect(ana.estado.fase, FaseSala.terminada);
      expect(ana.estado.resultado!.ganadores, [ana.id]);
    });

    test('si se rinde el anfitrión, el cargo pasa a un jugador activo', () {
      final (ana, beto, codigo) = parejaEnLobby();
      final caro = Jugador(g, 'caro')..unirse(codigo);
      ana.accion(MsgCliente.empezar);
      for (final j in [ana, beto, caro]) {
        j.distribuir();
      }
      ana.accion(MsgCliente.conceder);
      expect(beto.estado.anfitrion, isNot(ana.id));
      expect(beto.estado.jugador(beto.estado.anfitrion)!.participa, isTrue);
      expect(caro.estado.fase, FaseSala.jugando);
    });
  });

  group('Preparación', () {
    test('empezar abre la preparación: tablero propio vacío y sin turno', () {
      final (ana, beto) = parejaPreparando();
      for (final j in [ana, beto]) {
        final e = j.estado;
        expect(e.fase, FaseSala.preparacion);
        expect(e.tablero, hasLength(49));
        expect(e.tablero.where((v) => v != null), isEmpty);
        expect(e.numerosPorColocar, [1, 2, 3, 4, 5, 6]);
        expect(e.ronda, isNull);
        expect(e.dados, isNull);
        for (final x in e.jugadores) {
          expect(x.estado, EstadoJugador.preparando);
        }
      }
    });

    test('colocar, retirar y confirmar por mensajes; cada uno ve lo suyo', () {
      final (ana, beto) = parejaPreparando();
      final ini = ana.estado.mapaOficial.indicesIniciales;
      ana.enviar({
        'tipo': MsgCliente.colocarInicial,
        'indice': ini[0],
        'numero': 4,
      });
      expect(ana.estado.tablero[ini[0]], 4);
      expect(ana.estado.numerosPorColocar, [1, 2, 3, 5, 6]);
      expect(beto.estado.tablero[ini[0]], isNull, reason: 'tablero ajeno');
      ana.enviar({'tipo': MsgCliente.quitarInicial, 'indice': ini[0]});
      expect(ana.estado.tablero[ini[0]], isNull);
      expect(ana.estado.numerosPorColocar, [1, 2, 3, 4, 5, 6]);

      ana.distribuir(orden: const [3, 1, 2, 6, 5, 4]);
      expect(ana.estado.miJugador!.estado, EstadoJugador.listo);
      expect(beto.estado.jugador(ana.id)!.estado, EstadoJugador.listo);
      expect(beto.estado.jugador(beto.id)!.estado, EstadoJugador.preparando);
      expect(beto.estado.fase, FaseSala.preparacion);
    });

    test('un mensaje con otro id no toca el tablero de otro jugador', () {
      final (ana, beto) = parejaPreparando();
      final ini = ana.estado.mapaOficial.indicesIniciales;
      ana.enviar({
        'tipo': MsgCliente.colocarInicial,
        'indice': ini[0],
        'numero': 2,
        'id': beto.id,
        'yo': beto.id,
      });
      expect(ana.estado.tablero[ini[0]], 2);
      expect(beto.estado.tablero[ini[0]], isNull);
    });

    test('valores inválidos se rechazan con error y sin cambios', () {
      final (ana, _) = parejaPreparando();
      final ini = ana.estado.mapaOficial.indicesIniciales;
      for (final msg in <Map<String, Object?>>[
        {'indice': ini[0], 'numero': 0},
        {'indice': ini[0], 'numero': 7},
        {'indice': ini[0], 'numero': 2.5},
        {'indice': ini[0], 'numero': '3'},
        {'indice': ini[0], 'numero': null},
        {'indice': ini[0]},
        {'indice': 0, 'numero': 3},
        {'indice': 49, 'numero': 3},
        {'indice': -4, 'numero': 3},
        {'indice': 1.5, 'numero': 3},
        {'numero': 3},
      ]) {
        ana.enviar({'tipo': MsgCliente.colocarInicial, ...msg});
        expect(ana.canal.ultimoError, isNotNull, reason: '$msg');
      }
      expect(ana.estado.tablero.where((v) => v != null), isEmpty);
      ana.accion(MsgCliente.confirmarDistribucion);
      expect(ana.canal.ultimoError, contains('Faltan 6'));
      expect(ana.estado.miJugador!.estado, EstadoJugador.preparando);
    });

    test('no valen jugadas normales ni cambios tras confirmar', () {
      final (ana, beto) = parejaPreparando();
      ana.distribuir();
      for (final tipo in [MsgCliente.tirar, MsgCliente.pasarRonda]) {
        ana.enviar({'tipo': tipo, 'ronda': 1});
        expect(ana.canal.ultimoError, isNotNull);
      }
      ana.enviar({
        'tipo': MsgCliente.confirmarJugada,
        'ronda': 1,
        'indice': 1,
        'ancla': 0,
      });
      expect(ana.canal.ultimoError, isNotNull);
      final ini = ana.estado.mapaOficial.indicesIniciales;
      ana.enviar({'tipo': MsgCliente.quitarInicial, 'indice': ini[0]});
      expect(ana.canal.ultimoError, contains('confirmada'));
      expect(ana.estado.tablero[ini[0]], 1);
      beto.enviar({'tipo': MsgCliente.tirar, 'ronda': 1});
      expect(beto.canal.ultimoError, isNotNull);
    });

    test('la partida empieza una vez, en "esperando tirada", al confirmar el último', () {
      final (ana, beto) = parejaPreparando();
      ana.distribuir();
      expect(ana.estado.fase, FaseSala.preparacion);
      expect(ana.estado.ronda, isNull);
      beto.distribuir();
      final e = ana.estado;
      expect(e.fase, FaseSala.jugando);
      expect(e.ronda!.fase, FaseRonda.esperandoTirada);
      expect(e.ronda!.segundos, isNull);
      // Mensajes repetidos de confirmación no reinician nada.
      ana.accion(MsgCliente.confirmarDistribucion);
      beto.accion(MsgCliente.confirmarDistribucion);
      expect(ana.estado.ronda!.id, 1);
      expect(ana.estado.fase, FaseSala.jugando);
    });

    test(
      'no corre ningún plazo durante la preparación ni esperando tirada',
      () async {
        nuevo(ronda: const Duration(milliseconds: 80));
        final (ana, beto) = parejaPreparando();
        ana.distribuir();
        await esperar(250);
        expect(ana.estado.fase, FaseSala.preparacion);
        expect(ana.estado.mensaje, isNot(contains('Se agotó')));
        beto.distribuir();
        expect(ana.estado.fase, FaseSala.jugando);
        await esperar(250);
        expect(ana.estado.ronda!.id, 1);
        expect(ana.estado.ronda!.fase, FaseRonda.esperandoTirada);
        expect(ana.estado.mensaje, isNot(contains('Se agotó')));
      },
    );

    test('reconectar restaura una preparación incompleta', () {
      final (ana, beto) = parejaPreparando();
      final ini = beto.estado.mapaOficial.indicesIniciales;
      beto.enviar({
        'tipo': MsgCliente.colocarInicial,
        'indice': ini[2],
        'numero': 5,
      });
      beto.enviar({
        'tipo': MsgCliente.colocarInicial,
        'indice': ini[4],
        'numero': 1,
      });
      final antes = beto.estado.tablero;
      beto.caer();
      final caido = ana.estado.jugador(beto.id)!;
      expect(caido.conectado, isFalse);
      expect(
        caido.estado,
        EstadoJugador.preparando,
        reason: 'sigue participando',
      );
      beto.volver();
      final e = beto.estado;
      expect(e.fase, FaseSala.preparacion);
      expect(e.tablero, antes);
      expect(e.numerosPorColocar, [2, 3, 4, 6]);
      expect(e.miJugador!.estado, EstadoJugador.preparando);
    });

    test('reconectar conserva una preparación confirmada', () {
      final (ana, beto) = parejaPreparando();
      beto.distribuir(orden: const [2, 4, 6, 1, 3, 5]);
      final antes = beto.estado.tablero;
      beto.caer();
      expect(ana.estado.jugador(beto.id)!.estado, EstadoJugador.listo);
      beto.volver();
      expect(beto.estado.tablero, antes);
      expect(beto.estado.miJugador!.estado, EstadoJugador.listo);
      // Y sigue sin poder cambiarla ni reenviarla para empezar antes.
      beto.accion(MsgCliente.confirmarDistribucion);
      expect(beto.estado.fase, FaseSala.preparacion);
      ana.distribuir();
      expect(ana.estado.fase, FaseSala.jugando);
      expect(beto.estado.tablero, antes);
    });

    test('rendirse o salir en la preparación deja ganar al único restante', () {
      final (ana, beto) = parejaPreparando();
      ana.distribuir();
      beto.accion(MsgCliente.conceder);
      final e = ana.estado;
      expect(e.fase, FaseSala.terminada);
      expect(e.resultado!.ganadores, [ana.id]);
      expect(e.resultado!.motivo, MotivoFin.rendicion);
      expect(e.jugador(beto.id)!.estado, EstadoJugador.concedio);

      final (c, d) = otraParejaPreparando();
      d.accion(MsgCliente.salirSala);
      expect(c.estado.fase, FaseSala.terminada);
      expect(c.estado.resultado!.ganadores, [c.id]);
    });

    test('con tres, rendirse en la preparación no impide empezar sin él', () {
      final (ana, beto, codigo) = parejaEnLobby();
      final caro = Jugador(g, 'caro')..unirse(codigo);
      ana.accion(MsgCliente.empezar);
      ana.distribuir();
      beto.distribuir();
      expect(ana.estado.fase, FaseSala.preparacion);
      caro.accion(MsgCliente.conceder);
      final e = ana.estado;
      expect(e.fase, FaseSala.jugando);
      expect(e.jugador(caro.id)!.estado, EstadoJugador.concedio);
      expect(e.ronda!.fase, FaseRonda.esperandoTirada);
    });

    test('no volver a tiempo en la preparación cuenta como abandono', () async {
      nuevo(graciaPartida: const Duration(milliseconds: 80));
      final (ana, beto) = parejaPreparando();
      ana.distribuir();
      beto.caer();
      await esperar(200);
      final e = ana.estado;
      expect(e.fase, FaseSala.terminada);
      expect(e.resultado!.motivo, MotivoFin.abandono);
      expect(e.resultado!.ganadores, [ana.id]);
      expect(e.jugador(beto.id)!.estado, EstadoJugador.abandono);
    });

    test('con tres, el que no vuelve no bloquea el inicio', () async {
      nuevo(graciaPartida: const Duration(milliseconds: 80));
      final (ana, beto, codigo) = parejaEnLobby();
      final caro = Jugador(g, 'caro')..unirse(codigo);
      ana.accion(MsgCliente.empezar);
      ana.distribuir();
      beto.distribuir();
      caro.caer();
      await esperar(200);
      final e = ana.estado;
      expect(e.fase, FaseSala.jugando);
      expect(e.jugador(caro.id)!.estado, EstadoJugador.abandono);
    });

    test('quien aún no confirma bloquea el inicio hasta que lo haga', () async {
      final (ana, beto) = parejaPreparando();
      ana.distribuir();
      await esperar(120);
      expect(ana.estado.fase, FaseSala.preparacion);
      expect(ana.estado.jugador(beto.id)!.estado, EstadoJugador.preparando);
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
      final tablero = beto.estado.tablero;
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

    test('quien vuelve a tiempo conserva sus puntos y la ronda', () async {
      nuevo(graciaPartida: const Duration(milliseconds: 300));
      final (ana, beto) = parejaJugando();
      ana.tirar();
      final dados = ana.estado.dados;
      beto.caer();
      await esperar(100);
      beto.volver();
      await esperar(400);
      expect(ana.estado.fase, FaseSala.jugando);
      expect(beto.estado.ronda!.id, 1);
      expect(beto.estado.dados, dados, reason: 'no se vuelve a tirar');
      expect(beto.estado.miResolucion, Resolucion.pendiente);
    });

    test(
      'reconectar conserva dados, resolución y plazo sin reiniciarlo',
      () async {
        nuevo(ronda: const Duration(seconds: 30));
        final (ana, beto) = parejaJugando();
        ana.tirar();
        await esperar(1100);
        final antes = ana.estado.ronda!.segundos!;
        final dados = ana.estado.dados;
        final jugada = beto.jugadaPosible();
        if (jugada == null) {
          beto.pasarRonda();
        } else {
          beto.confirmar(jugada.$1, jugada.$2);
        }
        final resolucion = beto.estado.miResolucion;
        final tablero = beto.estado.tablero;
        beto.caer();
        beto.volver();
        final e = beto.estado;
        expect(e.dados, dados);
        expect(e.miResolucion, resolucion);
        expect(e.tablero, tablero);
        expect(e.ronda!.segundos, lessThanOrEqualTo(antes));
        expect(e.ronda!.segundos, greaterThan(antes - 3));
        // Tras reconectar sigue sin poder resolver otra vez.
        beto.pasarRonda();
        expect(beto.estado.miResolucion, resolucion);
        expect(ana.estado.ronda!.id, 1, reason: 'la ronda sigue abierta (Ana)');
      },
    );

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
        for (final j in [ana, beto, caro]) {
          j.distribuir();
        }
        caro.caer();
        await esperar(200);
        final e = ana.estado;
        expect(e.fase, FaseSala.jugando);
        expect(e.jugador(caro.id)!.estado, EstadoJugador.abandono);
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

  group('Rendición, desconexión, abandono y terminado', () {
    test('las cuatro situaciones se distinguen en el estado', () {
      final (ana, beto, codigo) = parejaEnLobby();
      final caro = Jugador(g, 'caro')..unirse(codigo);
      final dani = Jugador(g, 'dani')..unirse(codigo);
      ana.accion(MsgCliente.empezar);
      for (final j in [ana, beto, caro, dani]) {
        j.distribuir();
      }
      final sala = g.sala(codigo)!;

      // Terminado: tablero sin jugadas posibles (preparado a mano) y se
      // evalúa al cerrar la ronda.
      bloquear(sala.partida!.jugador(dani.id)!, Random(3));
      jugarRonda([ana, beto, caro, dani]);

      beto.accion(MsgCliente.conceder); // rendición explícita
      caro.caer(); // desconexión temporal con gracia vigente
      dani.caer(); // el terminado también puede perder la conexión

      final e = ana.estado;
      final b = e.jugador(beto.id)!;
      final c = e.jugador(caro.id)!;
      final d = e.jugador(dani.id)!;
      expect(
        (b.estado, b.conectado, b.participa),
        (EstadoJugador.concedio, true, false),
        reason: 'Rendido: sigue conectado pero ya no puede ganar',
      );
      expect(c.estado, anyOf(EstadoJugador.jugando, EstadoJugador.terminado));
      expect(c.conectado, isFalse);
      expect(c.graciaRestante, greaterThan(0));
      expect(c.participa, isTrue, reason: 'en gracia sigue participando');
      expect(
        (d.estado, d.conectado, d.participa),
        (EstadoJugador.terminado, false, true),
        reason: 'Terminado: elegible aunque esté sin conexión',
      );
      expect(e.fase, FaseSala.jugando);
    });

    test(
      'abandono confirmado: al vencer la gracia queda como abandonó',
      () async {
        nuevo(graciaPartida: const Duration(milliseconds: 60));
        final (ana, beto, codigo) = parejaEnLobby();
        final caro = Jugador(g, 'caro')..unirse(codigo);
        ana.accion(MsgCliente.empezar);
        for (final j in [ana, beto, caro]) {
          j.distribuir();
        }
        caro.caer();
        expect(
          ana.estado.jugador(caro.id)!.estado,
          isNot(EstadoJugador.abandono),
        );
        await esperar(160);
        final c = ana.estado.jugador(caro.id)!;
        expect(c.estado, EstadoJugador.abandono);
        expect(c.participa, isFalse);
        expect(
          ana.estado.fase,
          FaseSala.jugando,
          reason: 'quedan dos elegibles',
        );
      },
    );

    for (final orden in [(0, 1), (1, 0)]) {
      test(
        'dos desconectados con el plazo vencido: sin ganador, '
        'sea cual sea el temporizador que salte primero (orden $orden)',
        () async {
          var reloj = DateTime(2026, 1, 1);
          nuevo(
            graciaPartida: const Duration(milliseconds: 50),
            ahora: () => reloj,
          );
          final (ana, beto, codigo) = parejaEnLobby();
          ana.accion(MsgCliente.empezar);
          ana.distribuir();
          beto.distribuir();
          final sala = g.sala(codigo)!;
          final jugadores = [ana, beto];

          // Los dos pierden la conexión en el mismo instante, en este orden.
          jugadores[orden.$1].caer();
          jugadores[orden.$2].caer();
          // Cuando salte el primer temporizador, ambos plazos ya vencieron.
          reloj = reloj.add(const Duration(seconds: 10));
          await esperar(200);

          final p = sala.partida!;
          expect(p.terminada, isTrue);
          expect(p.resultado!.ganadores, isEmpty);
          expect(p.resultado!.motivo, MotivoFin.abandono);
          expect(p.jugador(ana.id)!.estado, EstadoJugador.abandono);
          expect(p.jugador(beto.id)!.estado, EstadoJugador.abandono);
          expect(
            p.mensaje,
            'ana y beto se desconectaron y no volvieron. Nadie gana.',
          );
          expect(g.totalSalas, 0);
        },
      );
    }

    test('quien sigue dentro de su plazo no se convierte en abandonado', () async {
      var reloj = DateTime(2026, 1, 1);
      nuevo(
        graciaPartida: const Duration(milliseconds: 300),
        ahora: () => reloj,
      );
      final (ana, beto, codigo) = parejaEnLobby();
      ana.accion(MsgCliente.empezar);
      ana.distribuir();
      beto.distribuir();
      final sala = g.sala(codigo)!;

      ana.caer(); // su plazo vence a los 300 ms
      await esperar(150);
      reloj = reloj.add(const Duration(milliseconds: 150));
      beto.caer(); // su plazo vence a los 450 ms
      // Cuando salte el temporizador de Ana, la referencia es +310 ms: el plazo
      // de Ana venció y el de Beto no.
      reloj = reloj.add(const Duration(milliseconds: 160));
      await esperar(230);

      final p = sala.partida!;
      expect(p.jugador(ana.id)!.estado, EstadoJugador.abandono);
      expect(
        p.jugador(beto.id)!.estado,
        isNot(EstadoJugador.abandono),
        reason: 'todavía estaba dentro de su plazo',
      );
      expect(p.terminada, isTrue, reason: 'queda un solo elegible');
      expect(p.resultado!.ganadores, [beto.id]);
    });

    test(
      'con tres, dos plazos vencidos a la vez: gana quien sigue conectado',
      () async {
        var reloj = DateTime(2026, 1, 1);
        nuevo(
          graciaPartida: const Duration(milliseconds: 50),
          ahora: () => reloj,
        );
        final (ana, beto, codigo) = parejaEnLobby();
        final caro = Jugador(g, 'caro')..unirse(codigo);
        ana.accion(MsgCliente.empezar);
        for (final j in [ana, beto, caro]) {
          j.distribuir();
        }
        beto.caer();
        caro.caer();
        reloj = reloj.add(const Duration(seconds: 10));
        await esperar(200);
        final e = ana.estado;
        expect(e.fase, FaseSala.terminada);
        expect(e.resultado!.ganadores, [ana.id]);
        expect(e.resultado!.motivo, MotivoFin.abandono);
      },
    );

    test(
      'rendido más un abandono confirmado, sin nadie más: sin ganador',
      () async {
        var reloj = DateTime(2026, 1, 1);
        nuevo(
          graciaPartida: const Duration(milliseconds: 50),
          ahora: () => reloj,
        );
        final (ana, beto, codigo) = parejaEnLobby();
        final caro = Jugador(g, 'caro')..unirse(codigo);
        ana.accion(MsgCliente.empezar);
        for (final j in [ana, beto, caro]) {
          j.distribuir();
        }
        final sala = g.sala(codigo)!;
        caro.accion(MsgCliente.conceder); // rendición explícita
        ana.caer();
        beto.caer();
        reloj = reloj.add(const Duration(seconds: 10));
        await esperar(200);
        final p = sala.partida!;
        expect(p.terminada, isTrue);
        expect(p.resultado!.ganadores, isEmpty);
        expect(p.jugador(caro.id)!.estado, EstadoJugador.concedio);
      },
    );
  });

  group('Jugadores y meta', () {
    const nombres = ['ana', 'beto', 'caro', 'dani', 'eva', 'fede'];

    /// Sala con [n] jugadores ya jugando (todos confirmaron su distribución).
    (List<Jugador>, Sala) salaDe(int n) {
      final js = [Jugador(g, nombres[0])..crearSala()];
      for (var k = 1; k < n; k++) {
        js.add(Jugador(g, nombres[k])..unirse(js.first.estado.codigo));
      }
      js.first.accion(MsgCliente.empezar);
      for (final j in js) {
        j.distribuir();
      }
      return (js, g.sala(js.first.estado.codigo)!);
    }

    test('la meta se fija al empezar según el número de jugadores', () {
      for (final (n, meta) in [(2, 26), (3, 24), (4, 22), (5, 20)]) {
        final (js, _) = salaDe(n);
        for (final j in js) {
          expect(j.estado.meta, meta, reason: '$n jugadores');
          expect(j.estado.fase, FaseSala.jugando);
        }
        g.cerrar();
        nuevo();
      }
    });

    test('la sala admite cinco jugadores y rechaza al sexto', () {
      final js = [Jugador(g, nombres[0])..crearSala()];
      for (var k = 1; k < 5; k++) {
        js.add(Jugador(g, nombres[k])..unirse(js.first.estado.codigo));
      }
      expect(js.first.estado.jugadores, hasLength(5));
      final sexto = Jugador(g, nombres[5])..unirse(js.first.estado.codigo);
      expect(sexto.canal.ultimoError, contains('llena'));
      expect(js.first.estado.jugadores, hasLength(5));
    });

    test('con cinco jugadores se puede jugar una ronda completa', () {
      final (js, _) = salaDe(5);
      js.first.tirar();
      for (final j in js) {
        j.pasarRonda();
      }
      expect(js.first.estado.ronda!.id, 2);
      expect(js.last.estado.jugadores, hasLength(5));
    });

    test('la meta no cambia aunque se rindan o abandonen después', () {
      final (js, _) = salaDe(4);
      js[3].accion(MsgCliente.conceder);
      js[2].caer();
      expect(js.first.estado.meta, 22);
      js[2].volver();
      expect(js[2].estado.meta, 22);
    });
  });

  group('Premios competitivos', () {
    const nombres = ['ana', 'beto', 'caro', 'dani'];

    (List<Jugador>, Sala) salaDe(int n) {
      final js = [Jugador(g, nombres[0])..crearSala()];
      for (var k = 1; k < n; k++) {
        js.add(Jugador(g, nombres[k])..unirse(js.first.estado.codigo));
      }
      js.first.accion(MsgCliente.empezar);
      for (final j in js) {
        j.distribuir();
      }
      return (js, g.sala(js.first.estado.codigo)!);
    }

    /// Completa en el tablero de [j] todo el grupo [grupo] y lo registra como
    /// completado en la ronda abierta (equivale a confirmar la jugada que lo
    /// cierra; el premio se decide al cerrar la ronda). Después reconecta para
    /// que el cliente reciba el estado.
    void completar(Sala sala, Jugador j, String grupo) {
      final p = sala.partida!;
      final jp = p.jugador(j.id)!;
      final c = jp.controlador!;
      final g = p.libro.grupo(grupo)!;
      final base = [
        for (final i in g.casillas)
          if (c.matriz[i].valor != null) c.matriz[i].valor!,
      ];
      for (final i in g.casillas) {
        if (c.matriz[i].valor == null) c.colocar(i, base.firstOrNull ?? 1);
      }
      p.registrarGruposCompletos(jp);
    }

    int puntos(Jugador j, Jugador de) => j.estado.jugador(de.id)!.puntos;

    test('el Nivel 1 no da puntos iniciales: ningún grupo nace completo', () {
      final (js, _) = salaDe(2);
      for (final j in js) {
        for (final de in js) {
          expect(puntos(j, de), 0);
        }
        expect(j.estado.reclamaciones.every((r) => r.niveles.isEmpty), isTrue);
        expect(j.estado.misPendientes, isEmpty);
      }
    });

    test(
      'la finalización queda pendiente y se liquida una vez al cerrar la ronda',
      () {
        final (js, sala) = salaDe(2);
        final (ana, beto) = (js[0], js[1]);
        ana.tirar();
        completar(sala, ana, 'N1-a2');
        ana.caer(); // reconexión ANTES de liquidar
        ana.volver();
        expect(ana.estado.misPendientes, ['N1-a2']);
        expect(beto.estado.misPendientes, isEmpty);
        expect(puntos(ana, ana), 0, reason: 'sin liquidar no es definitivo');
        expect(ana.estado.reclamacionDe('N1-a2').niveles, isEmpty);

        ana.pasarRonda();
        beto.pasarRonda();
        for (var k = 0; k < 3; k++) {
          // Reconexiones DESPUÉS de liquidar: no se vuelve a conceder nada.
          ana.caer();
          ana.volver();
          beto.caer();
          beto.volver();
          expect(puntos(ana, ana), 7);
          expect(puntos(beto, ana), 7);
          expect(puntos(ana, beto), 0);
        }
        final r = ana.estado.reclamacionDe('N1-a2');
        expect(r.niveles, [
          [ana.id],
        ]);
        expect(ana.estado.misPendientes, isEmpty);
        expect(
          ana.estado.liquidacion.map(
            (a) => (a.jugador, a.grupo, a.nivel, a.puntos),
          ),
          [(ana.id, 'N1-a2', 1, 7)],
        );
        expect(ana.estado.mensaje, contains('Premios:'));
      },
    );

    test('empate en la misma ronda: comparten el primer nivel', () {
      Map<String, Object?> jugar(List<String> orden) {
        final (js, sala) = salaDe(3);
        final por = {for (final j in js) j.id: j};
        js.first.tirar();
        for (final id in orden) {
          completar(sala, por[id]!, 'N1-a2');
        }
        for (final j in js) {
          j.pasarRonda();
        }
        final e = js.first.estado;
        final res = {
          'puntos': [for (final j in e.jugadores) j.puntos],
          'niveles': e.reclamacionDe('N1-a2').niveles,
        };
        g.cerrar();
        nuevo();
        return res;
      }

      final a = jugar(['id_ana', 'id_beto']);
      final b = jugar(['id_beto', 'id_ana']); // orden inverso de llegada
      expect(a, b, reason: 'el orden de llegada no cambia nada');
      expect(a['puntos'], [7, 7, 0]);
      expect(a['niveles'], [
        ['id_ana', 'id_beto'],
      ]);
    });

    test('rondas distintas ocupan niveles sucesivos y luego no hay premio', () {
      final (js, sala) = salaDe(4);
      final esperado = [7, 5, 3, 0];
      for (var k = 0; k < 4; k++) {
        js.first.tirar();
        completar(sala, js[k], 'N1-a2');
        for (final j in js) {
          if (j.estado.estoyPendiente) j.pasarRonda();
        }
        expect(js.first.estado.ronda!.id, k + 2);
        expect(puntos(js.first, js[k]), esperado[k], reason: 'jugador $k');
      }
      final r = js.first.estado.reclamacionDe('N1-a2');
      expect(r.niveles, [
        [js[0].id],
        [js[1].id],
        [js[2].id],
      ]);
      expect(r.sinPremio, [js[3].id], reason: 'completó, pero sin premio');
      expect(js.first.estado.liquidacion.single.nivel, 0);
      // Quien ya cobró ese grupo no vuelve a cobrar aunque se registre otra vez.
      js.first.tirar();
      completar(sala, js[0], 'N1-a2');
      for (final j in js) {
        if (j.estado.estoyPendiente) j.pasarRonda();
      }
      expect(puntos(js.first, js[0]), 7);
    });

    test('cada grupo es independiente aunque compartan color', () {
      final (js, sala) = salaDe(2);
      js.first.tirar();
      completar(sala, js[0], 'N1-a1'); // verde 4 / 3 / 2
      completar(sala, js[1], 'N1-a13'); // el otro verde, también 4
      for (final j in js) {
        j.pasarRonda();
      }
      expect(puntos(js[0], js[0]), 4);
      expect(puntos(js[0], js[1]), 4);
      expect(js[0].estado.reclamacionDe('N1-a1').niveles, [
        [js[0].id],
      ]);
      expect(js[0].estado.reclamacionDe('N1-a13').niveles, [
        [js[1].id],
      ]);
    });

    test('varios grupos completados en la misma jugada puntúan todos', () {
      final (js, sala) = salaDe(2);
      js.first.tirar();
      completar(sala, js[0], 'N1-a2');
      completar(sala, js[0], 'N1-a34');
      for (final j in js) {
        j.pasarRonda();
      }
      expect(puntos(js[0], js[0]), 14);
      expect(js[0].estado.liquidacion, hasLength(2));
    });

    test('la meta termina la partida al cerrar la ronda, no antes', () {
      final (js, sala) = salaDe(2);
      final p = sala.partida!;
      p.jugador(js[0].id)!.puntos = 25;
      js[0].tirar();
      completar(sala, js[0], 'N1-a2'); // 25 + 7 = 32 >= 26, pero sin liquidar
      js[0].pasarRonda();
      expect(js[0].estado.fase, FaseSala.jugando, reason: 'falta Beto');
      expect(sala.partida!.terminada, isFalse);
      js[1].pasarRonda();
      for (final j in js) {
        final e = j.estado;
        expect(e.fase, FaseSala.terminada);
        expect(e.resultado!.motivo, MotivoFin.meta);
        expect(e.resultado!.ganadores, [js[0].id]);
        expect(puntos(j, js[0]), 32);
      }
      expect(js[0].estado.mensaje, contains('meta de 26'));
    });

    test(
      'varios alcanzan la meta en la misma ronda: gana el de más puntos',
      () {
        final (js, sala) = salaDe(2);
        final p = sala.partida!;
        p.jugador(js[0].id)!.puntos = 25;
        p.jugador(js[1].id)!.puntos = 21;
        js[0].tirar();
        completar(sala, js[0], 'N1-a2');
        completar(sala, js[1], 'N1-a2'); // empatan: ambos +7 (1.er nivel)
        for (final j in js) {
          j.pasarRonda();
        }
        final e = js[0].estado;
        expect(e.resultado!.motivo, MotivoFin.meta);
        expect(puntos(js[0], js[0]), 32);
        expect(puntos(js[0], js[1]), 28);
        expect(e.resultado!.ganadores, [js[0].id]);
      },
    );

    test('empate en el máximo al alcanzar la meta: comparten la victoria', () {
      final (js, sala) = salaDe(2);
      final p = sala.partida!;
      p.jugador(js[0].id)!.puntos = 22;
      p.jugador(js[1].id)!.puntos = 22;
      js[0].tirar();
      completar(sala, js[0], 'N1-a2');
      completar(sala, js[1], 'N1-a2');
      for (final j in js) {
        j.pasarRonda();
      }
      expect(js[0].estado.resultado!.ganadores.toSet(), {js[0].id, js[1].id});
    });

    test('sin llegar a la meta la partida sigue; rendirse no concede premios nuevos', () {
      final (js, sala) = salaDe(3);
      js[0].tirar();
      completar(sala, js[2], 'N1-a2');
      js[2].accion(
        MsgCliente.conceder,
      ); // se rinde con una finalización pendiente
      for (final j in js.take(2)) {
        if (j.estado.estoyPendiente) j.pasarRonda();
      }
      expect(js[0].estado.fase, FaseSala.jugando);
      // Lo completado antes de rendirse cuenta, pero no puede ganar.
      expect(puntos(js[0], js[2]), 7);
      expect(js[0].estado.jugador(js[2].id)!.participa, isFalse);
    });
  });

  group('Plazo común de la ronda', () {
    test('esperando la tirada no corre ningún plazo', () async {
      nuevo(ronda: const Duration(milliseconds: 80));
      final (ana, beto) = parejaJugando();
      await esperar(250);
      expect(ana.estado.ronda!.fase, FaseRonda.esperandoTirada);
      expect(ana.estado.ronda!.id, 1);
      for (final j in [ana, beto]) {
        expect(j.estado.miJugador!.estado, EstadoJugador.jugando);
      }
    });

    test('empieza al publicar los dados y baja con el tiempo', () async {
      nuevo(ronda: const Duration(seconds: 30));
      final (ana, beto) = parejaJugando();
      ana.tirar();
      for (final j in [ana, beto]) {
        expect(j.estado.ronda!.segundos, inInclusiveRange(29, 30));
      }
    });

    test(
      'al vencer, el que no respondió queda sin respuesta y se cierra',
      () async {
        nuevo(ronda: const Duration(milliseconds: 150));
        final (ana, beto) = parejaJugando();
        ana.tirar();
        ana.pasarRonda();
        await esperar(260);
        final e = ana.estado;
        expect(e.ronda!.id, 2);
        expect(e.ronda!.fase, FaseRonda.esperandoTirada);
        expect(e.mensaje, contains('no respondió'));
        expect(e.mensaje, contains('beto'));
        expect(e.jugador(beto.id)!.estado, EstadoJugador.jugando);
        expect(beto.estado.tablero.where((v) => v != null), hasLength(6));
      },
    );

    test('confirmar o pasar no reinicia el plazo común', () async {
      nuevo(ronda: const Duration(milliseconds: 300));
      final (ana, beto) = parejaJugando();
      ana.tirar();
      await esperar(200);
      ana.pasarRonda(); // si reiniciara, vencería a los 500 ms
      expect(ana.estado.ronda!.id, 1);
      await esperar(180); // 380 ms: ya venció el plazo original
      expect(ana.estado.ronda!.id, 2);
      expect(beto.estado.ronda!.fase, FaseRonda.esperandoTirada);
    });

    test('reconectar o caerse no alarga el plazo', () async {
      nuevo(ronda: const Duration(milliseconds: 400));
      final (ana, beto) = parejaJugando();
      ana.tirar();
      await esperar(200);
      beto.caer();
      beto.volver();
      expect(ana.estado.ronda!.id, 1);
      await esperar(320); // 520 ms desde la tirada
      expect(ana.estado.ronda!.id, 2);
    });

    test('tres rondas seguidas sin respuesta provocan el abandono', () async {
      nuevo(ronda: const Duration(milliseconds: 60));
      final (ana, beto) = parejaJugando();
      for (var i = 0; i < 3; i++) {
        expect(ana.estado.jugador(beto.id)!.estado, EstadoJugador.jugando);
        ana.tirar();
        ana.pasarRonda();
        await esperar(130);
      }
      final e = ana.estado;
      expect(e.jugador(beto.id)!.estado, EstadoJugador.abandono);
      expect(e.fase, FaseSala.terminada);
      expect(e.resultado!.ganadores, [ana.id]);
    });

    test('pasar voluntariamente nunca cuenta como inactividad', () async {
      nuevo(ronda: const Duration(milliseconds: 60));
      final (ana, beto) = parejaJugando();
      // Beto pasa siempre: nunca debe acumular faltas de respuesta.
      for (var i = 0; i < 5; i++) {
        ana.tirar();
        ana.pasarRonda();
        beto.pasarRonda();
      }
      await esperar(200);
      expect(ana.estado.jugador(beto.id)!.estado, EstadoJugador.jugando);
      expect(ana.estado.ronda!.id, 6);
    });

    test('responder reinicia la cuenta de rondas sin respuesta', () async {
      nuevo(ronda: const Duration(milliseconds: 60));
      final (ana, beto) = parejaJugando();
      Future<void> ronda({required bool betoResponde}) async {
        ana.tirar();
        ana.pasarRonda();
        if (betoResponde) {
          beto.pasarRonda();
        } else {
          await esperar(130);
        }
      }

      await ronda(betoResponde: false); // 1
      await ronda(betoResponde: false); // 2
      await ronda(betoResponde: true); // reinicia
      await ronda(betoResponde: false); // 1
      await ronda(betoResponde: false); // 2
      expect(ana.estado.jugador(beto.id)!.estado, EstadoJugador.jugando);
      expect(ana.estado.fase, FaseSala.jugando);
    });

    test(
      'vence la ronda con alguien desconectado: sin respuesta, no abandono',
      () async {
        nuevo(ronda: const Duration(milliseconds: 100)); // la gracia es larga
        final (ana, beto) = parejaJugando();
        ana.tirar();
        ana.pasarRonda();
        beto.caer();
        await esperar(220);
        final e = ana.estado;
        expect(e.ronda!.id, 2);
        final b = e.jugador(beto.id)!;
        expect(b.estado, EstadoJugador.jugando);
        expect(b.conectado, isFalse);
        expect(b.graciaRestante, greaterThan(0));
        // Puede volver y seguir participando.
        beto.volver();
        expect(beto.estado.miJugador!.participa, isTrue);
        expect(beto.estado.ronda!.id, 2);
      },
    );

    test(
      'vence la gracia con la ronda abierta: abandono y la ronda se cierra',
      () async {
        nuevo(graciaPartida: const Duration(milliseconds: 80));
        final (ana, beto, codigo) = parejaEnLobby();
        final caro = Jugador(g, 'caro')..unirse(codigo);
        ana.accion(MsgCliente.empezar);
        for (final j in [ana, beto, caro]) {
          j.distribuir();
        }
        ana.tirar();
        ana.pasarRonda();
        beto.pasarRonda();
        expect(ana.estado.ronda!.id, 1, reason: 'falta Caro');
        caro.caer();
        await esperar(200);
        final e = ana.estado;
        expect(e.jugador(caro.id)!.estado, EstadoJugador.abandono);
        expect(e.ronda!.id, 2, reason: 'ya no se espera a Caro');
        expect(e.ronda!.fase, FaseRonda.esperandoTirada);
        expect(e.fase, FaseSala.jugando);
      },
    );

    test(
      'rendido, abandonado y terminado no pueden lanzar ni bloquean rondas',
      () {
        final (ana, beto, codigo) = parejaEnLobby();
        final caro = Jugador(g, 'caro')..unirse(codigo);
        ana.accion(MsgCliente.empezar);
        for (final j in [ana, beto, caro]) {
          j.distribuir();
        }
        caro.accion(MsgCliente.conceder);
        caro.tirar(de: 1);
        expect(caro.canal.ultimoError, isNotNull);
        ana.tirar();
        expect(ana.estado.ronda!.resoluciones.keys.toSet(), {ana.id, beto.id});
        ana.pasarRonda();
        beto.pasarRonda();
        expect(ana.estado.ronda!.id, 2, reason: 'el rendido no bloquea');
      },
    );

    test('el plazo se reprograma en cada ronda', () async {
      nuevo(ronda: const Duration(milliseconds: 150));
      final (ana, beto) = parejaJugando();
      jugarRonda([ana, beto]); // ronda 1 cerrada sin esperar al plazo
      expect(ana.estado.ronda!.id, 2);
      ana.tirar();
      expect(ana.estado.ronda!.segundos, isNotNull);
      await esperar(260);
      expect(ana.estado.ronda!.id, 3);
    });
  });
}
