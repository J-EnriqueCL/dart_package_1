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

Partida por turnos de 2 a 4 jugadores **sobre un único tablero compartido**. En su turno cada jugador tira
dos dados (el servidor los sortea), elige uno como ancla y coloca el otro número junto a una casilla con el
número del ancla. Quien completa un área se lleva sus puntos. Gana quien más puntos tenga cuando el tablero
se llena o ya no queda ninguna jugada posible. Solo se puede pasar de turno si los dados no dejan movimientos.

Cada mensaje es un JSON con un campo `tipo` (los nombres están en `nucleo/lib/src/protocolo.dart`).

**Autenticación:** el primer mensaje debe ser `{"tipo":"auth","token":<JWT del login>}` en menos de 5 s (el
token no va en la URL para que no quede en registros). Si falla, el servidor manda un `error` con
`fatal: true` y cierra (código 4001).

| Cliente envía                         | Efecto                                                                 |
| ------------------------------------- | ---------------------------------------------------------------------- |
| `crear_sala {mapa}`                   | Crea una sala con código de invitación de 6 caracteres; eres anfitrión |
| `unirse {codigo}`                     | Entra a una sala en el lobby (el código admite minúsculas, espacios y guiones) |
| `elegir_mapa {mapa}` / `expulsar {id}` / `empezar` | Solo anfitrión, en el lobby (`empezar` exige 2+ jugadores conectados) |
| `tirar` / `colocar {indice, ancla}` / `pasar` | Acciones del turno (`ancla` es 0 o 1: posición del dado ancla) |
| `conceder`                            | Te rindes; los demás siguen. Si queda uno solo, gana                    |
| `salir_sala`                          | En el lobby, sales; en partida equivale a rendirte y salir              |
| `volver_al_lobby`                     | Solo anfitrión, con la partida terminada                                |
| `ping`                                | Responde `pong` (latido)                                                |

El servidor responde con `estado {sala}` (foto completa de la sala, tras **cada** cambio), `sin_sala`,
`expulsado`, `sesion_reemplazada`, `pong` o `error {codigo, mensaje, fatal?}`. Las jugadas inválidas dan un
`error` solo al que las envió y no cambian nada.

### Desconexiones y errores

- **Caídas:** si un jugador pierde la conexión, los demás lo ven como desconectado con una cuenta atrás.
  Si vuelve a autenticarse dentro del plazo (`GRACIA_RECONEXION`; 20 s en el lobby) recibe el estado
  actual y sigue como estaba. Si no vuelve: en el lobby se le saca de la sala, y en partida cuenta como
  **abandono** (si queda un solo jugador activo, gana).
- **Turnos:** cada turno tiene un reloj (`TIEMPO_TURNO`). Al agotarse se pasa el turno; tras 3 turnos
  agotados seguidos el jugador se da por abandonado. Los eventos ajenos (conexiones, etc.) no reinician el reloj.
- **Rendirse:** `conceder` o `salir_sala`. Si el anfitrión se va, el cargo pasa a otro jugador.
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
