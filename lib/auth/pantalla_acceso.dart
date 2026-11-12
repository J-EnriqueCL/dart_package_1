import 'package:flutter/material.dart';

import '../tema.dart';
import 'cliente_auth.dart';
import 'dialogo_servidor.dart';

/// Pantalla para iniciar sesión o crear una cuenta.
class PantallaAcceso extends StatefulWidget {
  const PantallaAcceso({super.key, required this.auth});

  final ClienteAuth auth;

  @override
  State<PantallaAcceso> createState() => _PantallaAccesoState();
}

class _PantallaAccesoState extends State<PantallaAcceso> {
  final _formulario = GlobalKey<FormState>();
  final _correo = TextEditingController();
  final _contrasena = TextEditingController();
  final _repetir = TextEditingController();
  bool _registro = false;
  bool _ocupado = false;
  bool _ocultar = true;
  String? _error;

  @override
  void dispose() {
    _correo.dispose();
    _contrasena.dispose();
    _repetir.dispose();
    super.dispose();
  }

  void _cambiarModo() {
    setState(() {
      _registro = !_registro;
      _error = null;
      _repetir.clear();
    });
  }

  Future<void> _configurarServidor() async {
    final cambio = await mostrarDialogoServidor(context, widget.auth);
    // Un error de acceso anterior era de otro servidor: ya no vale.
    if (cambio && mounted) setState(() => _error = null);
  }

  Future<void> _enviar() async {
    if (!_formulario.currentState!.validate()) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final correo = _correo.text.trim();
      final contrasena = _contrasena.text;
      if (_registro) {
        await widget.auth.registrar(correo, contrasena);
      }
      // Tras registrarse se entra directo; al conseguirlo el padre cambia de pantalla.
      await widget.auth.iniciarSesion(correo, contrasena);
    } on ErrorCliente catch (e) {
      if (!mounted) return;
      setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  static String? _validarCorreo(String? v) {
    final t = v?.trim() ?? '';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) {
      return 'Escribe un correo válido';
    }
    return null;
  }

  String? _validarContrasena(String? v) {
    final t = v ?? '';
    if (t.isEmpty) return 'Escribe tu contraseña';
    if (!_registro) return null;
    if (t.length < 8 ||
        !t.contains(RegExp(r'[A-Za-z]')) ||
        !t.contains(RegExp(r'\d'))) {
      return 'Mínimo 8 caracteres, con letras y números';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final titulo = _registro ? 'Crear cuenta' : 'Iniciar sesión';
    return Scaffold(
      body: FondoJuego(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Form(
                  key: _formulario,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'BRILLIANT',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        titulo,
                        key: const Key('titulo_acceso'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Servidor: ${widget.auth.urlBase}',
                        key: const Key('servidor_actual'),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                      if (widget.auth.config != null)
                        Align(
                          child: TextButton.icon(
                            key: const Key('boton_configurar_servidor'),
                            onPressed: _ocupado ? null : _configurarServidor,
                            icon: const Icon(Icons.dns_outlined, size: 18),
                            label: const Text('Configurar servidor'),
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('campo_correo'),
                        controller: _correo,
                        enabled: !_ocupado,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Correo',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: _validarCorreo,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        key: const Key('campo_contrasena'),
                        controller: _contrasena,
                        enabled: !_ocupado,
                        obscureText: _ocultar,
                        textInputAction: _registro
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onFieldSubmitted: (_) => _registro ? null : _enviar(),
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _ocultar ? 'Mostrar' : 'Ocultar',
                            icon: Icon(
                              _ocultar
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                            onPressed: () =>
                                setState(() => _ocultar = !_ocultar),
                          ),
                        ),
                        validator: _validarContrasena,
                      ),
                      if (_registro) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('campo_repetir'),
                          controller: _repetir,
                          enabled: !_ocupado,
                          obscureText: _ocultar,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _enviar(),
                          decoration: const InputDecoration(
                            labelText: 'Repite la contraseña',
                            prefixIcon: Icon(Icons.lock_outline),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => v == _contrasena.text
                              ? null
                              : 'Las contraseñas no coinciden',
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _error!,
                          key: const Key('error_acceso'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFFF8A80)),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        key: const Key('boton_enviar_acceso'),
                        onPressed: _ocupado ? null : _enviar,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: _ocupado
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(titulo),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        key: const Key('boton_cambiar_modo'),
                        onPressed: _ocupado ? null : _cambiarModo,
                        child: Text(
                          _registro
                              ? '¿Ya tienes cuenta? Inicia sesión'
                              : '¿No tienes cuenta? Créala',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pide la contraseña y borra la cuenta. Devuelve true si se borró.
Future<bool> confirmarBorrarCuenta(
  BuildContext context,
  ClienteAuth auth,
) async {
  final borrada = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _DialogoBorrarCuenta(auth: auth),
  );
  return borrada ?? false;
}

class _DialogoBorrarCuenta extends StatefulWidget {
  const _DialogoBorrarCuenta({required this.auth});

  final ClienteAuth auth;

  @override
  State<_DialogoBorrarCuenta> createState() => _DialogoBorrarCuentaState();
}

class _DialogoBorrarCuentaState extends State<_DialogoBorrarCuenta> {
  final _contrasena = TextEditingController();
  bool _ocupado = false;
  String? _error;

  @override
  void dispose() {
    _contrasena.dispose();
    super.dispose();
  }

  Future<void> _borrar() async {
    if (_contrasena.text.isEmpty) {
      setState(() => _error = 'Escribe tu contraseña');
      return;
    }
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      await widget.auth.borrarCuenta(_contrasena.text);
      if (mounted) Navigator.of(context).pop(true);
    } on ErrorCliente catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _error = e.mensaje;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Borrar cuenta'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Esta acción no se puede deshacer. '
            'Escribe tu contraseña para confirmar.',
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('campo_contrasena_borrar'),
            controller: _contrasena,
            enabled: !_ocupado,
            obscureText: true,
            onSubmitted: (_) => _borrar(),
            decoration: InputDecoration(
              labelText: 'Contraseña',
              border: const OutlineInputBorder(),
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _ocupado ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('boton_confirmar_borrar'),
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          onPressed: _ocupado ? null : _borrar,
          child: const Text('Borrar'),
        ),
      ],
    );
  }
}
