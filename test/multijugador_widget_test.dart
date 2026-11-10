import 'package:dart_package_1/auth/cliente_auth.dart';
import 'package:dart_package_1/dart_package_1.dart';
import 'package:dart_package_1/online/cliente_multijugador.dart';
import 'package:dart_package_1/online/pantalla_multijugador.dart';
import 'package:dart_package_1/pantalla_seleccion_mapa.dart';
import 'package:dart_package_1/widgets/celda_gema.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ayudas_online.dart';
import 'ayudas_pruebas.dart';

/// Avanza un poco el reloj de la prueba (no usa pumpAndSettle porque el
/// indicador de "Conectando…" y el reloj de turno animan sin parar).
Future<void> bombear(WidgetTester tester, [int ms = 50]) async {
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
}

/// Deja terminar la animación de cierre de una pantalla.
Future<void> transicion(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 1));

Future<void> tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await bombear(tester, 350);
}

CeldaGema celda(WidgetTester tester, int i) =>
    tester.widget<CeldaGema>(find.byKey(Key('celda_$i')));

bool habilitado(WidgetTester tester, String clave) {
  final w = tester.widget(find.byKey(Key(clave)));
  return switch (w) {
    FilledButton b => b.onPressed != null,
    OutlinedButton b => b.onPressed != null,
    _ => throw StateError('No es un botón: $clave'),
  };
}

