# Servidor de Brilliant (cuentas y partidas en línea)

Programa independiente de la app Flutter. Se ejecuta con:

```
cd servidor
dart pub get
dart run bin/servidor.dart      # http://localhost:8080
dart test
```

Variables de entorno opcionales: `PORT`, `JWT_SECRETO` (mínimo 32 caracteres; si no se da,
se genera y se guarda en `datos/secreto_jwt.txt`), `ORIGEN_PERMITIDO` (origen CORS y de WebSocket; por defecto `*`),
`HOST` (por defecto solo escucha en `127.0.0.1`; con `0.0.0.0` acepta conexiones de la red),
`TIEMPO_RONDA` (plazo común en segundos para resolver una ronda, 60 por defecto; `TIEMPO_TURNO` es su
nombre antiguo y solo se usa si no está `TIEMPO_RONDA`) y `GRACIA_RECONEXION` (segundos que se espera a un
jugador desconectado en plena partida, 60 por defecto).

Las reglas del juego viven en el paquete compartido `../nucleo`, el mismo que usa la app, así que el
servidor valida cada jugada con las reglas reales.

## API

| Método y ruta     | Cuerpo                       | Respuesta                    |
| ----------------- | ---------------------------- | ---------------------------- |
| `POST /registro`  | `{correo, contrasena}`       | 201 `{id, correo}`           |
| `POST /login`     | `{correo, contrasena}`       | 200 `{token}` (JWT, 1 hora)  |
| `GET /yo`         | — (`Authorization: Bearer`)  | 200 `{id, correo}`           |
| `DELETE /cuenta`  | `{contrasena}` + Bearer      | 200 `{ok: true}`             |

## Partidas en línea (`GET /ws`, WebSocket)

Partida por **rondas simultáneas** de 2 a 5 jugadores. **Cada jugador tiene su propio tablero** (todos con el mapa
que eligió el anfitrión). Las jugadas de un jugador solo cambian su tablero y los puntos se calculan por tablero.
En cada ronda hay **una única tirada de dos dados que ven todos**; cada jugador elige uno como ancla y coloca el
otro número junto a una casilla de su tablero con el número del ancla (una sola colocación por ronda), o pasa.
No hay turno de colocación: todos resuelven a la vez y el orden no da ventaja.

Cada mensaje es un JSON con un campo `tipo` (los nombres están en `nucleo/lib/src/protocolo.dart`).

### Fases de la sala

`lobby` → `preparacion` → `jugando` → `terminada` (y `volver_al_lobby` reabre el lobby).

1. **Lobby:** el anfitrión elige mapa y pulsa `empezar` (exige 2+ jugadores conectados).
2. **Preparación:** no hay rondas ni plazos. Cada jugador reparte los números **1 al 6, cada uno una
   vez**, entre las **seis posiciones iniciales** de su tablero (`MapaOficial.indicesIniciales`; no se colocan
   al azar ni se puede usar otra casilla). Puede colocar y retirar con libertad y después `confirmar_distribucion`;
   desde ese momento queda bloqueada. Cuando **todos** los que siguen en la partida confirmaron, empieza la fase
   `jugando` (una sola vez) y el servidor sortea quién abre.
   - **Quien no confirma bloquea el inicio** para los demás: no hay temporizador ni colocación automática ni
     expulsión durante la preparación (decisión pendiente).
3. **Jugando:** rondas (ver abajo). Un jugador pasa a `terminado` cuando llena su tablero o ya no existe ninguna
   jugada legal con **ninguna** pareja de dados (no basta con que la tirada actual no tenga jugadas: eso es
   "pasar"). Se evalúa **al cerrar la ronda**; deja de participar en las rondas pero **conserva sus puntos y sigue
   siendo candidato a ganar**.
4. **Terminada**, en este orden de comprobación:
   - **Meta** (`motivo: meta`): al **cerrar una ronda**, y solo después de liquidar todos los premios de esa ronda, si
     algún jugador elegible (que no se rindió ni abandonó) tiene `meta` puntos o más. Gana quien tenga **más puntos**
     entre los elegibles; si empatan en el máximo comparten la victoria. Nunca termina al llegar la primera
     confirmación.
   - **Todos terminaron** (`motivo: todosTerminaron`): todos los elegibles terminaron su tablero sin alcanzar la meta;
     gana el de más puntos (empate compartido).
   - **Victoria automática** (`rendicion` / `abandono`): solo queda un jugador que no se rindió ni abandonó. Los que ya
     terminaron su tablero siguen siendo elegibles. Si no queda ninguno, no hay ganador.

### Meta

