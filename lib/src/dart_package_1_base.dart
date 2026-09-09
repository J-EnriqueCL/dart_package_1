// TODO: Put public facing types in this file.

/// Checks if you are awesome. Spoiler: you are.
class Awesome {
  bool get isAwesome => true;
}


bool ListaNumeros(List<int> numeros, int insertarnumero){

if(numeros.contains(insertarnumero)){
  return false;
}

  

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

// Bloque Morado: El grupo solo puede contener un máximo de 2 números distintos
bool BloqueMorado(List<int> numeros, int insertarnumero) {
  final numerosUnicos = {...numeros, insertarnumero};
  return numerosUnicos.length <= 2;
}

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
  List<int> resultados = []; // 1. Creas una lista vacía

  for (var celda in tablero) { // 2. Recorres cada celda del tablero
    // 3. Revisas si cumple las dos condiciones
    if (celda.region == region && celda.valor != null) {
      resultados.add(celda.valor!); // 4. Si cumple, agregas el número a tu lista
    }
  }

  return resultados; 
  
}