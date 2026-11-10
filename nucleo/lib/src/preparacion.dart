import 'mapas.dart';

/// Los seis números que cada jugador distribuye en su tablero.
const numerosIniciales = <int>[1, 2, 3, 4, 5, 6];

/// Reglas de la fase de preparación, compartidas por servidor y cliente.
///
/// Trabajan sobre los valores de las 49 casillas de un tablero (`null` =
/// vacía). Las seis posiciones iniciales son `mapa.indicesIniciales`. Cada
/// función devuelve `null` si la acción es válida o el motivo del rechazo.
///
/// Estas reglas solo comprueban que los números 1..6 se repartan sin repetir
/// en las seis posiciones iniciales. No aplican la regla de color de las
/// áreas: ver la decisión pendiente sobre el área morada del Nivel 4.

/// Números ya colocados en posiciones iniciales.
Set<int> numerosColocados(MapaOficial mapa, List<int?> tablero) => {
  for (final i in mapa.indicesIniciales)
    if (i < tablero.length && tablero[i] != null) tablero[i]!,
};

/// Números del 1 al 6 que todavía no tienen posición.
List<int> numerosPendientes(MapaOficial mapa, List<int?> tablero) {
  final usados = numerosColocados(mapa, tablero);
  return [
    for (final n in numerosIniciales)
      if (!usados.contains(n)) n,
  ];
}

/// ¿Se puede poner [numero] en [indice]? Poner el mismo número que ya hay es
/// válido (no cambia nada), así un mensaje repetido no duplica colocaciones.
String? errorColocarInicial(
  MapaOficial mapa,
  List<int?> tablero,
  int indice,
  int numero,
) {
  if (!mapa.indicesIniciales.contains(indice)) {
    return 'Solo puedes colocar números en las seis posiciones iniciales.';
  }
  if (!numerosIniciales.contains(numero)) {
    return 'Los números iniciales van del 1 al 6.';
  }
  final actual = tablero[indice];
  if (actual == numero) return null;
  if (actual != null) {
    return 'Esa posición ya tiene un $actual. Retíralo antes de cambiarlo.';
  }
  if (numerosColocados(mapa, tablero).contains(numero)) {
    return 'El $numero ya está colocado. Retíralo antes de usarlo otra vez.';
  }
  return null;
}

/// ¿Se puede retirar el número de [indice]? Retirar una posición vacía es
/// válido (no cambia nada).
String? errorQuitarInicial(MapaOficial mapa, int indice) {
  if (!mapa.indicesIniciales.contains(indice)) {
    return 'Solo las posiciones iniciales llevan número inicial.';
  }
  return null;
}

/// ¿Está completa la distribución? Cada número del 1 al 6 exactamente una vez.
String? errorConfirmarDistribucion(MapaOficial mapa, List<int?> tablero) {
  final faltan = numerosPendientes(mapa, tablero).length;
  if (faltan == 0) return null;
  return faltan == 1
      ? 'Falta 1 número por colocar.'
      : 'Faltan $faltan números por colocar.';
}
