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
`TIEMPO_TURNO` (segundos por turno, 60 por defecto) y `GRACIA_RECONEXION` (segundos que se espera a un
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

Partida por turnos de 2 a 4 jugadores. **Cada jugador tiene su propio tablero** (todos con el mapa que eligió el
anfitrión). Las jugadas de un jugador solo cambian su tablero y los puntos se calculan por tablero. En su turno
tira dos dados (el servidor los sortea), elige uno como ancla y coloca el otro número junto a una casilla con el
número del ancla. Solo se puede pasar de turno si los dados no dejan movimientos.

Cada mensaje es un JSON con un campo `tipo` (los nombres están en `nucleo/lib/src/protocolo.dart`).

### Fases de la sala

`lobby` → `preparacion` → `jugando` → `terminada` (y `volver_al_lobby` reabre el lobby).

1. **Lobby:** el anfitrión elige mapa y pulsa `empezar` (exige 2+ jugadores conectados).
2. **Preparación:** no hay turnos ni reloj de turno. Cada jugador reparte los números **1 al 6, cada uno una
   vez**, entre las **seis posiciones iniciales** de su tablero (`MapaOficial.indicesIniciales`; no se colocan
   al azar ni se puede usar otra casilla). Puede colocar y retirar con libertad y después `confirmar_distribucion`;
   desde ese momento queda bloqueada. Cuando **todos** los que siguen en la partida confirmaron, empieza la fase
   `jugando` (una sola vez) y el servidor sortea quién abre.
   - **Quien no confirma bloquea el inicio** para los demás: no hay temporizador ni colocación automática ni
     expulsión durante la preparación (decisión pendiente).
3. **Jugando:** turnos como arriba. Un jugador pasa a `terminado` cuando llena su tablero o ya no existe ninguna
   jugada legal con **ninguna** pareja de dados (no basta con que la tirada actual no tenga jugadas: eso es
   "pasar"). Se salta su turno, **conserva sus puntos y sigue siendo candidato a ganar**.
4. **Terminada:** cuando todos los jugadores que no se rindieron ni abandonaron terminaron su tablero
   (`motivo: todosTerminaron`), gana quien más puntos tenga entre ellos; si hay empate en el máximo comparten la
   victoria. Si solo queda uno que no se rindió ni abandonó (`rendicion` / `abandono`), gana ese
   automáticamente. Si no queda ninguno, no hay ganador.

### Puntos

Se calculan siempre a partir de las casillas del tablero con las reglas de `nucleo/` (un área completa da sus
puntos una sola vez), no se acumulan ni se aceptan del cliente. Valen 0 hasta confirmar la distribución; al
confirmar cuentan las áreas que ya queden completas (p. ej. dos áreas de una casilla en los niveles 3 y 4: 4 + 4).
Antes de confirmar el cliente muestra un valor provisional calculado de su propio tablero.

> **Pendiente de decidir:** en el Nivel 4 las tres posiciones iniciales de la zona morada obligan a tener tres
> números distintos en un área que admite como máximo dos. El validador actual cuenta los iniciales, así que esa
> área queda bloqueada (no admite ningún número más) y nunca puntúa. La preparación **no** rechaza esa
> distribución y no se ha cambiado ninguna regla de área.

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
| `tirar` / `colocar {indice, ancla}` / `pasar` | Acciones del turno (`ancla` es 0 o 1: posición del dado ancla) |
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
(marcador de todos), `turnoDe`, `turno`, `dados`, `segundosTurno`, `mensaje`, `resultado` y `tablero`: las 49
casillas **de tu propio tablero** (los tableros rivales no se envían). En la preparación `tablero` contiene tu
borrador (los números pendientes son los de 1..6 que faltan en las posiciones iniciales), así una reconexión lo
recupera.

### Desconexiones y errores

- **Caídas:** si un jugador pierde la conexión, los demás lo ven como desconectado con una cuenta atrás.
  Si vuelve a autenticarse dentro del plazo (`GRACIA_RECONEXION`: 60 s en preparación y partida, 20 s en el
  lobby) recibe el estado actual (fase, tablero propio con sus números colocados o su confirmación, puntos,
  turno y dados) y sigue como estaba; el reloj de turno no se reinicia ni se vuelven a tirar los dados. Si no
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
- **Turnos:** cada turno tiene un reloj (`TIEMPO_TURNO`). Al agotarse se pasa el turno; tras 3 turnos
  agotados seguidos el jugador se da por abandonado. Los eventos ajenos (conexiones, etc.) no reinician el reloj.
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
