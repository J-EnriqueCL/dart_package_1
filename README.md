# Brilliant

Juego de tablero de números para Flutter (web y Android), con modo individual y **multijugador en línea** de 2 a 5
jugadores. Está formado por tres proyectos Dart en este repositorio:

| Carpeta | Qué es |
| --- | --- |
| `/` (raíz) | App Flutter (`dart_package_1`): pantallas, modo individual y cliente del multijugador. |
| `servidor/` | Servidor Dart (cuentas, salas y partidas autoritativas por WebSocket). Ver [`servidor/README.md`](servidor/README.md) para el protocolo y las reglas de rondas, premios y meta. |
| `nucleo/` | Paquete compartido (`brilliant_nucleo`): reglas del juego, mapas y modelo del protocolo. Lo usan la app y el servidor, así las reglas no se duplican. |

Soporte de plataforma incluido: `android/`, `ios/` y `web/`. (iOS solo se puede compilar en macOS; no se ha probado.)

## Qué hay implementado

- Modo individual con los 4 niveles.
- Multijugador: cuentas, lobby con código de invitación, **preparación manual** de los números 1–6 en las seis
  posiciones iniciales, **tablero independiente** por jugador, **rondas simultáneas con dados compartidos**
  (confirmar jugada o pasar), plazo común de ronda, reconexión y rendición.
- **Puntuación competitiva del Nivel 1** (premios por orden de completar cada grupo, con empates compartidos y
  liquidación al cerrar la ronda) y **meta por número de jugadores**: 2 → 26, 3 → 24, 4 → 22, 5 → 20 puntos.
- En el multijugador **solo el Nivel 1 está disponible** por ahora; los niveles 2, 3 y 4 siguen en el modo individual.

## Requisitos (Windows)

Versiones con las que se ha desarrollado y probado este estado del proyecto:

- **Flutter 3.47.5** (canal stable), que incluye **Dart 3.13.4**. Los `pubspec.yaml` piden `sdk: ^3.13.1`.
- **Android SDK** con la plataforma 36 (Android Studio la instala). La primera compilación de Android descarga sola,
  vía Gradle, el NDK 28.2 y CMake. En el proyecto: Gradle 9.3.1 (wrapper), Android Gradle Plugin 9.1.0, Kotlin 2.4.0.
  Necesitas un JDK compatible (el que trae Android Studio sirve; no se ha verificado una versión mínima exacta).
- **Git**.
- Para ejecutar en navegador: Chrome o Edge. Si Flutter no encuentra Chrome, usa `-d edge` o define
  `CHROME_EXECUTABLE`.
- Para instalar en un teléfono: depuración USB o simplemente copiar el APK al teléfono.

Comprueba tu instalación con `flutter doctor -v`. En el equipo de desarrollo original Flutter avisa de que faltan
`cmdline-tools` y de la licencia de Android, y aun así las compilaciones de Android funcionan; si en tu laptop falla,
instala *Android SDK Command-line Tools* desde Android Studio y ejecuta `flutter doctor --android-licenses`.

## Obtener el código

```powershell
git clone https://github.com/J-EnriqueCL/dart_package_1.git
cd dart_package_1
git checkout main
```

Si ya tienes una copia: `cd dart_package_1; git status` (no debe haber cambios tuyos sin guardar) y después
`git pull --ff-only origin main`. Si el comando se queja de que no puede avanzar en línea recta, **no** fuerces nada:
revisa antes qué cambió con `git log --oneline main..origin/main`.

## Instalar dependencias

```powershell
flutter pub get                       # app (también resuelve nucleo/, que es una dependencia por ruta)
cd servidor; dart pub get; cd ..      # servidor
cd nucleo;   dart pub get; cd ..      # núcleo
```

## Análisis y pruebas

```powershell
# App (raíz)
flutter analyze
flutter test

# Servidor
cd servidor; dart analyze; dart test; cd ..

# Núcleo
cd nucleo; dart analyze; dart test; cd ..
```

Nota: `flutter test` escribe en `build/` y en `.dart_tool/`, que no se versionan.

## Arrancar el servidor

```powershell
cd servidor
dart run bin/servidor.dart                      # solo acepta conexiones de este equipo (127.0.0.1:8080)
```

Para que otros equipos o teléfonos se conecten, escucha en toda la red:

```powershell
cd servidor
$env:HOST = "0.0.0.0"
dart run bin/servidor.dart
```

Y permite el puerto en el firewall (PowerShell **como administrador**, una vez):

```powershell
New-NetFirewallRule -DisplayName "Brilliant 8080" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow -Profile Any
```

