import 'dart:convert';
import 'dart:io';

class Usuario {
  Usuario({
    required this.id,
    required this.correo,
    required this.hashContrasena,
    required this.creado,
  });

  final String id;
  final String correo;
  final String hashContrasena;
  final DateTime creado;

  Map<String, Object?> toJson() => {
    'id': id,
    'correo': correo,
    'hashContrasena': hashContrasena,
    'creado': creado.toIso8601String(),
  };

  factory Usuario.fromJson(Map<String, Object?> j) => Usuario(
    id: j['id'] as String,
    correo: j['correo'] as String,
    hashContrasena: j['hashContrasena'] as String,
    creado: DateTime.parse(j['creado'] as String),
  );
}

/// Persistencia de usuarios.
abstract class AlmacenUsuarios {
  Usuario? porCorreo(String correo);
  Usuario? porId(String id);
  Future<void> guardar(Usuario usuario);
  Future<bool> borrar(String id);
}

class AlmacenMemoria implements AlmacenUsuarios {
  final Map<String, Usuario> _porId = {};

  @override
  Usuario? porCorreo(String correo) {
    for (final u in _porId.values) {
      if (u.correo == correo) return u;
    }
    return null;
  }

  @override
  Usuario? porId(String id) => _porId[id];

  @override
  Future<void> guardar(Usuario usuario) async => _porId[usuario.id] = usuario;

  @override
  Future<bool> borrar(String id) async => _porId.remove(id) != null;
}

/// Guarda los usuarios en un JSON con escritura atómica (tmp + rename).
class AlmacenArchivo extends AlmacenMemoria {
  AlmacenArchivo(this.ruta) {
    final f = File(ruta);
    if (f.existsSync()) {
      final lista = jsonDecode(f.readAsStringSync()) as List<Object?>;
      for (final e in lista) {
        final u = Usuario.fromJson((e as Map).cast<String, Object?>());
        _porId[u.id] = u;
      }
    }
  }

  final String ruta;

  Future<void> _volcar() async {
    final tmp = File('$ruta.tmp');
    await tmp.parent.create(recursive: true);
    await tmp.writeAsString(
      jsonEncode([for (final u in _porId.values) u.toJson()]),
      flush: true,
    );
    await tmp.rename(ruta);
  }

  @override
  Future<void> guardar(Usuario usuario) async {
    await super.guardar(usuario);
    await _volcar();
  }

  @override
  Future<bool> borrar(String id) async {
    final ok = await super.borrar(id);
    if (ok) await _volcar();
    return ok;
  }
}
