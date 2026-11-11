import 'dart:convert';

import 'package:brilliant_nucleo/brilliant_nucleo.dart';
import 'package:test/test.dart';

void main() {
  const g = GrupoPremio(id: 'T-g', casillas: [1, 2], premios: [8, 6, 4]);
  LibroPremios libro() => LibroPremios(const [
    g,
    GrupoPremio(id: 'T-h', casillas: [3], premios: [4, 3, 2]),
  ]);

  int total(List<Adjudicacion> a, String j) =>
      a.where((x) => x.jugador == j).fold(0, (s, x) => s + x.puntos);

  group('Metas', () {
    test('2, 3, 4 y 5 jugadores', () {
      expect([for (var n = 2; n <= 5; n++) metaPara(n)], [26, 24, 22, 20]);
      expect(metaPara(1), isNull);
      expect(metaPara(6), isNull);
      expect(minJugadoresEnLinea, 2);
      expect(maxJugadoresEnLinea, 5);
    });
  });

  group('Grupos de premio del Nivel 1', () {
    final m = mapasOficiales.first;
    test('cubren las 49 casillas sin solaparse y con ids únicos', () {
      final todas = [for (final x in m.gruposPremio) ...x.casillas];
      expect(todas, hasLength(49));
      expect(todas.toSet(), hasLength(49));
      expect(m.gruposPremio.map((x) => x.id).toSet(), hasLength(9));
      expect(m.disponibleEnLinea, isTrue);
    });

    test('premios de cada grupo y casilla mínima en el id', () {
      final por = {for (final x in m.gruposPremio) x.id: x};
      expect(por['N1-a0']!.casillas, [0, 6, 24, 42, 48]);
      expect(por['N1-a0']!.premios, [8, 6, 4]);
      for (final id in ['N1-a1', 'N1-a13']) {
        expect(por[id]!.premios, [4, 3, 2]);
      }
      for (final id in ['N1-a2', 'N1-a34']) {
        expect(por[id]!.premios, [7, 5, 3]);
      }
      for (final id in ['N1-a15', 'N1-a32', 'N1-a3', 'N1-a23']) {
        expect(por[id]!.premios, [6, 4, 2]);
      }
      for (final x in m.gruposPremio) {
        final min = x.casillas.reduce((a, b) => a < b ? a : b);
        expect(x.id, 'N1-a$min');
        expect(x.niveles, 3);
      }
    });

    test('cada grupo es una unidad independiente del color', () {
      // Dos verdes distintos: tienen id, casillas y premio propios.
      final verdes = m.gruposPremio.where(
        (x) => x.id == 'N1-a1' || x.id == 'N1-a13',
      );
      expect(verdes.map((x) => x.casillas).toSet(), hasLength(2));
    });

    test('los demás niveles no están disponibles en línea (pero siguen existiendo)', () {
      expect(
        [for (final x in mapasOficiales) x.disponibleEnLinea],
        [true, false, false, false],
      );
      expect(mapasOficiales, hasLength(4));
    });

    test('ninguna región del Nivel 1 incluye ya los iniciales completos', () {
      // Con la agrupación del Nivel 1 ningún grupo nace completo: todos
      // tienen casillas que no son iniciales.
      for (final x in m.gruposPremio) {
        expect(
          x.casillas.every(m.indicesIniciales.contains),
          isFalse,
          reason: x.id,
        );
      }
    });

    test('un grupo se completa cuando todas sus casillas están ocupadas', () {
      final t = List<int?>.filled(49, null);
      final a2 = m.gruposPremio.firstWhere((x) => x.id == 'N1-a2');
      for (final i in a2.casillas.take(3)) {
        t[i] = 1;
      }
      expect(a2.completo(t), isFalse);
      t[a2.casillas.last] = 1;
      expect(a2.completo(t), isTrue);
      expect(libro2(m).gruposCompletos(t), ['N1-a2']);
    });
  });

  group('LibroPremios', () {
    test('primer, segundo y tercer nivel por rondas distintas', () {
      final l = libro();
      expect(
        total(
          l.liquidar(1, {
            'T-g': {'a'},
          }),
          'a',
        ),
        8,
      );
      expect(
        total(
          l.liquidar(2, {
            'T-g': {'b'},
          }),
          'b',
        ),
        6,
      );
      expect(
        total(
          l.liquidar(3, {
            'T-g': {'c'},
          }),
          'c',
        ),
        4,
      );
    });

    test('un cuarto jugador completa el grupo sin premio (0 puntos)', () {
      final l = libro();
      for (final (i, j) in ['a', 'b', 'c'].indexed) {
        l.liquidar(i + 1, {
          'T-g': {j},
        });
      }
      final adj = l.liquidar(4, {
        'T-g': {'d'},
      });
      expect(adj.single.nivel, 0);
      expect(adj.single.puntos, 0);
      expect(l.reclamaciones.first.sinPremio, ['d']);
      expect(l.yaReclamo('T-g', 'd'), isTrue);
    });

    test(
      'empate en el primer nivel: comparten y el siguiente grupo recibe el 2.º',
      () {
        final l = libro();
        final r1 = l.liquidar(1, {
          'T-g': {'a', 'b'},
        });
        expect(r1.map((x) => (x.jugador, x.nivel, x.puntos)), [
          ('a', 1, 8),
          ('b', 1, 8),
        ]);
        final r2 = l.liquidar(2, {
          'T-g': {'c'},
        });
        expect(r2.single.nivel, 2);
        expect(r2.single.puntos, 6);
        final r3 = l.liquidar(3, {
          'T-g': {'d'},
        });
        expect(r3.single.nivel, 3);
        expect(r3.single.puntos, 4);
        expect(
          l
              .liquidar(4, {
                'T-g': {'e'},
              })
              .single
              .nivel,
          0,
        );
      },
    );

    test('cuatro a la vez: los cuatro reciben el primer premio', () {
      final l = libro();
      final r = l.liquidar(1, {
        'T-g': {'a', 'b', 'c', 'd'},
      });
      expect(r.map((x) => x.nivel).toSet(), {1});
      expect(r.map((x) => x.puntos).toSet(), {8});
      expect(l.reclamaciones.first.niveles, hasLength(1));
    });

    test('empate en el segundo y en el tercer nivel', () {
      final l = libro();
      l.liquidar(1, {
        'T-g': {'a'},
      });
      final r2 = l.liquidar(2, {
        'T-g': {'b', 'c'},
      });
      expect(r2.map((x) => x.puntos), [6, 6]);
      final r3 = l.liquidar(3, {
        'T-g': {'d', 'e'},
      });
      expect(r3.map((x) => x.puntos), [4, 4]);
      expect(
        l
            .liquidar(4, {
              'T-g': {'f'},
            })
            .single
            .puntos,
        0,
      );
    });

    test('un jugador solo puede cobrar una vez por grupo', () {
      final l = libro();
      l.liquidar(1, {
        'T-g': {'a'},
      });
      expect(
        l.liquidar(2, {
          'T-g': {'a'},
        }),
        isEmpty,
      );
      expect(l.reclamaciones.first.niveles, [
        ['a'],
      ]);
      // En otro grupo sí cobra.
      expect(
        l
            .liquidar(3, {
              'T-h': {'a'},
            })
            .single
            .puntos,
        4,
      );
    });

    test('el resultado no depende del orden de los datos', () {
      List<Object?> corre(Map<String, Set<String>> m) {
        final l = libro();
        final adj = l.liquidar(1, m);
        return [
          [
            for (final a in adj)
              '${a.jugador}|${a.grupo}|${a.nivel}|${a.puntos}',
          ],
          l.reclamaciones.map((r) => r.toJson()).toList(),
        ];
      }

      final a = corre({
        'T-g': {'a', 'b'},
        'T-h': {'c'},
      });
      final b = corre({
        'T-h': {'c'},
        'T-g': {'b', 'a'},
      });
      expect(jsonEncode(a), jsonEncode(b));
    });

    test('varios grupos en la misma liquidación se resuelven por separado', () {
      final l = libro();
      final r = l.liquidar(1, {
        'T-g': {'a'},
        'T-h': {'a', 'b'},
      });
      expect(total(r, 'a'), 12);
      expect(total(r, 'b'), 4);
    });

    test('un grupo desconocido o sin finalizaciones nuevas no hace nada', () {
      final l = libro();
      expect(
        l.liquidar(1, {
          'X': {'a'},
        }),
        isEmpty,
      );
      expect(l.liquidar(1, {}), isEmpty);
      expect(l.reclamaciones.every((r) => r.niveles.isEmpty), isTrue);
    });

    test('adjudicaciones y reclamaciones viajan por JSON', () {
      final l = libro();
      final adj = l.liquidar(2, {
        'T-g': {'a', 'b'},
      });
      final a = Adjudicacion.fromJson(
        (jsonDecode(jsonEncode(adj.first.toJson())) as Map)
            .cast<String, Object?>(),
      );
      expect((a.ronda, a.jugador, a.nivel, a.puntos), (2, 'a', 1, 8));
      final r = ReclamacionGrupo.fromJson(
        (jsonDecode(jsonEncode(l.reclamaciones.first.toJson())) as Map)
            .cast<String, Object?>(),
      );
      expect(r.niveles, [
        ['a', 'b'],
      ]);
    });
  });

  group('EstadoSala con premios', () {
    test(
      'meta, reclamaciones, pendientes y liquidación sobreviven al JSON',
      () {
        final e = EstadoSala(
          yo: 'a',
          codigo: 'ABC234',
          fase: FaseSala.jugando,
          mapa: 0,
          maxJugadores: 5,
          anfitrion: 'a',
          jugadores: const [
            JugadorSala(id: 'a', nombre: 'Ana', conectado: true, puntos: 7),
            JugadorSala(id: 'b', nombre: 'Beto', conectado: true),
          ],
          meta: 26,
          reclamaciones: const [
            ReclamacionGrupo(
              grupo: 'N1-a2',
              niveles: [
                ['a'],
              ],
            ),
          ],
          misPendientes: const ['N1-a0'],
          liquidacion: const [
            Adjudicacion(
              ronda: 3,
              jugador: 'a',
              grupo: 'N1-a2',
              nivel: 1,
              puntos: 7,
            ),
          ],
        );
        final copia = EstadoSala.fromJson(
          (jsonDecode(jsonEncode(e.toJson())) as Map).cast<String, Object?>(),
        );
        expect(copia.meta, 26);
        expect(copia.reclamacionDe('N1-a2').niveles, [
          ['a'],
        ]);
        expect(copia.reclamacionDe('N1-zz').niveles, isEmpty);
        expect(copia.misPendientes, ['N1-a0']);
        expect(copia.liquidacion.single.puntos, 7);
        expect(MotivoFin.desde('meta'), MotivoFin.meta);
      },
    );
  });
}

LibroPremios libro2(MapaOficial m) => LibroPremios(m.gruposPremio);