Se fija **al empezar** según los participantes y no cambia por rendiciones, abandonos o desconexiones posteriores:
2 jugadores → 26 puntos, 3 → 24, 4 → 22, 5 → 20 (`estado.sala.meta`; `null` antes de empezar). La sala admite de 2 a
5 jugadores.

### Mapas disponibles en línea

Solo se puede crear o elegir un mapa que tenga su **tabla de premios validada**. En esta versión de prueba es solo el
**Nivel 1**; los niveles 2, 3 y 4 conservan sus datos y siguen disponibles en el modo individual, pero el servidor
rechaza elegirlos ("todavía no está disponible en línea").

### Rondas

Cada ronda tiene un `id` (empieza en 1 y sube al cerrarse), una `fase` y, si hay tirada, los `dados` compartidos.

1. **`esperandoTirada`** (estado inicial de cada ronda, también la 1ª tras la preparación): cualquier jugador cuyo
   `estado` sea `jugando` puede enviar `tirar {ronda}`. Los `terminado`, `concedio` y `abandono` no pueden. No hay
   plazo ni tirada automática: la sala espera indefinidamente (los plazos de reconexión siguen corriendo).
2. **`resolviendo`**: el servidor sortea una sola pareja de dados, la publica a todos y fija los participantes (los
   que están `jugando`), todos `pendiente`. Empieza el **plazo común** (`TIEMPO_RONDA`, 60 s por defecto), que **no se
   reinicia** al confirmar, pasar ni reconectar. Cada participante resuelve **una sola vez**:
   - `confirmar_jugada {ronda, indice, ancla}`: aplica la jugada en su tablero (valida con las reglas del núcleo).
   - `pasar_ronda {ronda}`: no coloca nada; se permite **aunque haya jugadas**. Pasar nunca cuenta como inactividad.
3. **Cierre:** cuando no queda ningún pendiente (se cuentan solo los que siguen en la ronda: los rendidos y
   abandonados salen de ella), la ronda se cierra **una sola vez**: se recalcula quién queda `terminado`, se
   comprueba el final de partida y, si sigue, pasa a `esperandoTirada` con `id + 1`.
4. **Plazo vencido:** los pendientes quedan *sin respuesta* (no colocan nada, se anota en `mensaje`) y la ronda se
   cierra. **Tres rondas seguidas** sin respuesta provocan el abandono; confirmar o pasar reinicia la cuenta. Un
   jugador desconectado en gracia sigue pendiente: si vence la ronda queda sin respuesta (no abandonado por eso); si
   vence su gracia, pasa a `abandono` aunque quede tiempo de ronda.

Todas las acciones se validan al procesarlas: fase, `ronda` (una acción de otra ronda da `error` y no cambia nada) y
resolución del jugador. Solo se acepta una resolución por jugador y ronda: repetir `confirmar_jugada` o `pasar_ronda`
no hace nada, confirmar tras pasar (o pasar tras confirmar) se rechaza, y un `tirar` con la ronda ya abierta no
genera otra tirada. Los dados nunca vienen del cliente. Ante un `error`, el servidor reenvía antes el `estado`
autoritativo al que lo provocó, para que un cliente desactualizado se corrija.

### Puntos y premios por grupo

La puntuación **no** es un valor fijo por área ni se calcula de las casillas: es lo que el servidor **adjudica** (`puntos`
de cada jugador), y depende del **orden en que se completan** los grupos de premio.

- **Grupo de premio:** unidad de puntuación con id estable (`N1-a0`: nivel y casilla de menor índice), una lista de
  casillas (puede tener partes separadas) y tres premios (1.º, 2.º, 3.º). No es lo mismo que una región de validación
  ni que el color: dos grupos del mismo color son independientes. Nivel 1 (provisional, de la imagen del tablero):

  | Grupo | Casillas | Premios |
  | --- | --- | --- |
  | `N1-a0` amarillo | 0, 6, 24, 42, 48 | 8 / 6 / 4 |
  | `N1-a1`, `N1-a13` verdes | 1,7,8,14,21,28 · 13,19,20,25,26,27 | 4 / 3 / 2 |
  | `N1-a2`, `N1-a34` azules | 2,9,10,17 · 34,40,41,47 | 7 / 5 / 3 |
  | `N1-a15`, `N1-a32` rojos | 15,16,22,29,35,36 · 32,33,38,39,45,46 | 6 / 4 / 2 |
  | `N1-a3`, `N1-a23` morados | 3,4,5,11,12,18 · 23,30,31,37,43,44 | 6 / 4 / 2 |