void main() {
  setUpAll(cargarFuentes);

  late ServidorFalso servidor;
  late ClienteMultijugador cliente;
  late ClienteAuth auth;
  var abierto = false;

  /// Como testWidgets, pero al terminar retira la pantalla y cierra el
  /// cliente dentro del test: así no quedan temporizadores pendientes (el
  /// latido y el reloj) cuando el framework comprueba que todo se limpió.
  void prueba(String nombre, Future<void> Function(WidgetTester) cuerpo) {
    testWidgets(nombre, (tester) async {
      abierto = false;
      await cuerpo(tester);
      await tester.pumpWidget(const SizedBox());
      if (abierto) cliente.dispose();
    });
  }

  /// Abre la pantalla desde un menú para poder probar el "volver".
  Future<void> abrir(WidgetTester tester) async {
    await fijarPantalla(tester);
    abierto = true;
    servidor = ServidorFalso();
    auth = ClienteAuth(urlBase: 'http://servidor.test');
    cliente = ClienteMultijugador(
      url: Uri.parse('ws://servidor.test/ws'),
      token: () => 'jwt',
      fabrica: servidor.fabrica,
      esperasReintento: const [Duration(milliseconds: 20)],
      umbralSegundoPlano: Duration.zero,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('abrir'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        PantallaMultijugador(auth: auth, cliente: cliente),
                  ),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('abrir')));
    await bombear(tester, 1000);
  }

  /// Abre la pantalla y deja al cliente conectado con el estado dado.
  Future<void> abrirCon(WidgetTester tester, EstadoSala? estado) async {
    await abrir(tester);
    if (estado == null) {
      servidor.ultima.servidorEnvia({'tipo': MsgServidor.sinSala});
    } else {
      servidor.ultima.servidorEstado(estado);
    }
    await bombear(tester);
  }

  void enviar(EstadoSala e) => servidor.ultima.servidorEstado(e);

  Future<void> recibir(WidgetTester tester, EstadoSala e) async {
    enviar(e);
    await bombear(tester);
  }

  group('Menú principal', () {
    testWidgets('ofrece jugar en línea solo con una cuenta', (tester) async {
      await fijarPantalla(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: PantallaSeleccionMapa(
            auth: ClienteAuth(urlBase: 'http://servidor.test'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('boton_multijugador')), findsOneWidget);

      await tester.pumpWidget(const MaterialApp(home: PantallaSeleccionMapa()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('boton_multijugador')), findsNothing);
    });
  });

  group('Entrada', () {
    prueba('muestra "Conectando…" y luego crear o unirse', (tester) async {
      await abrir(tester);
      expect(find.text('Conectando…'), findsOneWidget);
      expect(servidor.ultima.enviados.first['tipo'], MsgCliente.auth);

      servidor.ultima.servidorEnvia({'tipo': MsgServidor.sinSala});
      await bombear(tester);
      expect(find.text('Conectando…'), findsNothing);
      expect(find.byKey(const Key('boton_crear_sala')), findsOneWidget);
      expect(find.byKey(const Key('campo_codigo')), findsOneWidget);
    });

    prueba('crear sala pide la sala y muestra el lobby con el código', (
      tester,
    ) async {
      await abrirCon(tester, null);
      await tap(tester, find.byKey(const Key('boton_crear_sala')));
      expect(servidor.ultima.ultimoDe(MsgCliente.crearSala), isNotNull);
      // Mientras espera la respuesta no se puede pulsar otra vez.
      expect(habilitado(tester, 'boton_crear_sala'), isFalse);

      await recibir(tester, estadoSala(jugadores: [jugadorSala('a')]));
      expect(find.byKey(const Key('codigo_sala')), findsOneWidget);
      expect(find.text('ABC234'), findsOneWidget);
      expect(find.text('A (tú)'), findsOneWidget);
      expect(habilitado(tester, 'boton_empezar'), isFalse);
      expect(find.byKey(const Key('aviso_lobby')), findsOneWidget);
    });

    prueba('unirse envía el código escrito', (tester) async {
      await abrirCon(tester, null);
      await tester.enterText(find.byKey(const Key('campo_codigo')), 'abc 234');
      await tap(tester, find.byKey(const Key('boton_unirse')));
      expect(servidor.ultima.ultimoDe(MsgCliente.unirse), {
        'tipo': MsgCliente.unirse,
        'codigo': 'abc 234',
      });
    });

    prueba('no envía nada si el código está vacío', (tester) async {
      await abrirCon(tester, null);
      await tap(tester, find.byKey(const Key('boton_unirse')));
      expect(servidor.ultima.ultimoDe(MsgCliente.unirse), isNull);
    });

    prueba('un código incorrecto muestra el error del servidor', (
      tester,
    ) async {
      await abrirCon(tester, null);
      await tester.enterText(find.byKey(const Key('campo_codigo')), 'ZZZZZZ');
      await tap(tester, find.byKey(const Key('boton_unirse')));
      servidor.ultima.servidorEnvia({
        'tipo': MsgServidor.error,
        'codigo': CodigoError.generico,
        'mensaje': 'No existe ninguna sala con ese código.',
      });
      await bombear(tester);
      expect(
        find.text('No existe ninguna sala con ese código.'),
        findsOneWidget,
      );
      // La acción se liberó: se puede reintentar.
      expect(habilitado(tester, 'boton_unirse'), isTrue);
    });
  });

  group('Lobby', () {
    prueba('el anfitrión empieza cuando hay 2 conectados', (tester) async {
      await abrirCon(
        tester,
        estadoSala(jugadores: [jugadorSala('a'), jugadorSala('b')]),
      );
      expect(habilitado(tester, 'boton_empezar'), isTrue);
      await tap(tester, find.byKey(const Key('boton_empezar')));
      expect(servidor.ultima.ultimoDe(MsgCliente.empezar), isNotNull);
    });

    prueba('no se empieza con un jugador desconectado', (tester) async {
      await abrirCon(
        tester,
        estadoSala(
          jugadores: [
            jugadorSala('a'),
            jugadorSala('b', conectado: false, gracia: 12),
          ],
        ),
      );
      expect(habilitado(tester, 'boton_empezar'), isFalse);
      expect(find.textContaining('puede volver durante 12s'), findsOneWidget);

      await recibir(
        tester,
        estadoSala(jugadores: [jugadorSala('a'), jugadorSala('b')]),
      );
      expect(habilitado(tester, 'boton_empezar'), isTrue);
    });

    prueba('un invitado espera: sin botón de empezar ni de elegir mapa', (
      tester,
    ) async {
      await abrirCon(tester, estadoSala(yo: 'b', mapa: 2));
      expect(find.byKey(const Key('boton_empezar')), findsNothing);
      expect(find.byKey(const Key('mapa_0')), findsNothing);
      expect(find.byKey(const Key('expulsar_a')), findsNothing);
      expect(find.text('Nivel 3'), findsOneWidget);
      expect(find.textContaining('Esperando a que el anfitrión'), findsOne);
    });

    prueba('el anfitrión elige mapa y expulsa', (tester) async {
      await abrirCon(tester, estadoSala());
      await tap(tester, find.byKey(const Key('mapa_2')));
      expect(servidor.ultima.ultimoDe(MsgCliente.elegirMapa), {
        'tipo': MsgCliente.elegirMapa,
        'mapa': 2,
      });
      await recibir(tester, estadoSala(mapa: 2));

      await tap(tester, find.byKey(const Key('expulsar_b')));
      expect(servidor.ultima.ultimoDe(MsgCliente.expulsar), {
        'tipo': MsgCliente.expulsar,
        'id': 'b',
      });
    });

    prueba('salir de la sala vuelve a la entrada', (tester) async {
      await abrirCon(tester, estadoSala());
      await tap(tester, find.byKey(const Key('boton_salir_sala')));
      expect(servidor.ultima.ultimoDe(MsgCliente.salirSala), isNotNull);
      servidor.ultima.servidorEnvia({'tipo': MsgServidor.sinSala});
      await bombear(tester);
      expect(find.byKey(const Key('boton_crear_sala')), findsOneWidget);
    });

    prueba('si me expulsan vuelvo a la entrada con un aviso', (tester) async {
      await abrirCon(tester, estadoSala(yo: 'b'));
      servidor.ultima.servidorEnvia({'tipo': MsgServidor.expulsado});
      await bombear(tester);
      expect(find.byKey(const Key('boton_crear_sala')), findsOneWidget);
      expect(find.text('El anfitrión te sacó de la sala.'), findsOneWidget);
    });
  });

  group('Preparación', () {
    final ini = mapasOficiales.first.indicesIniciales;

    EstadoSala preparando({
      Map<int, int> colocados = const {},
      EstadoJugador yo = EstadoJugador.preparando,
      EstadoJugador rival = EstadoJugador.preparando,
      List<JugadorSala>? jugadores,
    }) {
      final t = List<int?>.filled(49, null);
      colocados.forEach((posicion, n) => t[ini[posicion]] = n);
      return estadoSala(
        fase: FaseSala.preparacion,
        tablero: t,
        jugadores:
            jugadores ??
            [jugadorSala('a', estado: yo), jugadorSala('b', estado: rival)],
      );
    }

    Map<String, Object?>? ultimo(String tipo) => servidor.ultima.ultimoDe(tipo);

    prueba('muestra números, progreso y estados; confirmar deshabilitado', (
      tester,
    ) async {
      await abrirCon(tester, preparando());
      for (var n = 1; n <= 6; n++) {
        expect(find.byKey(Key('numero_$n')), findsOneWidget);
        expect(habilitado(tester, 'numero_$n'), isTrue);
      }
      expect(find.text('Números colocados: 0/6'), findsOneWidget);
      expect(habilitado(tester, 'boton_confirmar_distribucion'), isFalse);
      expect(
        tester.widget<Text>(find.byKey(const Key('estado_a'))).data,
        'Colocando números',
      );
      for (var k = 0; k < 6; k++) {
        expect(find.byKey(Key('inicial_$k')), findsOneWidget);
      }
    });

    prueba('elegir un número y tocar una posición envía la colocación', (
      tester,
    ) async {
      await abrirCon(tester, preparando());
      await tap(tester, find.byKey(const Key('numero_4')));
      await tap(tester, find.byKey(const Key('inicial_2')));
      final msg = ultimo(MsgCliente.colocarInicial)!;
      expect(msg['indice'], ini[2]);
      expect(msg['numero'], 4);

      // El servidor confirma: avanza el progreso y el 4 queda usado.
      await recibir(tester, preparando(colocados: {2: 4}));
      expect(find.text('Números colocados: 1/6'), findsOneWidget);
      expect(habilitado(tester, 'numero_4'), isFalse);
      expect(habilitado(tester, 'numero_5'), isTrue);
      expect(celda(tester, 0).valor, isNull);
    });

    prueba(
      'tocar una posición sin elegir número, o una casilla normal, no envía nada',
      (tester) async {
        await abrirCon(tester, preparando());
        await tap(tester, find.byKey(const Key('inicial_0')));
        await tap(tester, find.byKey(const Key('numero_1')));
        await tap(tester, find.byKey(const Key('celda_0')));
        expect(
          servidor.ultima.tiposEnviados,
          isNot(contains(MsgCliente.colocarInicial)),
        );
      },
    );

    prueba('tocar un número colocado lo retira y lo devuelve a disponibles', (
      tester,
    ) async {
      await abrirCon(tester, preparando(colocados: {0: 3, 1: 6}));
      expect(find.text('Números colocados: 2/6'), findsOneWidget);
      await tap(tester, find.byKey(const Key('inicial_0')));
      expect(ultimo(MsgCliente.quitarInicial)!['indice'], ini[0]);
      await recibir(tester, preparando(colocados: {1: 6}));
      expect(find.text('Números colocados: 1/6'), findsOneWidget);
      expect(habilitado(tester, 'numero_3'), isTrue);
    });

    prueba('confirmar solo se habilita con los seis números y se envía', (
      tester,
    ) async {
      await abrirCon(
        tester,
        preparando(colocados: {0: 1, 1: 2, 2: 3, 3: 4, 4: 5}),
      );
      expect(habilitado(tester, 'boton_confirmar_distribucion'), isFalse);
      await recibir(
        tester,
        preparando(colocados: {0: 1, 1: 2, 2: 3, 3: 4, 4: 5, 5: 6}),
      );
      expect(find.text('Números colocados: 6/6'), findsOneWidget);
      expect(habilitado(tester, 'boton_confirmar_distribucion'), isTrue);
      await tap(tester, find.byKey(const Key('boton_confirmar_distribucion')));
      expect(ultimo(MsgCliente.confirmarDistribucion), isNotNull);
    });

    prueba('tras confirmar se bloquea y se espera a los demás', (tester) async {
      final todos = {0: 1, 1: 2, 2: 3, 3: 4, 4: 5, 5: 6};
      await abrirCon(
        tester,
        preparando(colocados: todos, yo: EstadoJugador.listo),
      );
      expect(find.text('Esperando a los demás jugadores'), findsOneWidget);
      expect(
        find.byKey(const Key('boton_confirmar_distribucion')),
        findsNothing,
      );
      expect(find.byKey(const Key('numero_1')), findsNothing);
      expect(find.text('Faltan por confirmar: B'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('estado_a'))).data,
        'Listo',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('estado_b'))).data,
        'Colocando números',
      );
      // Ya no se puede modificar: tocar una posición no envía nada.
      await tap(tester, find.byKey(const Key('inicial_0')));
      expect(
        servidor.ultima.tiposEnviados,
        isNot(contains(MsgCliente.quitarInicial)),
      );
    });

    prueba('un número elegido se descarta si ya no está disponible', (
      tester,
    ) async {
      await abrirCon(tester, preparando());
      await tap(tester, find.byKey(const Key('numero_2')));
      await recibir(tester, preparando(colocados: {0: 2}));
      await tap(tester, find.byKey(const Key('inicial_1')));
      expect(
        servidor.ultima.tiposEnviados,
        isNot(contains(MsgCliente.colocarInicial)),
      );
    });

    prueba('puntos provisionales según el tablero propio, sin acumular', (
      tester,
    ) async {
      // Nivel 3: dos áreas blancas de una casilla iniciales (4 + 4).
      final ini3 = mapasOficiales[2].indicesIniciales;
      List<int?> tab(int n) {
        final t = List<int?>.filled(49, null);
        for (var k = 0; k < n; k++) {
          t[ini3[k]] = k + 1;
        }
        return t;
      }

      EstadoSala e(int n, {EstadoJugador yo = EstadoJugador.preparando}) =>
          estadoSala(
            fase: FaseSala.preparacion,
            mapa: 2,
            tablero: tab(n),
            jugadores: [
              jugadorSala('a', estado: yo),
              jugadorSala('b'),
            ],
          );
      await abrirCon(tester, e(0));
      Text pts() => tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('puntos_provisionales')),
          matching: find.byType(Text),
        ),
      );
      expect(pts().data, '0 pts (provisional)');
      await recibir(tester, e(6));
      expect(pts().data, '8 pts (provisional)');
      // Quitar y volver a poner no suma de más: el valor sale del tablero.
      await recibir(tester, e(5));
      await recibir(tester, e(6));
      expect(pts().data, '8 pts (provisional)');
      await recibir(tester, e(6, yo: EstadoJugador.listo));
      expect(pts().data, '8 pts');
    });

    prueba('la reconexión recupera borrador y confirmación', (tester) async {
      final borrador = preparando(colocados: {0: 5, 3: 1});
      await abrirCon(tester, borrador);
      servidor.ultima.servidorCierra();
      await bombear(tester, 100);
      expect(find.byKey(const Key('banda_reconectando')), findsOneWidget);
      expect(find.text('Números colocados: 2/6'), findsOneWidget);
      // El servidor devuelve el mismo borrador al reconectar.
      await recibir(tester, borrador);
      expect(find.byKey(const Key('banda_reconectando')), findsNothing);
      expect(find.text('Números colocados: 2/6'), findsOneWidget);
      expect(habilitado(tester, 'numero_5'), isFalse);
      // Si ya había confirmado, sigue confirmado.
      await recibir(
        tester,
        preparando(
          colocados: {0: 1, 1: 2, 2: 3, 3: 4, 4: 5, 5: 6},
          yo: EstadoJugador.listo,
        ),
      );
      expect(find.text('Esperando a los demás jugadores'), findsOneWidget);
    });

    prueba('rival desconectado, rendido o abandonado se distingue', (
      tester,
    ) async {
      await abrirCon(
        tester,
        preparando(
          jugadores: [
            jugadorSala('a'),
            jugadorSala(
              'b',
              estado: EstadoJugador.listo,
              conectado: false,
              gracia: 30,
            ),
            jugadorSala('c', estado: EstadoJugador.concedio),
            jugadorSala('d', estado: EstadoJugador.abandono),
          ],
        ),
      );
      String texto(String id) =>
          tester.widget<Text>(find.byKey(Key('estado_$id'))).data!;
      expect(texto('b'), 'Listo · Sin conexión 30s');
      expect(texto('c'), 'Rendido');
      expect(texto('d'), 'Abandonó');
    });

    prueba('quien se rindió en la preparación solo mira', (tester) async {
      await abrirCon(tester, preparando(yo: EstadoJugador.concedio));
      expect(
        find.text('Ya no participas. Puedes seguir mirando.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('boton_confirmar_distribucion')),
        findsNothing,
      );
      expect(habilitado(tester, 'numero_1'), isFalse);
    });

    prueba('salir en plena preparación pide confirmar (cuenta como rendirse)', (
      tester,
    ) async {
      await abrirCon(tester, preparando());
      await tester.tap(find.byKey(const Key('boton_volver')));
      await bombear(tester, 350);
      expect(find.text('¿Rendirte y salir?'), findsOneWidget);
    });
  });

  group('Estados en partida', () {
    EstadoSala conEstados(List<JugadorSala> js, {String yo = 'a'}) =>
        estadoSala(yo: yo, fase: FaseSala.jugando, turnoDe: 'b', jugadores: js);

    prueba('terminado, rendido, abandonó y sin conexión se distinguen', (
      tester,
    ) async {
      await abrirCon(
        tester,
        conEstados([
          jugadorSala('a'),
          jugadorSala('b'),
          jugadorSala('c', estado: EstadoJugador.terminado, puntos: 30),
          jugadorSala(
            'd',
            estado: EstadoJugador.terminado,
            conectado: false,
            gracia: 20,
          ),
        ]),
      );
      String texto(String id) =>
          tester.widget<Text>(find.byKey(Key('estado_$id'))).data!;
      expect(texto('c'), 'Terminado');
      expect(texto('d'), 'Terminado · Sin conexión 20s');
      expect(tester.widget<Text>(find.byKey(const Key('puntos_c'))).data, '30');

      await recibir(
        tester,
        conEstados([
          jugadorSala('a'),
          jugadorSala('b'),
          jugadorSala('c', estado: EstadoJugador.concedio, puntos: 12),
          jugadorSala('d', estado: EstadoJugador.abandono, puntos: 8),
        ]),
      );
      expect(texto('c'), 'Rendido');
      expect(texto('d'), 'Abandonó');
      expect(tester.widget<Text>(find.byKey(const Key('puntos_c'))).data, '12');
    });

    prueba('quien terminó su tablero lo ve y no puede actuar', (tester) async {
      await abrirCon(
        tester,
        conEstados([
          jugadorSala('a', estado: EstadoJugador.terminado, puntos: 20),
          jugadorSala('b'),
        ]),
      );
      expect(
        find.text('Terminaste tu tablero. Esperando a que acaben los demás.'),
        findsOneWidget,
      );
      expect(habilitado(tester, 'boton_tirar_dados'), isFalse);
    });
  });

  group('Partida', () {
    EstadoSala jugando({
      String yo = 'a',
      String turnoDe = 'a',
      List<int>? dados,
      List<int?>? tablero,
      List<JugadorSala>? jugadores,
      int turno = 1,
    }) => estadoSala(
      yo: yo,
      fase: FaseSala.jugando,
      turnoDe: turnoDe,
      dados: dados,
      tablero: tablero,
      jugadores: jugadores,
      turno: turno,
      mensaje: 'Empieza la partida.',
    );

    prueba('mi turno: tirar, elegir ancla y colocar', (tester) async {
      await abrirCon(tester, jugando());
      expect(find.byType(CeldaGema), findsNWidgets(49));
      expect(find.text('Es tu turno. Tira los dados.'), findsOneWidget);
      expect(habilitado(tester, 'boton_tirar_dados'), isTrue);
      expect(habilitado(tester, 'boton_pasar_turno'), isFalse);

      await tap(tester, find.byKey(const Key('boton_tirar_dados')));
      expect(servidor.ultima.ultimoDe(MsgCliente.tirar), isNotNull);

      await recibir(tester, jugando(dados: [1, 2]));
      expect(find.text('2'), findsWidgets);
      expect(habilitado(tester, 'boton_tirar_dados'), isFalse);

      // Ancla: dado 1. La casilla 2 tiene un 1; sus vecinos 1 y 3 valen para
      // el 2, y la 9 (azul con un 1) no.
      await tap(tester, find.byKey(const Key('dado_0')));
      expect(celda(tester, 1).esDestino, isTrue);
      expect(celda(tester, 3).esDestino, isTrue);
      expect(celda(tester, 9).esDestino, isFalse);

      // Tocar el mismo dado quita la selección.
      await tap(tester, find.byKey(const Key('dado_0')));
      expect(celda(tester, 1).esDestino, isFalse);
      await tap(tester, find.byKey(const Key('dado_0')));

      await tap(tester, find.byKey(const Key('celda_1')));
      expect(servidor.ultima.ultimoDe(MsgCliente.colocar), {
        'tipo': MsgCliente.colocar,
        'indice': 1,
        'ancla': 0,
      });
    });

    prueba('tocar una casilla que no es destino no envía nada', (tester) async {
      await abrirCon(tester, jugando(dados: [1, 2]));
      await tap(tester, find.byKey(const Key('dado_0')));
      await tap(tester, find.byKey(const Key('celda_9')));
      await tap(tester, find.byKey(const Key('celda_40')));
      expect(servidor.ultima.ultimoDe(MsgCliente.colocar), isNull);
    });

    prueba('al llegar un turno nuevo se olvida el ancla elegida', (
      tester,
    ) async {
      await abrirCon(tester, jugando(dados: [1, 2]));
      await tap(tester, find.byKey(const Key('dado_0')));
      expect(celda(tester, 1).esDestino, isTrue);

      final tablero = tableroInicial()..[1] = 2;
      await recibir(tester, jugando(turnoDe: 'b', tablero: tablero, turno: 2));
      await recibir(tester, jugando(tablero: tablero, turno: 3, dados: [1, 2]));
      expect(celda(tester, 3).esDestino, isFalse);
    });

    prueba('fuera de mi turno no puedo tirar, pasar ni elegir dado', (
      tester,
    ) async {
      await abrirCon(tester, jugando(yo: 'b', turnoDe: 'a', dados: [1, 2]));
      expect(find.text('Turno de A.'), findsOneWidget);
      expect(habilitado(tester, 'boton_tirar_dados'), isFalse);
      expect(habilitado(tester, 'boton_pasar_turno'), isFalse);
      await tap(tester, find.byKey(const Key('dado_0')));
      expect(celda(tester, 1).esDestino, isFalse);
      // Pero sí veo los dados del rival.
      expect(find.byKey(const Key('dado_0')), findsOneWidget);
    });

    prueba('solo se puede pasar cuando los dados no dejan movimientos', (
      tester,
    ) async {
      // Todo ocupado salvo la casilla 9 (azul), cuya área exige unos.
      final tablero = List<int?>.filled(49, 4);
      for (final e in tableroInicial().asMap().entries) {
        if (e.value != null) tablero[e.key] = e.value;
      }
      tablero[9] = null;
      tablero[10] = 1;
      tablero[17] = 1;

      await abrirCon(tester, jugando(tablero: tablero, dados: [2, 3]));
      expect(habilitado(tester, 'boton_pasar_turno'), isTrue);
      expect(find.textContaining('no hay movimientos'), findsOneWidget);
      await tap(tester, find.byKey(const Key('boton_pasar_turno')));
      expect(servidor.ultima.ultimoDe(MsgCliente.pasar), isNotNull);
    });

    prueba('el marcador muestra a todos y de quién es el turno', (
      tester,
    ) async {
      await abrirCon(
        tester,
        jugando(
          jugadores: [jugadorSala('a', puntos: 7), jugadorSala('b', puntos: 4)],
        ),
      );
      expect(find.byKey(const Key('puntos_a')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('puntos_a'))).data, '7');
      expect(tester.widget<Text>(find.byKey(const Key('puntos_b'))).data, '4');
      expect(
        tester.widget<Text>(find.byKey(const Key('estado_a'))).data,
        startsWith('Turno'),
      );
      expect(tester.widget<Text>(find.byKey(const Key('estado_b'))).data, '');
    });

    prueba('un rival desconectado se ve con su cuenta atrás', (tester) async {
      await abrirCon(
        tester,
        jugando(
          turnoDe: 'b',
          jugadores: [
            jugadorSala('a'),
            jugadorSala('b', conectado: false, gracia: 40),
          ],
        ),
      );
      final texto = tester.widget<Text>(find.byKey(const Key('estado_b')));
      expect(texto.data, contains('Sin conexión 40s'));
      expect(texto.data, startsWith('Turno'), reason: 'conserva su estado');
      expect(texto.data, contains('s'));
    });

    prueba('un rival que se rindió aparece como tal', (tester) async {
      await abrirCon(
        tester,
        jugando(
          jugadores: [
            jugadorSala('a'),
            jugadorSala('b', estado: EstadoJugador.concedio),
            jugadorSala('c'),
          ],
        ),
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('estado_b'))).data,
        'Rendido',
      );
    });

    prueba('rendirse desde el menú pide confirmación y envía conceder', (
      tester,
    ) async {
      await abrirCon(tester, jugando());
      await tap(tester, find.byKey(const Key('menu_partida')));
      await tap(tester, find.byKey(const Key('menu_rendirse')));
      expect(find.text('¿Rendirte?'), findsOneWidget);

      await tap(tester, find.byKey(const Key('confirmar_no')));
      expect(servidor.ultima.ultimoDe(MsgCliente.conceder), isNull);

      await tap(tester, find.byKey(const Key('menu_partida')));
      await tap(tester, find.byKey(const Key('menu_rendirse')));
      await tap(tester, find.byKey(const Key('confirmar_si')));
      expect(servidor.ultima.ultimoDe(MsgCliente.conceder), isNotNull);
    });

    prueba('quien ya se rindió no ve la opción y solo mira', (tester) async {
      await abrirCon(
        tester,
        jugando(
          turnoDe: 'b',
          jugadores: [
            jugadorSala('a', estado: EstadoJugador.concedio),
            jugadorSala('b'),
            jugadorSala('c'),
          ],
        ),
      );
      expect(find.textContaining('Ya no participas'), findsOneWidget);
      await tap(tester, find.byKey(const Key('menu_partida')));
      expect(find.byKey(const Key('menu_reglas')), findsOneWidget);
      expect(find.byKey(const Key('menu_rendirse')), findsNothing);
    });

    prueba('las reglas de las áreas se pueden consultar', (tester) async {
      await abrirCon(tester, jugando());
      await tap(tester, find.byKey(const Key('menu_partida')));
      await tap(tester, find.byKey(const Key('menu_reglas')));
      expect(find.text('Reglas de las áreas'), findsOneWidget);
      expect(find.text('Todos los números deben ser iguales.'), findsOneWidget);
    });

    prueba('la flecha atrás en plena partida pide confirmar', (tester) async {
      await abrirCon(tester, jugando());
      await tap(tester, find.byKey(const Key('boton_volver')));
      expect(find.text('¿Rendirte y salir?'), findsOneWidget);
      expect(find.byType(PantallaMultijugador), findsOneWidget);

      await tap(tester, find.byKey(const Key('confirmar_no')));
      expect(find.byType(PantallaMultijugador), findsOneWidget);

      await tap(tester, find.byKey(const Key('boton_volver')));
      await tap(tester, find.byKey(const Key('confirmar_si')));
      await transicion(tester);
      expect(find.byType(PantallaMultijugador), findsNothing);
      expect(find.byKey(const Key('abrir')), findsOneWidget);
    });

    prueba('en el lobby la flecha atrás sale sin preguntar', (tester) async {
      await abrirCon(tester, null);
      await tap(tester, find.byTooltip('Volver'));
      await transicion(tester);
      expect(find.byType(PantallaMultijugador), findsNothing);
    });
  });

  group('Fin de partida', () {
    EstadoSala terminada({
      String yo = 'a',
      required List<String> ganadores,
      MotivoFin motivo = MotivoFin.todosTerminaron,
      List<JugadorSala>? jugadores,
    }) => estadoSala(
      yo: yo,
      fase: FaseSala.terminada,
      jugadores:
          jugadores ??
          [jugadorSala('a', puntos: 20), jugadorSala('b', puntos: 8)],
      mensaje: 'Tablero completo.',
      resultado: ResultadoPartida(ganadores: ganadores, motivo: motivo),
    );

    prueba('el ganador lo ve y el anfitrión puede volver al lobby', (
      tester,
    ) async {
      await abrirCon(tester, terminada(ganadores: ['a']));
      expect(find.text('¡Ganaste!'), findsOneWidget);
      expect(find.text('20 pts'), findsOneWidget);
      await tap(tester, find.byKey(const Key('boton_volver_lobby')));
      expect(servidor.ultima.ultimoDe(MsgCliente.volverAlLobby), isNotNull);

      await recibir(tester, estadoSala());
      expect(find.byKey(const Key('codigo_sala')), findsOneWidget);
    });

    prueba('el perdedor espera al anfitrión y puede salir', (tester) async {
      await abrirCon(tester, terminada(yo: 'b', ganadores: ['a']));
      expect(find.text('Perdiste'), findsOneWidget);
      expect(find.byKey(const Key('boton_volver_lobby')), findsNothing);
      expect(find.byKey(const Key('esperando_anfitrion')), findsOneWidget);
      await tap(tester, find.byKey(const Key('boton_salir')));
      await transicion(tester);
      expect(find.byType(PantallaMultijugador), findsNothing);
    });

    prueba('empate', (tester) async {
      await abrirCon(tester, terminada(ganadores: ['a', 'b']));
      expect(find.text('¡Empate!'), findsOneWidget);
    });

    prueba('victoria por rendición del rival', (tester) async {
      await abrirCon(
        tester,
        terminada(
          ganadores: ['a'],
          motivo: MotivoFin.rendicion,
          jugadores: [
            jugadorSala('a'),
            jugadorSala('b', estado: EstadoJugador.concedio),
          ],
        ),
      );
      expect(find.text('¡Ganaste!'), findsOneWidget);
      expect(find.text('Rendido  '), findsOneWidget);
    });

    prueba('quien se rindió ve "Te rendiste"', (tester) async {
      await abrirCon(
        tester,
        terminada(
          yo: 'b',
          ganadores: ['a'],
          motivo: MotivoFin.rendicion,
          jugadores: [
            jugadorSala('a'),
            jugadorSala('b', estado: EstadoJugador.concedio),
          ],
        ),
      );
      expect(find.text('Te rendiste'), findsOneWidget);
    });

    prueba('quien fue dado por abandonado lo ve', (tester) async {
      await abrirCon(
        tester,
        terminada(
          yo: 'b',
          ganadores: ['a'],
          motivo: MotivoFin.abandono,
          jugadores: [
            jugadorSala('a'),
            jugadorSala('b', estado: EstadoJugador.abandono),
          ],
        ),
      );
      expect(find.text('Perdiste por abandono'), findsOneWidget);
    });
  });

  group('Segundo plano', () {
    prueba('al volver a primer plano reconecta y recupera la partida', (
      tester,
    ) async {
      await abrirCon(
        tester,
        estadoSala(fase: FaseSala.jugando, turnoDe: 'b', turno: 3),
      );
      final primera = servidor.ultima;

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await bombear(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await bombear(tester, 10);

      expect(find.byKey(const Key('banda_reconectando')), findsOneWidget);
      expect(find.byType(CeldaGema), findsNWidgets(49));
      expect(servidor.conexiones, hasLength(2));
      expect(primera.cerradoPorCliente, isTrue);

      servidor.ultima.servidorEstado(
        estadoSala(fase: FaseSala.jugando, turnoDe: 'a', turno: 9),
      );
      await bombear(tester);
      expect(find.byKey(const Key('banda_reconectando')), findsNothing);
      expect(find.text('Turno 9'), findsOneWidget);
    });
  });

  group('Pantallas pequeñas', () {
    prueba('la preparación cabe sin desbordes en 320x568', (tester) async {
      await abrirCon(tester, null);
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final ini = mapasOficiales.first.indicesIniciales;
      final t = List<int?>.filled(49, null)..[ini[0]] = 2;
      await recibir(
        tester,
        estadoSala(
          fase: FaseSala.preparacion,
          tablero: t,
          jugadores: [
            for (final id in ['a', 'b', 'c', 'd'])
              jugadorSala(
                id,
                conectado: id != 'c',
                gracia: id == 'c' ? 45 : null,
              ),
          ],
        ),
      );
      expect(find.byKey(const Key('numero_6')), findsOneWidget);
      expect(
        find.byKey(const Key('boton_confirmar_distribucion')),
        findsOneWidget,
      );
      final celdaRect = tester.getRect(find.byKey(const Key('inicial_0')));
      expect(celdaRect.width, greaterThan(24));
      final r = tester.getRect(find.byKey(const Key('numero_1')));
      expect(r.height, greaterThanOrEqualTo(40));
    });

    const tamanos = [Size(320, 568), Size(360, 640)];
    final cuatro = [
      for (final id in ['a', 'b', 'c', 'd'])
        jugadorSala(
          id,
          puntos: 12,
          conectado: id != 'c',
          gracia: id == 'c' ? 45 : null,
        ),
    ];

    for (final tam in tamanos) {
      final nombre = '${tam.width.toInt()}x${tam.height.toInt()}';

      prueba('entrada, lobby y partida sin desbordes en $nombre', (
        tester,
      ) async {
        await abrirCon(tester, null);
        await tester.binding.setSurfaceSize(tam);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await bombear(tester);
        expect(find.byKey(const Key('boton_crear_sala')), findsOneWidget);

        // Con el teclado abierto el campo del código sigue a la vista.
        // Se toca el campo con el teclado cerrado y luego aparece el teclado
        // (260 px lógicos; los insets van en píxeles físicos): el campo debe
        // quedar a la vista, no tapado.
        await tester.tap(find.byKey(const Key('campo_codigo')));
        await bombear(tester);
        final teclado = 260 * tester.view.devicePixelRatio;
        tester.view.viewInsets = FakeViewPadding(bottom: teclado);
        addTearDown(tester.view.resetViewInsets);
        await bombear(tester, 400);
        final campo = tester.getRect(find.byKey(const Key('campo_codigo')));
        expect(campo.bottom, lessThanOrEqualTo(tam.height - 260));
        tester.view.resetViewInsets();

        await recibir(tester, estadoSala(jugadores: cuatro));
        expect(find.byKey(const Key('codigo_sala')), findsOneWidget);
        // Los botones de abajo se alcanzan con scroll.
        await tester.scrollUntilVisible(
          find.byKey(const Key('boton_salir_sala')),
          100,
          scrollable: find.byType(Scrollable).first,
        );

        await recibir(
          tester,
          estadoSala(
            fase: FaseSala.jugando,
            turnoDe: 'a',
            dados: [1, 2],
            jugadores: cuatro,
            mensaje: 'A sacó 1 y 2.',
          ),
        );
        expect(find.byType(CeldaGema), findsNWidgets(49));
        // El tablero conserva un tamaño táctil razonable.
        final celdaRect = tester.getRect(find.byKey(const Key('celda_0')));
        // Casillas de al menos ~24 px aun en el móvil más pequeño.
        expect(celdaRect.width, greaterThan(tam.height < 600 ? 24 : 28));
        for (final k in ['boton_tirar_dados', 'boton_pasar_turno']) {
          final r = tester.getRect(find.byKey(Key(k)));
          expect(r.height, greaterThanOrEqualTo(40));
        }

        await recibir(
          tester,
          estadoSala(
            fase: FaseSala.terminada,
            jugadores: cuatro,
            mensaje: 'Tablero completo. Gana A.',
            resultado: const ResultadoPartida(
              ganadores: ['a'],
              motivo: MotivoFin.todosTerminaron,
            ),
          ),
        );
        expect(find.byKey(const Key('titulo_resultado')), findsOneWidget);
      });
    }
  });

  group('Conexión', () {
    prueba('al cortarse muestra la banda, conserva la partida y se recupera', (
      tester,
    ) async {
      await abrirCon(tester, estadoSala(fase: FaseSala.jugando, turnoDe: 'b'));
      expect(find.byKey(const Key('banda_reconectando')), findsNothing);

      servidor.ultima.servidorCierra();
      await bombear(tester, 5);
      expect(find.byKey(const Key('banda_reconectando')), findsOneWidget);
      expect(find.textContaining('Reconectando'), findsOneWidget);
      expect(find.byType(CeldaGema), findsNWidgets(49));

      // Mientras no hay conexión, las acciones no se envían.
      await bombear(tester, 30);
      expect(servidor.conexiones, hasLength(2));
      servidor.ultima.servidorEstado(
        estadoSala(fase: FaseSala.jugando, turnoDe: 'a', turno: 5),
      );
      await bombear(tester);
      expect(find.byKey(const Key('banda_reconectando')), findsNothing);
      expect(find.text('Turno 5'), findsOneWidget);
    });

    prueba('un fallo de sesión ofrece iniciar sesión de nuevo', (tester) async {
      await abrir(tester);
      servidor.ultima.servidorEnvia({
        'tipo': MsgServidor.error,
        'codigo': CodigoError.autenticacion,
        'mensaje': 'Sesión inválida o expirada.',
        'fatal': true,
      });
      await bombear(tester);
      expect(find.byKey(const Key('error_fatal')), findsOneWidget);
      expect(find.text('Sesión inválida o expirada.'), findsOneWidget);
      expect(find.byKey(const Key('boton_reintentar')), findsNothing);

      await tap(tester, find.byKey(const Key('boton_volver_acceso')));
      await transicion(tester);
      expect(find.byType(PantallaMultijugador), findsNothing);
      expect(find.byKey(const Key('abrir')), findsOneWidget);
    });

    prueba('si se agotan los reintentos se puede volver a intentar', (
      tester,
    ) async {
      await abrir(tester);
      servidor.ultima.servidorEnvia({'tipo': MsgServidor.sesionReemplazada});
      await bombear(tester);
      expect(find.byKey(const Key('error_fatal')), findsOneWidget);
      expect(find.textContaining('otro lugar'), findsOneWidget);

      await tap(tester, find.byKey(const Key('boton_reintentar')));
      expect(servidor.conexiones, hasLength(2));
      expect(find.text('Conectando…'), findsOneWidget);
      servidor.ultima.servidorEnvia({'tipo': MsgServidor.sinSala});
      await bombear(tester);
      expect(find.byKey(const Key('boton_crear_sala')), findsOneWidget);
    });
  });
}
