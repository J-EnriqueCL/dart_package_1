import 'package:flutter/material.dart';

import '../widgets/confirmar.dart';
import 'cliente_auth.dart';
import 'config_servidor.dart';

/// Muestra el diálogo para cambiar la dirección del servidor. Devuelve true
/// si se cambió. Cancelar o cerrar no produce ningún cambio.
///
/// Si hay una sesión activa, antes de guardar pide confirmación porque
/// cambiar de servidor la cierra.
Future<bool> mostrarDialogoServidor(
  BuildContext context,
  ClienteAuth auth,
) async {
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => DialogoServidor(auth: auth),
  );
  return r ?? false;
}

class DialogoServidor extends StatefulWidget {
  const DialogoServidor({super.key, required this.auth});

  final ClienteAuth auth;

  @override
  State<DialogoServidor> createState() => _DialogoServidorState();
}

class _DialogoServidorState extends State<DialogoServidor> {
  late final TextEditingController _campo;

  /// Error de validación o de guardado de lo escrito.
  String? _error;
  PruebaServidor? _prueba;
  bool _probando = false;
  bool _guardando = false;

  /// Identifica la prueba vigente: cambia al editar la dirección, al guardar y
  /// al cerrar el diálogo, para ignorar los resultados que lleguen tarde.
  int _token = 0;

  ClienteAuth get _auth => widget.auth;

  @override
  void initState() {
    super.initState();
    _campo = TextEditingController(text: _auth.urlBase.toString());
  }

  @override
  void dispose() {
    _token++;
    _campo.dispose();
    super.dispose();
  }

  void _alEditar(String _) {
    setState(() {
      _token++;
      _error = null;
      _prueba = null;
      _probando = false;
    });
  }

  /// Valida lo escrito; si no es válido muestra el error y devuelve null.
  Uri? _validar() {
    try {
      return validarUrlServidor(_campo.text);
    } on ErrorUrl catch (e) {
      setState(() {
        _error = e.mensaje;
        _prueba = null;
      });
      return null;
    }
  }

  Future<void> _probar() async {
    final uri = _validar();
    final config = _auth.config;
    if (uri == null || config == null) return;
    final mio = ++_token;
    setState(() {
      _error = null;
      _prueba = null;
      _probando = true;
    });
    final resultado = await config.probar(uri);
    // Si mientras tanto se editó la dirección, se guardó o se cerró el
    // diálogo, este resultado ya no corresponde a lo que se ve.
    if (!mounted || mio != _token) return;
    setState(() {
      _probando = false;
      _prueba = resultado;
    });
  }

  Future<void> _guardar() async {
    final uri = _validar();
    if (uri == null) return;
    if (uri == _auth.urlBase) {
      Navigator.of(context).pop(false); // sin cambios
      return;
    }
    if (_auth.haySesion) {
      final seguir = await confirmar(
        context,
        titulo: '¿Cambiar de servidor?',
        texto:
            'Tu sesión actual es de otro servidor y se cerrará. Tendrás que '
            'iniciar sesión de nuevo en el nuevo.',
        textoConfirmar: 'Cerrar sesión y cambiar',
      );
      if (!seguir || !mounted) return;
    }
    final mio = ++_token; // anula cualquier prueba pendiente
    setState(() {
      _guardando = true;
      _probando = false;
      _error = null;
    });
    try {
      await _auth.cambiarServidor(uri);
      if (mounted) Navigator.of(context).pop(true);
    } on ErrorCliente catch (e) {
      if (!mounted || mio != _token) return;
      setState(() {
        _guardando = false;
        _error = e.mensaje;
      });
    }
  }

  Color _color(ResultadoPrueba r) => switch (r) {
    ResultadoPrueba.correcta => Colors.greenAccent,
    ResultadoPrueba.tiempoAgotado => Colors.orangeAccent,
    ResultadoPrueba.sinConexion => const Color(0xFFFF8A80),
    ResultadoPrueba.incompatible => const Color(0xFFFF8A80),
  };

  @override
  Widget build(BuildContext context) {
    final p = _prueba;
    return AlertDialog(
      scrollable: true,
      title: const Text('Servidor'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('campo_url_servidor'),
              controller: _campo,
              enabled: !_guardando,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onChanged: _alEditar,
              onSubmitted: (_) => _probar(),
              decoration: InputDecoration(
                labelText: 'Dirección del servidor',
                hintText: 'http://192.168.1.10:8080',
                border: const OutlineInputBorder(),
                errorText: _error,
                errorMaxLines: 4,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Usa https:// en producción. http:// es solo para pruebas en '
              'tu red local.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('boton_probar_servidor'),
              onPressed: _probando || _guardando ? null : _probar,
              icon: _probando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_find_rounded),
              label: Text(_probando ? 'Probando…' : 'Probar conexión'),
            ),
            if (p != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    p.correcta
                        ? Icons.check_circle_rounded
                        : Icons.error_outline_rounded,
                    size: 18,
                    color: _color(p.resultado),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      p.mensaje,
                      key: const Key('resultado_prueba'),
                      style: TextStyle(color: _color(p.resultado)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('boton_cancelar_servidor'),
          onPressed: _guardando ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('boton_guardar_servidor'),
          onPressed: _guardando ? null : _guardar,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
