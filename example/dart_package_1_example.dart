import 'package:dart_package_1/dart_package_1.dart';

void main() {
  final awesome = Awesome();
  print('awesome: ${awesome.isAwesome}');

  final celda = Celda(region: Region.verde, valor: 5);
  print('valor: ${obtenerValoresForIn([celda], Region.verde)}');
}
