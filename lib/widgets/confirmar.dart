import 'package:flutter/material.dart';

/// Pregunta de sí o no; devuelve true si el usuario confirma.
Future<bool> confirmar(
  BuildContext context, {
  required String titulo,
  required String texto,
  required String textoConfirmar,
}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      actions: [
        TextButton(
          key: const Key('confirmar_no'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('confirmar_si'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(textoConfirmar),
        ),
      ],
    ),
  );
  return r ?? false;
}