- **Completar un grupo** es tener todas sus casillas ocupadas en tu tablero. Es distinto de **recibir premio**:
  - Al confirmar una jugada, el servidor solo **registra** los grupos recién completos (`misPendientes`); no da puntos ni
    prioridad por el orden de llegada.
  - **Al cerrar la ronda** se agrupan las finalizaciones de cada grupo y se liquidan: los que lo completaron en la
    misma ronda **comparten el siguiente nivel libre** (un empate ocupa un solo nivel, aunque sean cuatro); el grupo
    siguiente recibe el nivel siguiente; cada jugador cobra **una sola vez por grupo**; con los tres niveles agotados,
    completarlo da **0 puntos** (`sinPremio`). Los puntos se suman una vez y después se evalúa la meta.
  - Un jugador que se rinde o abandona tras completar un grupo en una ronda conserva ese premio (aunque ya no puede
    ganar).
- **Preparación:** los grupos que ya nacen completos se evalúan **juntos** al terminar la preparación de todos (no al
  confirmar cada uno): todos los que lo tengan completo empatan en el primer nivel, que es el único que consumen. Con
  los grupos del Nivel 1 ninguno nace completo (todos contienen casillas no iniciales), así que no hay puntos
  iniciales.
- El historial (`LibroPremios`) vive en el servidor: reconectar no vuelve a conceder nada. `estado.sala` lleva
  `reclamaciones` (quién ocupa cada nivel de cada grupo), `liquidacion` (premios de la última liquidación),
  `misPendientes` y `meta`. El cliente no decide puntuaciones ni prioridad.

> **Pendiente de decidir:** en el Nivel 4 las tres posiciones iniciales de la zona morada obligan a tener tres
> números distintos en un área que admite como máximo dos. El validador actual cuenta los iniciales, así que esa
> área queda bloqueada (no admite ningún número más). La preparación **no** rechaza esa distribución y no se ha
> cambiado ninguna regla de área (el Nivel 4 tampoco está disponible en línea por ahora).

### Estados de un jugador

`estado` (en `jugadores[]`): `preparando`, `listo`, `jugando`, `terminado`, `concedio` (Rendido) y `abandono`.
Los dos últimos conservan sus puntos pero no pueden ganar. La conexión es aparte (`conectado`,
`graciaRestante`): perderla temporalmente no cambia el `estado`.

**Autenticación:** el primer mensaje debe ser `{"tipo":"auth","token":<JWT del login>}` en menos de 5 s (el
token no va en la URL para que no quede en registros). Si falla, el servidor manda un `error` con
`fatal: true` y cierra (código 4001).

| Cliente envía                         | Efecto                                                                 |
| ------------------------------------- | ---------------------------------------------------------------------- |
| `crear_sala {mapa}`                   | Crea una sala con código de invitación de 6 caracteres; eres anfitrión |
| `unirse {codigo}`                     | Entra a una sala en el lobby (el código admite minúsculas, espacios y guiones) |
| `elegir_mapa {mapa}` / `expulsar {id}` / `empezar` | Solo anfitrión, en el lobby (`empezar` exige 2+ jugadores conectados) |
| `colocar_inicial {indice, numero}`    | Preparación: pone un número 1..6 en una posición inicial **tuya** vacía. Repetir lo mismo no cambia nada |
| `quitar_inicial {indice}`             | Preparación, antes de confirmar: retira el número de esa posición       |
| `confirmar_distribucion`              | Preparación: bloquea tu distribución (exige los seis números). Repetirlo no hace nada |
| `tirar {ronda}`                       | Lanza los dados compartidos (ronda en `esperandoTirada`, jugador `jugando`) |
| `confirmar_jugada {ronda, indice, ancla}` | Confirma tu jugada de la ronda (`ancla` es 0 o 1: posición del dado ancla) |
| `pasar_ronda {ronda}`                 | Pasas la ronda (aunque tengas jugadas)                                  |
| `conceder`                            | Te rindes (también en la preparación); los demás siguen mientras queden 2+ jugadores que no se hayan rendido ni abandonado |
| `salir_sala`                          | En el lobby, sales; en preparación o partida equivale a rendirte y salir |
| `volver_al_lobby`                     | Solo anfitrión, con la partida terminada                                |
| `ping`                                | Responde `pong` (latido)                                                |

El servidor identifica al jugador por su conexión autenticada: ningún mensaje lleva un id de jugador y cualquier
campo extra se ignora, así que nadie puede tocar un tablero ajeno.

El servidor responde con `estado {sala}` (foto completa de la sala, tras **cada** cambio), `sin_sala`,
`expulsado`, `sesion_reemplazada`, `pong` o `error {codigo, mensaje, fatal?}`. Las jugadas inválidas dan un
`error` solo al que las envió y no cambian nada.

