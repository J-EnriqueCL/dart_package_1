import 'dart:math';

import 'package:brilliant_nucleo/brilliant_nucleo.dart';
import 'package:servidor_brilliant/servidor_brilliant.dart';

/// Azar con valores predefinidos: cada `nextInt(max)` devuelve el siguiente.
///
/// Orden de consumo en una partida nueva: 5 valores para barajar los números
/// iniciales (con `5,4,3,2,1` quedan 1..6 en orden), 1 para el jugador que
/// empieza y luego 2 por cada tirada (0..5 = dado 1..6).
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

/// Prefijo del guion que deja los números 1..6 en orden y empieza el jugador 0.
const guionInicio = [5, 4, 3, 2, 1, 0];

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
