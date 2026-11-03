# Servidor de autenticación de Brilliant

Programa independiente de la app Flutter. Se ejecuta con:

```
cd servidor
dart pub get
dart run bin/servidor.dart      # http://localhost:8080
dart test
```

Variables de entorno opcionales: `PORT`, `JWT_SECRETO` (mínimo 32 caracteres; si no se da,
se genera y se guarda en `datos/secreto_jwt.txt`), `ORIGEN_PERMITIDO` (origen CORS; por defecto `*`).

## API

| Método y ruta     | Cuerpo                       | Respuesta                    |
| ----------------- | ---------------------------- | ---------------------------- |
| `POST /registro`  | `{correo, contrasena}`       | 201 `{id, correo}`           |
| `POST /login`     | `{correo, contrasena}`       | 200 `{token}` (JWT, 1 hora)  |
| `GET /yo`         | — (`Authorization: Bearer`)  | 200 `{id, correo}`           |
| `DELETE /cuenta`  | `{contrasena}` + Bearer      | 200 `{ok: true}`             |

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