**Contenido de `estado.sala`:** `fase`, `jugadores[] {id, nombre, conectado, puntos, estado, graciaRestante?}`
(marcador de todos), `ronda {id, fase, dados, resoluciones, segundos}` (`resoluciones` = cada participante
`pendiente`, `confirmo` o `paso`; `segundos` = plazo restante), `meta`, `reclamaciones`, `misPendientes`,
`liquidacion`, `mensaje`, `resultado` y `tablero`: las 49
casillas **de tu propio tablero** (los tableros rivales no se envían). En la preparación `tablero` contiene tu
borrador (los números pendientes son los de 1..6 que faltan en las posiciones iniciales), así una reconexión lo
recupera.

### Desconexiones y errores

- **Caídas:** si un jugador pierde la conexión, los demás lo ven como desconectado con una cuenta atrás.
  Si vuelve a autenticarse dentro del plazo (`GRACIA_RECONEXION`: 60 s en preparación y partida, 20 s en el
  lobby) recibe el estado actual (fase, tablero propio con sus números colocados o su confirmación, puntos,
  ronda, dados, su resolución y plazo restante) y sigue como estaba; no se reinicia ningún plazo, no se vuelve a
  tirar ni se puede resolver otra vez ni reabrir una ronda cerrada (la previsualización local no confirmada se pierde). Si no
  vuelve: en el lobby se le saca de la sala, y en preparación o partida cuenta como **abandono**.
- **Cuatro situaciones distintas** (siempre separadas en `jugadores[]`):
  1. *Rendición explícita* (`conceder`/`salir_sala`): `estado: concedio`, sin posibilidad de ganar.
  2. *Desconexión temporal*: `conectado: false` y `graciaRestante`; el `estado` de participación no cambia.
  3. *Abandono confirmado*: al vencer la gracia, `estado: abandono`, sin posibilidad de ganar.
  4. *Terminado*: llenó su tablero o no tiene jugadas; sigue siendo elegible (aunque se desconecte dentro de la gracia).
- **Plazos vencidos a la vez:** cuando vence un plazo de reconexión, el servidor mira con **ese mismo instante de
  referencia** a los demás desconectados cuyo plazo también venció y los resuelve juntos, antes de decidir el
  resultado. Así el final no depende de qué temporizador se ejecute primero: con 0 elegibles no hay ganador, con 1
  gana ese, y quien aún está dentro de su plazo no se convierte en abandonado antes de tiempo.
- **Preparación:** quien se rinde o abandona deja de contar para iniciar. Si quedan 2+ y todos ya confirmaron,
  empieza sin esperarle; si queda uno solo, termina y gana.
- **Plazo de ronda:** ver «Rondas». Los eventos ajenos (conexiones, confirmaciones, etc.) no reinician el plazo.
- **Rendirse:** `conceder` o `salir_sala`. Si el anfitrión se va, el cargo pasa a otro jugador que siga en la
  partida. Rendirse **no** termina la partida si quedan al menos dos jugadores que no se rindieron ni abandonaron
  (incluidos los que ya terminaron su tablero).
- **Misma cuenta en dos sitios:** la conexión nueva sustituye a la anterior (que recibe
  `sesion_reemplazada` y se cierra con 4003) y recupera la sala.
- **Abuso:** mensajes de hasta 4 KB, 30 mensajes por segundo y conexión (si no, se cierra con 4002/4009),
  8 códigos de sala erróneos por minuto y usuario, y máximo 500 salas.
- Las salas viven en memoria: si el servidor se reinicia, se pierden (los clientes vuelven a la entrada).

## Seguridad

- Contraseñas con **bcrypt** (costo 12) y sal propia; nunca se guardan en claro.
- Sesiones con **JWT** firmado (HS256) que caduca en 1 hora. Un token de una cuenta borrada deja de valer.
- Mismo mensaje de error si el correo no existe o la contraseña es incorrecta, y se compara contra un
  hash de relleno para que el tiempo de respuesta no delate si el correo existe.
- Bloqueo de 15 minutos tras 5 intentos fallidos por correo.
- Borrar la cuenta exige volver a escribir la contraseña.
- Límite de 10 KB por petición y entrada validada (correo, contraseña de 8 a 72 bytes con letras y números).
- Respuestas con `Cache-Control: no-store`.

**Pendiente para producción:** servir por HTTPS (por ejemplo con un proxy inverso), fijar
`ORIGEN_PERMITIDO` y `JWT_SECRETO`, y cambiar el JSON por una base de datos real.
