import 'dart:math';

import 'package:brilliant_nucleo/brilliant_nucleo.dart';
import 'package:servidor_brilliant/servidor_brilliant.dart';

/// Azar con valores predefinidos: cada `nextInt(max)` devuelve el siguiente.
///
/// Orden de consumo en una partida: 1 valor para elegir qué jugador empieza,
/// justo cuando todos confirman su distribución inicial (los números iniciales
/// los eligen los jugadores, no el azar), y luego 2 por cada tirada
/// (0..5 = dado 1..6).
class GuionAzar implements Random {
  GuionAzar(this.valores);
  final List<int> valores;
  int _i = 0;

  @override
  int nextInt(int max) {
    final v = valores[_i++];
    assert(v < max, 'Valor $v fuera de rango para nextInt($max)');
    return v;
  }

  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;
}

/// Prefijo del guion con el que empieza el jugador 0.
const guionInicio = [0];

/// Pone [orden] (por defecto 1..6) en las seis posiciones iniciales del mapa
/// de [p] para el jugador [id], sin confirmar.
void colocarTodos(PartidaOnline p, String id, {List<int>? orden}) {
  final iniciales = p.mapaOficial.indicesIniciales;
  final numeros = orden ?? const [1, 2, 3, 4, 5, 6];
  for (var k = 0; k < iniciales.length; k++) {
    p.colocarInicial(id, iniciales[k], numeros[k]);
  }
}

/// Reparte y confirma la distribución de [id].
void distribuir(PartidaOnline p, String id, {List<int>? orden}) {
  colocarTodos(p, id, orden: orden);
  p.confirmarDistribucion(id);
}

class CanalFalso implements Canal {
  final List<Map<String, Object?>> recibidos = [];
  bool cerrado = false;
  int? codigoCierre;

  @override
  void enviar(Map<String, Object?> mensaje) {
    if (!cerrado) recibidos.add(mensaje);
  }

  @override
  void cerrar([int? codigo, String? motivo]) {
    cerrado = true;
    codigoCierre = codigo;
  }

  Iterable<String> get tipos => recibidos.map((m) => m['tipo'] as String);

  EstadoSala? get estado {
    for (final m in recibidos.reversed) {
      if (m['tipo'] == MsgServidor.estado) {
        return EstadoSala.fromJson((m['sala'] as Map).cast<String, Object?>());
      }
    }
    return null;
  }

  Map<String, Object?>? get ultimo => recibidos.isEmpty ? null : recibidos.last;

  String? get ultimoError {
    final m = ultimo;
    return m != null && m['tipo'] == MsgServidor.error
        ? m['mensaje'] as String
        : null;
  }
}

Usuario usuarioFalso(String nombre) => Usuario(
  id: 'id_$nombre',
  correo: '$nombre@correo.com',
  hashContrasena: 'x',
  creado: DateTime(2026),
);

/// Rellena el tablero de [j] con números que cumplen las reglas de área, sin
/// seguir las reglas de turno, hasta que no cabe ninguno más. Sirve para
/// fabricar un tablero sin jugadas posibles.
void bloquear(JugadorPartida j, Random azar) {
  final c = j.controlador!;
  var cambio = true;
  while (cambio) {
    cambio = false;
    final celdas = [for (var i = 0; i < 49; i++) i]..shuffle(azar);
    for (final i in celdas) {
      final numeros = [1, 2, 3, 4, 5, 6]..shuffle(azar);
      for (final n in numeros) {
        if (c.colocar(i, n)) {
          cambio = true;
          break;
        }
      }
    }
  }
}

/// Como [bloquear], pero deja sin completar el área azul del mapa 0: una de
/// sus casillas queda vacía y otra con un número distinto, así que la vacía no
/// admite ninguno y el tablero queda sin jugadas con menos puntos.
void bloquearIncompleto(JugadorPartida j, Random azar) {
  bloquear(j, azar);
  final t = j.tablero;
  final celdas = j.mapa.crearTablero();
  for (var i = 0; i < 49; i++) {
    if (t[i] != null) celdas[i] = celdas[i].copiarCon(valor: t[i]);
  }
  celdas[9] = celdas[9].copiarCon(borrarValor: true);
  celdas[17] = celdas[17].copiarCon(valor: t[2]! % 6 + 1);
  j.controlador = ControladorPartida(gruposConectados: j.mapa.gruposConectados)
    ..establecerTableroProvisional(celdas);
}
