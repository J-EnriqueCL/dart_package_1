import 'package:dart_package_1/dart_package_1.dart';

void main() {
  final matriz = [
    const Celda(
      region: Region.verde,
      valor: 5,
      esInicial: true,
    ),
  ];

  final controlador = ControladorPartida();
  controlador.establecerValoresIniciales(matriz);

  print(controlador.matriz);
}