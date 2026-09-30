import 'package:dart_package_1/pantalla_numeros_iniciales.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget crearAplicacion() {
    return MaterialApp(
      home: PantallaNumerosIniciales(
        alIniciar: (_) {},
      ),
    );
  }

  testWidgets('Muestra la pantalla de números iniciales', (tester) async {
    await tester.pumpWidget(crearAplicacion());

    expect(find.text('Números iniciales'), findsOneWidget);
    expect(find.text('Selecciona los números iniciales.'), findsOneWidget);
    expect(find.text('Inicio'), findsOneWidget);
    expect(find.text('Borrar'), findsOneWidget);
  });

  testWidgets('El botón Inicio está deshabilitado al comenzar',
      (tester) async {
    await tester.pumpWidget(crearAplicacion());

    final botonInicio = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Inicio'),
    );

    expect(botonInicio.onPressed, isNull);
  });

  testWidgets('Muestra error si se presiona un número sin celda seleccionada',
      (tester) async {
    await tester.pumpWidget(crearAplicacion());

    await tester.tap(find.widgetWithText(ElevatedButton, '1'));
    await tester.pump();

    expect(
      find.text('Selecciona una casilla antes de colocar un número.'),
      findsOneWidget,
    );
  });

  testWidgets('Permite colocar un número en una celda seleccionada',
      (tester) async {
    await tester.pumpWidget(crearAplicacion());

    await tester.tap(find.byType(InkWell).first);
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, '1'));
    await tester.pump();

    expect(find.text('1'), findsWidgets);
  });

  testWidgets('No permite colocar un número repetido', (tester) async {
    await tester.pumpWidget(crearAplicacion());

    final celdas = find.byType(InkWell);

    await tester.tap(celdas.at(0));
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, '1'));
    await tester.pump();

    await tester.tap(celdas.at(1));
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, '1'));
    await tester.pump();

    expect(
      find.text('El número 1 ya fue seleccionado.'),
      findsOneWidget,
    );
  });

  testWidgets('Permite borrar el valor de una celda', (tester) async {
    await tester.pumpWidget(crearAplicacion());

    await tester.tap(find.byType(InkWell).first);
    await tester.pump();

    await tester.tap(find.widgetWithText(ElevatedButton, '1'));
    await tester.pump();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Borrar'));
    await tester.pump();

    expect(
      find.text('La casilla seleccionada está vacía.'),
      findsNothing,
    );
  });
}