Variables de entorno opcionales: `PORT`, `HOST`, `JWT_SECRETO`, `ORIGEN_PERMITIDO`, `GRACIA_RECONEXION`,
`TIEMPO_RONDA` (`TIEMPO_TURNO` es su nombre antiguo y solo se usa si no está `TIEMPO_RONDA`). Detalles en
[`servidor/README.md`](servidor/README.md).

Para ver tu IP en la red local: `ipconfig` y busca la «Dirección IPv4» del adaptador que usas (Wi-Fi o Ethernet).
Para comprobar desde otro equipo que el servidor responde, abre `http://IP-DEL-SERVIDOR:8080/yo` en su navegador:
debe devolver un error JSON por falta de sesión.

## Ejecutar la app

La app necesita saber dónde está el servidor. Se indica al compilar o ejecutar con
`--dart-define=URL_SERVIDOR=...` (si no se indica, usa `http://localhost:8080`, que **no** sirve en un teléfono).
La app deduce el WebSocket de esa URL (`http` → `ws`, `https` → `wss`).

```powershell
# Navegador, con el servidor en el mismo equipo
flutter run -d edge --dart-define=URL_SERVIDOR=http://localhost:8080

# Emulador de Android (10.0.2.2 es tu PC visto desde el emulador)
flutter run --dart-define=URL_SERVIDOR=http://10.0.2.2:8080

# Teléfono con cable USB y servidor en este equipo (sin depender de la IP ni del firewall)
adb reverse tcp:8080 tcp:8080
flutter run --dart-define=URL_SERVIDOR=http://localhost:8080
```

`adb` está en `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`.

## Generar el APK para probar por Wi-Fi

La IP de `URL_SERVIDOR` queda **incrustada en el APK**: si cambia la IP del equipo que ejecuta el servidor, hay que
generar un APK nuevo. No hay una IP válida para todos: usa la tuya (`ipconfig`).

```powershell
flutter build apk --debug --dart-define=URL_SERVIDOR=http://IP-DEL-SERVIDOR:8080
```

El archivo queda en `build\app\outputs\flutter-apk\app-debug.apk` (unos 160 MB). Cópialo al teléfono (Drive,
WhatsApp, correo…), ábrelo y permite «instalar apps desconocidas» si Android lo pide. Se actualiza encima de la versión
anterior. Los builds **debug** permiten tráfico `http`/`ws` sin cifrar solo para desarrollo; un build release no (usa
`https`/`wss` detrás de un proxy con TLS).

### Dos escenarios

**A. El servidor se ejecuta en la laptop.** Arranca el servidor con `HOST=0.0.0.0` y abre el puerto en el firewall de
la laptop. Los teléfonos y la app usan la **IP de la laptop** (`ipconfig` en la laptop). Si el APK que tienes se generó
con otra IP, genera uno nuevo con la IP de la laptop. Los equipos deben estar en la misma red.

**B. El servidor sigue en la PC original.** La app que ejecutes o compiles en la laptop debe apuntar a la **IP de esa
PC**: `--dart-define=URL_SERVIDOR=http://IP-DE-LA-PC:8080`. La PC debe tener el servidor arrancado con `HOST=0.0.0.0`,
el firewall abierto y estar accesible desde la laptop (misma red).

## Datos del servidor y limitaciones

- Las **cuentas y el secreto JWT** se guardan en `servidor/datos/` (ignorado por Git). **No viajan con el repositorio**:
  en un servidor nuevo hay que registrar las cuentas de nuevo, y los tokens emitidos por otro servidor no valen.
- Las **salas y partidas viven en memoria**: no se transfieren entre computadoras ni sobreviven a un reinicio del
  servidor (los clientes vuelven a la pantalla de entrada). El token de sesión dura 1 hora y solo se guarda en memoria.
- Pendiente y **no resuelto** en las reglas:
  - Niveles 2, 3 y 4: faltan validar sus **grupos de premio** (las agrupaciones propuestas y un valor del Nivel 3). No
    están disponibles en línea; sus datos siguen en el código.
  - Las **reglas de colocación** de algunos niveles difieren de las que sugiere el tablero físico (por ejemplo los
    naranjas `4-6` / `1-3` y las agrupaciones del Nivel 4, o las blancas y el morado inferior del Nivel 3). No se han
    cambiado; **el juego no debe considerarse totalmente fiel al reglamento** mientras existan estas diferencias.
  - **Área morada del Nivel 4**: sus tres posiciones iniciales hacen imposible cumplir «máximo dos números distintos»;
    el área queda bloqueada. Decisión pendiente.
  - Los premios del Nivel 1 son una agrupación **provisional** autorizada para pruebas.
- Identificador de paquete Android `com.example.dart_package_1` (por defecto); hay que cambiarlo antes de publicar. El
  firmado de release no está configurado (el APK debug se firma con la clave de depuración).
- No se ha probado en iOS ni se han publicado versiones en tiendas.
