// lib/dart_package_1.dart

// =====================
// TIPO: reglas de validación
// =====================

/// Regla amarilla / general:
/// - No permite que el número a insertar ya esté en la lista.
/// - Además, la lista base no debe tener repetidos.
bool ListaNumeros(List<int> numeros, int insertarnumero) {
  // Si el número ya está, no se puede insertar.
  if (numeros.contains(insertarnumero)) {
    return false;
  }

  // La lista base no debe tener repetidos.
  return numeros.length == numeros.toSet().length;
}

// Bloque Verde: Permite cualquier número y repeticiones sin restricción
bool BloqueVerde(List<int> numeros, int insertarnumero) {
  return true;
}

// Bloque Azul: Todos los números de la lista y el nuevo a insertar deben ser iguales
bool BloqueAzul(List<int> numeros, int insertarnumero) {
  if (numeros.isEmpty) return true;
  return numeros.every((n) => n == insertarnumero);
}

// Bloque Rojo y Amarillo: Ningún número se puede repetir en el grupo
bool BloqueRojo(List<int> numeros, int insertarnumero) {
  return !numeros.contains(insertarnumero);
}

// =====================
// ZONA: regiones y celdas
// =====================

enum Region {
  amarillo(5),
  verde(10),
  morado(3),
  azul(7),
  rojo(1);

  final int capacidadMax;

  const Region(this.capacidadMax);
}

class Celda {
  final int? valor;
  final Region region;

  Celda({this.valor, required this.region});
}

List<int> obtenerValoresForIn(List<Celda> tablero, Region region) {
  final resultados = <int>[];

  for (var celda in tablero) {
    if (celda.region == region && celda.valor != null) {
      resultados.add(celda.valor!);
    }
  }

  return resultados;
}