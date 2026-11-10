import 'dart:async';
import 'dart:convert';

import 'package:brilliant_nucleo/brilliant_nucleo.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'almacen.dart';
import 'salas.dart';
import 'servicio_auth.dart';

/// Códigos de cierre propios (el rango 4000-4999 es de la aplicación).
abstract final class CierreWs {
  static const autenticacion = 4001;
  static const limite = 4002;
  static const sesionReemplazada = 4003;
  static const mensajeGrande = 4009;
}

class _CanalWs implements Canal {
  _CanalWs(this._ch);
  final WebSocketChannel _ch;
  bool _cerrado = false;

  @override
  void enviar(Map<String, Object?> mensaje) {
    if (_cerrado) return;
    try {
      _ch.sink.add(jsonEncode(mensaje));
    } catch (_) {
      // El socket ya murió; el cierre llegará por onDone.
    }
  }

  void error(String codigo, String texto, {bool fatal = false}) => enviar({
    'tipo': MsgServidor.error,
    'codigo': codigo,
    'mensaje': texto,
    if (fatal) 'fatal': true,
  });

  @override
  void cerrar([int? codigo, String? motivo]) {
    if (_cerrado) return;
    _cerrado = true;
    unawaited(_ch.sink.close(codigo, motivo).catchError((Object _) {}));
  }
}

/// Máximo de mensajes por segundo y conexión; evita inundar al servidor.
class _Limitador {
  _Limitador(this.maximo, this._ahora);
  final int maximo;
  final DateTime Function() _ahora;
  DateTime _inicio = DateTime.fromMillisecondsSinceEpoch(0);
  int _cuenta = 0;

  bool permitir() {
    final t = _ahora();
    if (t.difference(_inicio) >= const Duration(seconds: 1)) {
      _inicio = t;
      _cuenta = 0;
    }
    return ++_cuenta <= maximo;
  }
}

/// Manejador de `GET /ws`.
///
/// Protocolo: el primer mensaje debe ser `{"tipo":"auth","token":...}` (con
/// el JWT del login) dentro de [plazoAuth]; el token no viaja en la URL para
/// que no quede en registros. Después, el servidor manda `estado` tras cada
/// cambio y el cliente envía acciones (ver [MsgCliente]).
Handler crearManejadorWs(
  ServicioAuth auth,
  GestorSalas gestor, {
  String? origenPermitido,
  Duration pingInterval = const Duration(seconds: 15),
  Duration plazoAuth = const Duration(seconds: 5),
  int maxMensajesPorSegundo = 30,
  int maxBytesMensaje = 4096,
}) {
  return webSocketHandler(
    (WebSocketChannel ch, String? _) {
      final canal = _CanalWs(ch);
      final limitador = _Limitador(maxMensajesPorSegundo, DateTime.now);
      Usuario? usuario;

      final plazo = Timer(plazoAuth, () {
        if (usuario == null) {
          canal.error(
            CodigoError.noAutenticado,
            'Falta autenticarse.',
            fatal: true,
          );
          canal.cerrar(CierreWs.autenticacion, 'Sin autenticar');
        }
      });

      void alCerrar() {
        plazo.cancel();
        final u = usuario;
        if (u != null) gestor.desconectar(u.id, canal);
      }

      ch.stream.listen(
        (dynamic dato) {
          try {
            if (dato is! String || dato.length > maxBytesMensaje) {
              canal.cerrar(CierreWs.mensajeGrande, 'Mensaje demasiado grande');
              return;
            }
            if (!limitador.permitir()) {
              canal.error(
                CodigoError.limite,
                'Demasiados mensajes.',
                fatal: true,
              );
              canal.cerrar(CierreWs.limite, 'Demasiados mensajes');
              return;
            }
            final msg = _decodificar(dato);
            if (msg == null) {
              canal.error(CodigoError.generico, 'Mensaje inválido.');
              return;
            }

            final u = usuario;
            if (u != null) {
              gestor.manejar(u.id, canal, msg);
              return;
            }

            final token = msg['token'];
            final nuevo = msg['tipo'] == MsgCliente.auth && token is String
                ? auth.usuarioDeToken(token)
                : null;
            if (nuevo == null) {
              canal.error(
                CodigoError.autenticacion,
                'Sesión inválida o expirada.',
                fatal: true,
              );
              canal.cerrar(CierreWs.autenticacion, 'No autenticado');
              return;
            }
            usuario = nuevo;
            plazo.cancel();
            gestor.conectar(nuevo, canal);
          } catch (e, st) {
            print('Error en la conexión: $e\n$st');
            canal.error(CodigoError.generico, 'Error interno.');
          }
        },
        onDone: alCerrar,
        onError: (Object _) => alCerrar(),
        cancelOnError: true,
      );
    },
    pingInterval: pingInterval,
    allowedOrigins: origenPermitido == null ? null : [origenPermitido],
  );
}

Map<String, Object?>? _decodificar(String texto) {
  try {
    final d = jsonDecode(texto);
    if (d is Map) return d.cast<String, Object?>();
  } catch (_) {}
  return null;
}
