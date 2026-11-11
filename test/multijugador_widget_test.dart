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

    prueba('solo el Nivel 1 está disponible; el anfitrión expulsa', (
      tester,
    ) async {
      await abrirCon(tester, estadoSala());
      // Los niveles 2, 3 y 4 salen como no disponibles y no se pueden elegir.
      for (final i in [1, 2, 3]) {
        expect(
          find.text('Nivel ${i + 1} (no disponible)'),
          findsOneWidget,
          reason: 'mapa $i',
        );
        await tap(tester, find.byKey(Key('mapa_$i')));
      }
      expect(servidor.ultima.ultimoDe(MsgCliente.elegirMapa), isNull);
      expect(find.text('Nivel 1'), findsWidgets);
      await tap(tester, find.byKey(const Key('mapa_0')));
      expect(servidor.ultima.ultimoDe(MsgCliente.elegirMapa), {
        'tipo': MsgCliente.elegirMapa,
        'mapa': 0,
      });
      await recibir(tester, estadoSala()); // el servidor responde

      await tester.scrollUntilVisible(
        find.byKey(const Key('expulsar_b')),
        100,
        scrollable: find.byType(Scrollable).first,
      );
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

  group('Lobby: jugadores y meta', () {
    prueba('muestra la meta provisional según los jugadores y hasta 5', (
      tester,
    ) async {
      EstadoSala lobby(int n) => estadoSala(
        jugadores: [
          for (var i = 0; i < n; i++) jugadorSala(String.fromCharCode(97 + i)),
        ],
      );
      await abrirCon(tester, lobby(2));
      expect(find.text('JUGADORES (2/5)'), findsOneWidget);
      for (final (n, meta) in [(2, 26), (3, 24), (4, 22), (5, 20)]) {
        await recibir(tester, lobby(n));
        expect(find.text('JUGADORES ($n/5)'), findsOneWidget);
        expect(
          find.textContaining('Meta con $n jugadores: $meta puntos'),
          findsOneWidget,
        );
      }
      expect(find.byKey(const Key('jugador_e')), findsOneWidget);
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
        estadoSala(yo: yo, fase: FaseSala.jugando, jugadores: js);

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
    /// Ronda abierta con dados si se dan [dados]; si no, esperando tirada.
    EstadoSala jugando({
      String yo = 'a',
      List<int>? dados,
      List<int?>? tablero,
      List<JugadorSala>? jugadores,
      Map<String, Resolucion>? resoluciones,
      int ronda = 1,
      int? segundos,
    }) => estadoSala(
      yo: yo,
      fase: FaseSala.jugando,
      dados: dados,
      tablero: tablero,
      jugadores: jugadores,
      resoluciones: resoluciones,
      ronda: ronda,
      segundos: segundos,
      mensaje: 'Empieza la partida.',
    );

    Text texto(WidgetTester tester, String clave) =>
        tester.widget<Text>(find.byKey(Key(clave)));

    prueba('esperando tirada: muestro la ronda y cualquiera puede tirar', (
      tester,
    ) async {
      await abrirCon(tester, jugando(ronda: 4));
      expect(find.byType(CeldaGema), findsNWidgets(49));
      expect(find.text('Ronda 4'), findsOneWidget);
      expect(find.textContaining('Turno'), findsNothing);
      expect(
        find.text('Esperando tirada. Cualquiera puede lanzar los dados.'),
        findsOneWidget,
      );
      expect(habilitado(tester, 'boton_tirar_dados'), isTrue);
      expect(find.byKey(const Key('boton_confirmar_jugada')), findsNothing);
      expect(find.byKey(const Key('boton_pasar_ronda')), findsNothing);
      expect(find.byKey(const Key('tiempo_ronda')), findsNothing);

      // Quien no es el anfitrión también puede lanzar.
      await tap(tester, find.byKey(const Key('boton_tirar_dados')));
      expect(servidor.ultima.ultimoDe(MsgCliente.tirar), {
        'tipo': MsgCliente.tirar,
        'ronda': 4,
      });
    });

    prueba('rendidos y terminados no pueden lanzar', (tester) async {
      await abrirCon(
        tester,
        jugando(
          jugadores: [
            jugadorSala('a', estado: EstadoJugador.concedio),
            jugadorSala('b'),
          ],
        ),
      );
      expect(habilitado(tester, 'boton_tirar_dados'), isFalse);
      await recibir(
        tester,
        jugando(
          jugadores: [
            jugadorSala('a', estado: EstadoJugador.terminado),
            jugadorSala('b'),
          ],
        ),
      );
      expect(habilitado(tester, 'boton_tirar_dados'), isFalse);
    });

    prueba('con dados: previsualizo, y solo "Confirmar jugada" envía', (
      tester,
    ) async {
      await abrirCon(tester, jugando(dados: [1, 2], segundos: 42));
      expect(find.text('Ronda 1'), findsOneWidget);
      expect(find.text('Tiempo de la ronda: 42s'), findsOneWidget);
      expect(find.text('Pendientes: Tú, B'), findsOneWidget);
      expect(find.byKey(const Key('boton_tirar_dados')), findsNothing);
      expect(habilitado(tester, 'boton_confirmar_jugada'), isFalse);
      expect(habilitado(tester, 'boton_pasar_ronda'), isTrue);

      // Ancla: dado 1. La casilla 2 tiene un 1; sus vecinos 1 y 3 valen para
      // el 2, y la 9 (azul con un 1) no.
      await tap(tester, find.byKey(const Key('dado_0')));
      expect(celda(tester, 1).esDestino, isTrue);
      expect(celda(tester, 3).esDestino, isTrue);
      expect(celda(tester, 9).esDestino, isFalse);
      expect(habilitado(tester, 'boton_confirmar_jugada'), isFalse);

      // Tocar el mismo dado quita la selección.
      await tap(tester, find.byKey(const Key('dado_0')));
      expect(celda(tester, 1).esDestino, isFalse);
      await tap(tester, find.byKey(const Key('dado_0')));

      // Elegir casilla es solo una previsualización: no se envía nada, no cambia
      // el tablero oficial ni la puntuación.
      await tap(tester, find.byKey(const Key('celda_1')));
      expect(celda(tester, 1).seleccionada, isTrue);
      expect(
        celda(tester, 1).valor,
        isNull,
        reason: 'el tablero oficial no cambia',
      );
      expect(texto(tester, 'puntos_a').data, '0');
      expect(
        servidor.ultima.tiposEnviados,
        isNot(contains(MsgCliente.confirmarJugada)),
      );
      expect(habilitado(tester, 'boton_confirmar_jugada'), isTrue);

      // Cambiar de casilla mueve la previsualización.
      await tap(tester, find.byKey(const Key('celda_3')));
      expect(celda(tester, 3).seleccionada, isTrue);
      expect(celda(tester, 1).seleccionada, isFalse);

      await tap(tester, find.byKey(const Key('boton_confirmar_jugada')));
      expect(servidor.ultima.ultimoDe(MsgCliente.confirmarJugada), {
        'tipo': MsgCliente.confirmarJugada,
        'ronda': 1,
        'indice': 3,
        'ancla': 0,
      });
    });

    prueba('tocar una casilla que no es destino no previsualiza ni envía', (
      tester,
    ) async {
      await abrirCon(tester, jugando(dados: [1, 2]));
      await tap(tester, find.byKey(const Key('dado_0')));
      await tap(tester, find.byKey(const Key('celda_9')));
      await tap(tester, find.byKey(const Key('celda_40')));
      expect(celda(tester, 9).seleccionada, isFalse);
      expect(habilitado(tester, 'boton_confirmar_jugada'), isFalse);
      expect(servidor.ultima.ultimoDe(MsgCliente.confirmarJugada), isNull);
    });

    prueba('"Pasar esta ronda" envía el pase aunque haya jugadas', (
      tester,
    ) async {
      await abrirCon(tester, jugando(dados: [1, 2]));
      expect(habilitado(tester, 'boton_pasar_ronda'), isTrue);
      await tap(tester, find.byKey(const Key('boton_pasar_ronda')));
      expect(servidor.ultima.ultimoDe(MsgCliente.pasarRonda), {
        'tipo': MsgCliente.pasarRonda,
        'ronda': 1,
      });
    });

    prueba('sin jugadas con estos dados se avisa y se puede pasar', (
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
      expect(
        find.textContaining('No tienes jugadas con estos dados'),
        findsOneWidget,
      );
      expect(habilitado(tester, 'boton_pasar_ronda'), isTrue);
      await tap(tester, find.byKey(const Key('boton_pasar_ronda')));
      expect(servidor.ultima.ultimoDe(MsgCliente.pasarRonda), isNotNull);
    });

    prueba('tras confirmar o pasar espero a los demás y veo quién falta', (
      tester,
    ) async {
      final tablero = tableroInicial()..[1] = 2;
      await abrirCon(
        tester,
        jugando(
          dados: [1, 2],
          tablero: tablero,
          resoluciones: {'a': Resolucion.confirmo, 'b': Resolucion.pendiente},
        ),
      );
      expect(find.text('Esperando a los demás'), findsOneWidget);
      expect(find.text('Pendientes: B'), findsOneWidget);
      expect(find.byKey(const Key('boton_confirmar_jugada')), findsNothing);
      expect(find.byKey(const Key('boton_pasar_ronda')), findsNothing);
      expect(find.byKey(const Key('boton_tirar_dados')), findsNothing);
      // Mi tablero sigue visible con mi jugada ya aplicada.
      expect(celda(tester, 1).valor, 2);
      expect(texto(tester, 'estado_a').data, 'Jugó');
      expect(texto(tester, 'estado_b').data, 'Pendiente');

      await recibir(
        tester,
        jugando(
          dados: [1, 2],
          tablero: tablero,
          resoluciones: {'a': Resolucion.paso, 'b': Resolucion.pendiente},
        ),
      );
      expect(texto(tester, 'estado_a').data, 'Pasó');
      expect(find.text('Esperando a los demás'), findsOneWidget);
    });

    prueba('al cerrarse la ronda se olvida la previsualización', (
      tester,
    ) async {
      await abrirCon(tester, jugando(dados: [1, 2]));
      await tap(tester, find.byKey(const Key('dado_0')));
      await tap(tester, find.byKey(const Key('celda_1')));
      expect(celda(tester, 1).seleccionada, isTrue);

      final tablero = tableroInicial()..[1] = 2;
      await recibir(tester, jugando(tablero: tablero, ronda: 2));
      expect(find.text('Ronda 2'), findsOneWidget);
      expect(habilitado(tester, 'boton_tirar_dados'), isTrue);
      await recibir(tester, jugando(tablero: tablero, ronda: 2, dados: [1, 2]));
      expect(celda(tester, 3).esDestino, isFalse, reason: 'sin ancla elegida');
      expect(celda(tester, 1).seleccionada, isFalse);
      expect(habilitado(tester, 'boton_confirmar_jugada'), isFalse);
    });

    prueba('reconectar con la jugada ya aceptada la recupera exactamente', (
      tester,
    ) async {
      final tablero = tableroInicial()..[1] = 2;
      final aceptada = jugando(
        dados: [1, 2],
        tablero: tablero,
        resoluciones: {'a': Resolucion.confirmo, 'b': Resolucion.pendiente},
        segundos: 33,
      );
      await abrirCon(tester, aceptada);
      servidor.ultima.servidorCierra();
      await bombear(tester, 100);
      expect(find.byKey(const Key('banda_reconectando')), findsOneWidget);
      expect(celda(tester, 1).valor, 2, reason: 'el tablero no se pierde');
      await recibir(tester, aceptada);
      expect(find.byKey(const Key('banda_reconectando')), findsNothing);
      expect(find.text('Esperando a los demás'), findsOneWidget);
      expect(celda(tester, 1).valor, 2);
      expect(find.byKey(const Key('boton_confirmar_jugada')), findsNothing);
    });

    prueba('el plazo de la ronda se ve y se pone en rojo al final', (
      tester,
    ) async {
      await abrirCon(tester, jugando(dados: [1, 2], segundos: 8));
      expect(find.text('Tiempo de la ronda: 8s'), findsOneWidget);
      expect(texto(tester, 'tiempo_ronda').style!.color, Colors.redAccent);
    });

    prueba('quien terminó su tablero no resuelve y espera', (tester) async {
      await abrirCon(
        tester,
        jugando(
          dados: [1, 2],
          jugadores: [
            jugadorSala('a', estado: EstadoJugador.terminado, puntos: 20),
            jugadorSala('b'),
          ],
        ),
      );
      expect(find.byKey(const Key('boton_pasar_ronda')), findsNothing);
      expect(find.byKey(const Key('boton_confirmar_jugada')), findsNothing);
      expect(texto(tester, 'estado_a').data, 'Terminado');
    });

    prueba('muestro mi puntuación sobre la meta y los premios de cada grupo', (
      tester,
    ) async {
      await abrirCon(
        tester,
        estadoSala(
          fase: FaseSala.jugando,
          meta: 26,
          jugadores: [
            jugadorSala('a', puntos: 18),
            jugadorSala('b', puntos: 7),
          ],
        ),
      );
      expect(find.text('18 / 26'), findsOneWidget);
      // Un chip por cada uno de los 9 grupos, con el próximo premio.
      final grupos = mapasOficiales.first.gruposPremio;
      expect(grupos, hasLength(9));
      for (final g in grupos) {
        expect(find.byKey(Key('premio_${g.id}')), findsOneWidget);
      }
      Text chip(String id) => tester.widget<Text>(
        find.descendant(
          of: find.byKey(Key('premio_$id')),
          matching: find.byType(Text),
        ),
      );
      expect(chip('N1-a0').data, '8'); // amarillo
      expect(chip('N1-a1').data, '4'); // verde
      expect(chip('N1-a2').data, '7'); // azul
      expect(chip('N1-a15').data, '6'); // rojo
    });

    prueba('los premios usados avanzan, se marcan agotados y los míos', (
      tester,
    ) async {
      EstadoSala con(
        List<ReclamacionGrupo> r, {
        List<String> pend = const [],
      }) => estadoSala(
        fase: FaseSala.jugando,
        reclamaciones: r,
        misPendientes: pend,
      );
      Text chip(String id) => tester.widget<Text>(
        find.descendant(
          of: find.byKey(Key('premio_$id')),
          matching: find.byType(Text),
        ),
      );
      await abrirCon(tester, con(const []));
      await recibir(
        tester,
        con(const [
          ReclamacionGrupo(
            grupo: 'N1-a2',
            niveles: [
              ['b'],
            ],
          ),
          ReclamacionGrupo(
            grupo: 'N1-a34',
            niveles: [
              ['b'],
              ['c'],
              ['d'],
            ],
          ),
        ]),
      );
      expect(chip('N1-a2').data, '5', reason: 'el siguiente nivel de 7/5/3');
      expect(chip('N1-a34').data, '0', reason: 'agotado');
      await recibir(
        tester,
        con(
          const [
            ReclamacionGrupo(
              grupo: 'N1-a2',
              niveles: [
                ['a'],
              ],
            ),
          ],
          pend: const ['N1-a0'],
        ),
      );
      expect(chip('N1-a2').data, '✓', reason: 'ya lo completé');
      expect(chip('N1-a0').data, '⏳', reason: 'pendiente de liquidar');
    });

    prueba('lo completado en la ronda se ve como pendiente, no como puntos', (
      tester,
    ) async {
      await abrirCon(
        tester,
        estadoSala(
          fase: FaseSala.jugando,
          dados: [1, 2],
          misPendientes: const ['N1-a2'],
          jugadores: [jugadorSala('a', puntos: 3), jugadorSala('b')],
        ),
      );
      expect(
        find.textContaining('Completaste: Azul (casilla 2)'),
        findsOneWidget,
      );
      expect(
        find.textContaining('se premia al cerrar la ronda'),
        findsOneWidget,
      );
      expect(texto(tester, 'puntos_a').data, '3', reason: 'sin sumar todavía');
    });

    prueba('al cerrar la ronda se muestra el resultado de la liquidación', (
      tester,
    ) async {
      await abrirCon(
        tester,
        estadoSala(
          fase: FaseSala.jugando,
          ronda: 4,
          liquidacion: const [
            Adjudicacion(
              ronda: 3,
              jugador: 'a',
              grupo: 'N1-a2',
              nivel: 1,
              puntos: 7,
            ),
            Adjudicacion(
              ronda: 3,
              jugador: 'b',
              grupo: 'N1-a2',
              nivel: 1,
              puntos: 7,
            ),
            Adjudicacion(
              ronda: 3,
              jugador: 'c',
              grupo: 'N1-a34',
              nivel: 0,
              puntos: 0,
            ),
          ],
          jugadores: [jugadorSala('a'), jugadorSala('b'), jugadorSala('c')],
        ),
      );
      final t = texto(tester, 'liquidacion_ronda').data!;
      expect(t, startsWith('Premios de la ronda 3:'));
      expect(t, contains('Tú +7 (1.º) en Azul (casilla 2)'));
      expect(t, contains('B +7 (1.º)'));
      expect(t, contains('C sin premio'));
    });

    prueba('la hoja de premios detalla niveles, empates y agotados', (
      tester,
    ) async {
      await abrirCon(
        tester,
        estadoSala(
          fase: FaseSala.jugando,
          reclamaciones: const [
            ReclamacionGrupo(
              grupo: 'N1-a2',
              niveles: [
                ['a', 'b'],
                ['c'],
              ],
            ),
          ],
          jugadores: [jugadorSala('a'), jugadorSala('b'), jugadorSala('c')],
        ),
      );
      await tap(tester, find.byKey(const Key('banda_premios')));
      final d = texto(tester, 'detalle_N1-a2').data!;
      expect(d, contains('1.º 7 pts: Tú y B'));
      expect(d, contains('2.º 5 pts: C'));
      expect(d, contains('3.º 3 pts: libre'));
    });

    prueba('al terminar por meta se muestra la meta y el resultado', (
      tester,
    ) async {
      await abrirCon(
        tester,
        estadoSala(
          fase: FaseSala.terminada,
          meta: 26,
          mensaje: 'Se alcanzó la meta de 26 puntos. Gana A.',
          jugadores: [
            jugadorSala('a', puntos: 31),
            jugadorSala('b', puntos: 20),
          ],
          resultado: const ResultadoPartida(
            ganadores: ['a'],
            motivo: MotivoFin.meta,
          ),
        ),
      );
      expect(find.text('Meta: 26 puntos'), findsOneWidget);
      expect(find.text('¡Ganaste!'), findsOneWidget);
      expect(find.textContaining('Se alcanzó la meta de 26'), findsOneWidget);
    });

    prueba('el marcador muestra a todos y quién sigue pendiente', (
      tester,
    ) async {
      await abrirCon(
        tester,
        jugando(
          dados: [1, 2],
          resoluciones: {'a': Resolucion.confirmo, 'b': Resolucion.pendiente},
          jugadores: [jugadorSala('a', puntos: 7), jugadorSala('b', puntos: 4)],
        ),
      );
      expect(find.byKey(const Key('puntos_a')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('puntos_a'))).data, '7');
      expect(tester.widget<Text>(find.byKey(const Key('puntos_b'))).data, '4');
      expect(texto(tester, 'estado_a').data, 'Jugó');
      expect(texto(tester, 'estado_b').data, 'Pendiente');
    });

    prueba('un rival desconectado se ve con su cuenta atrás', (tester) async {
      await abrirCon(
        tester,
        jugando(
          dados: [1, 2],
          jugadores: [
            jugadorSala('a'),
            jugadorSala('b', conectado: false, gracia: 40),
          ],
        ),
      );
      final texto = tester.widget<Text>(find.byKey(const Key('estado_b')));
      expect(texto.data, contains('Sin conexión 40s'));
      expect(texto.data, startsWith('Pendiente'), reason: 'conserva su estado');
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
      await abrirCon(tester, estadoSala(fase: FaseSala.jugando));
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
        estadoSala(fase: FaseSala.jugando, ronda: 9),
      );
      await bombear(tester);
      expect(find.byKey(const Key('banda_reconectando')), findsNothing);
      expect(find.text('Ronda 9'), findsOneWidget);
    });
  });

  group('Pantallas pequeñas', () {
    prueba('cinco jugadores caben en 320x568 con meta y premios', (
      tester,
    ) async {
      await abrirCon(tester, null);
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final cinco = [
        for (final id in ['a', 'b', 'c', 'd', 'e'])
          jugadorSala(
            id,
            puntos: 12,
            conectado: id != 'c',
            gracia: id == 'c' ? 45 : null,
          ),
      ];
      await recibir(
        tester,
        estadoSala(
          fase: FaseSala.jugando,
          dados: [1, 2],
          jugadores: cinco,
          misPendientes: const ['N1-a2'],
        ),
      );
      expect(find.byKey(const Key('jugador_e')), findsOneWidget);
      expect(
        find.text('12 / 20'),
        findsOneWidget,
        reason: 'meta de 5 jugadores',
      );
      expect(find.byType(CeldaGema), findsNWidgets(49));
      final celdaRect = tester.getRect(find.byKey(const Key('celda_0')));
      expect(celdaRect.width, greaterThan(22));
      // Los premios caben en una sola fila de chips.
      final primero = tester.getRect(find.byKey(const Key('premio_N1-a0')));
      final ultimo = tester.getRect(find.byKey(const Key('premio_N1-a34')));
      expect(ultimo.right, lessThanOrEqualTo(320));
      expect((primero.top - ultimo.top).abs(), lessThan(1));
      for (final k in ['boton_confirmar_jugada', 'boton_pasar_ronda']) {
        expect(
          tester.getRect(find.byKey(Key(k))).height,
          greaterThanOrEqualTo(40),
        );
      }
    });

    prueba('la preparación con cinco jugadores no desborda en 320x568', (
      tester,
    ) async {
      await abrirCon(tester, null);
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await recibir(
        tester,
        estadoSala(
          fase: FaseSala.preparacion,
          jugadores: [
            for (final id in ['a', 'b', 'c', 'd', 'e'])
              jugadorSala(id, estado: EstadoJugador.preparando),
          ],
        ),
      );
      expect(find.byKey(const Key('jugador_e')), findsOneWidget);
      expect(
        find.byKey(const Key('boton_confirmar_distribucion')),
        findsOneWidget,
      );
    });

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
        for (final k in ['boton_confirmar_jugada', 'boton_pasar_ronda']) {
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
      await abrirCon(tester, estadoSala(fase: FaseSala.jugando));
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
        estadoSala(fase: FaseSala.jugando, ronda: 5),
      );
      await bombear(tester);
      expect(find.byKey(const Key('banda_reconectando')), findsNothing);
      expect(find.text('Ronda 5'), findsOneWidget);
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
