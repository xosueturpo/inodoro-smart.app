# Inodoro Smart — App móvil (Flutter)

Aplicación móvil para controlar el sistema **Inodoro Smart**: un inodoro IoT con Arduino UNO (actuadores/sensores), ESP32 (comunicaciones) y firmware embebido. La app permite conectar por **Bluetooth LE** o **WiFi LAN**, enviar comandos, configurar WiFi del ESP32, usar **comandos de voz** y probar la interfaz en **modo demo**.

| Campo | Valor |
|-------|--------|
| Repositorio | https://github.com/xosueturpo/inodoro-smart.app |
| Rama principal | `main` (solo integración estable; **no desarrollar aquí**) |
| Nombre en tienda | **Inodoro Smart** |
| Package Dart | `inodoro_inteligente` |
| APK release | `inodoro-smart.apk` |
| SDK Dart | `^3.12.2` |
| UI | Flutter + Provider + estilo iOS (Cupertino) |

Documentación del hardware, pinout y flujos del firmware: [`docs/inodoro-smart.html`](docs/inodoro-smart.html).

---

## Arquitectura del sistema

```mermaid
flowchart LR
  App["App Flutter\n(Inodoro Smart)"]
  ESP["ESP32\nBLE + WiFi + HTTP"]
  UNO["Arduino UNO\nServos, sensores, relé"]

  App -->|"BLE GATT / HTTP LAN"| ESP
  ESP -->|"UART 9600"| UNO
```

La app **no habla directamente con el Arduino**. Todo pasa por el ESP32:

- **BLE**: característica de comando + notificaciones de eventos.
- **LAN**: HTTP (`/ping`, `/cmd`, `/evt`).

El ESP32 reenvía comandos al UNO y propaga eventos (`FLUSH_START`, `REFILL_END`, etc.) hacia la app.

---

## Requisitos de desarrollo

- [Flutter SDK](https://docs.flutter.dev/get-started/install) compatible con Dart 3.12+
- Android Studio / Xcode (según plataforma objetivo)
- Dispositivo físico recomendado (BLE, micrófono y permisos de ubicación en Android)
- Clave API de [Google AI Studio](https://aistudio.google.com/apikey) para comandos de voz con Gemini (opcional pero recomendado)

Verificar entorno:

```bash
flutter doctor
```

---

## Inicio rápido

### 1. Clonar el repositorio

```bash
git clone https://github.com/xosueturpo/inodoro-smart.app.git
cd inodoro-smart.app
```

HTTPS (anterior) o SSH:

```bash
git clone git@github.com:xosueturpo/inodoro-smart.app.git
cd inodoro-smart.app
```

### 2. Crear tu rama de trabajo

**No trabajes directamente en `main`.** Crea siempre una rama propia para tus cambios, versiones o experimentos:

```bash
git checkout main
git pull origin main
git checkout -b feature/tu-descripcion
```

Ejemplos de nombres de rama:

| Prefijo | Uso |
|---------|-----|
| `feature/` | Nueva funcionalidad (ej. `feature/comandos-voz-v2`) |
| `fix/` | Corrección de bugs (ej. `fix/reconexion-ble`) |
| `dev/` | Versión o línea de desarrollo personal (ej. `dev/jose-luis`) |

Publicar tu rama en GitHub:

```bash
git push -u origin feature/tu-descripcion
```

Cuando termines, abre un **Pull Request** hacia `main` desde tu rama en GitHub. Los cambios se integran a `main` solo tras revisión o cuando el mantenedor lo apruebe.

### 3. Dependencias Flutter

```bash
flutter pub get
```

### Clave Gemini (comandos de voz)

La voz usa **heurística local** primero y **Gemini** como respaldo para frases ambiguas.

**Opción A — archivo local (recomendado en desarrollo)**

```bash
cp lib/core/config/gemini_api_key.local.example.dart lib/core/config/gemini_api_key.local.dart
```

Editar `lib/core/config/gemini_api_key.local.dart` y pegar la clave. Este archivo está en `.gitignore` y **no debe subirse al repositorio**.

**Opción B — variable en compilación**

```bash
flutter run --dart-define=GEMINI_API_KEY=tu_clave_aqui
```

### Ejecutar en dispositivo

```bash
flutter run
```

### Build APK release

```bash
flutter build apk --release
```

Salida renombrada automáticamente: `build/app/outputs/flutter-apk/inodoro-smart.apk` (ver `android/app/build.gradle.kts`).

---

## Estructura del proyecto

```
lib/
├── main.dart                 # Entrada, tema, Provider raíz
├── core/
│   ├── config/               # Gemini API key (stub / local / env)
│   ├── constants/            # BLE, HTTP, voz, comandos de dispositivo
│   └── theme/                # AppTheme claro/oscuro
├── models/                   # DeviceSession, UnoEvent, LedState, etc.
├── providers/
│   └── app_provider.dart     # Estado global y orquestación
├── screens/
│   ├── home_screen.dart      # Inicio: BLE, LAN, Demo
│   ├── ble_search_screen.dart
│   ├── lan_search_screen.dart
│   ├── device_connecting_screen.dart  # Pantalla full-screen "Conectando"
│   └── device_session_screen.dart     # Control + WiFi (BLE)
├── services/
│   ├── ble_provisioning_service.dart  # Escaneo, GATT, WiFi provisioning
│   ├── discovery_service.dart         # mDNS + HTTP LAN
│   ├── voice_command_service.dart     # STT + FAB + sesión de voz
│   ├── gemini_intent_service.dart     # Clasificación FLUSH/REFILL
│   ├── flush_intent_heuristic.dart    # Reglas locales offline
│   └── wifi_scan_service.dart
└── widgets/                  # Botones de control, FAB voz, búsqueda, etc.

codigo_ArduinoUNO/            # Firmware UNO (no es parte del build Flutter)
codigo_ESP32/                 # Firmware ESP32
docs/inodoro-smart.html       # Documentación técnica del sistema completo
```

---

## Capas de la aplicación

### 1. Presentación (`screens/`, `widgets/`)

| Pantalla | Responsabilidad |
|----------|-----------------|
| `HomeScreen` | Elegir canal: Bluetooth, LAN o Modo demo |
| `BleSearchScreen` / `LanSearchScreen` | Descubrimiento de dispositivos |
| `DeviceConnectingScreen` | Conexión a pantalla completa con animación |
| `DeviceSessionScreen` | Control del inodoro, FAB de voz, pestaña WiFi (solo BLE) |

### 2. Estado (`AppProvider`)

`AppProvider` (`ChangeNotifier`) centraliza:

- Sesión activa (`DeviceSession`) y canal (`ble`, `lan`, `demo`)
- Escaneo BLE/LAN
- Envío de comandos (`FLUSH`, `REFILL`, `LID_OPEN`, `LID_CLOSE`)
- Sincronización de eventos UNO → UI (`flushInProgress`, `refillInProgress`)
- Reconexión automática cada 5 s si hay error
- Modo demo (simulación local de descarga/recarga a 3 s)

Inyección de dependencias para tests:

```dart
AppProvider(
  bleService: mockBle,
  discoveryService: mockDiscovery,
  apiService: mockApi,
  voiceService: mockVoice,
)
```

### 3. Servicios

| Servicio | Función |
|----------|---------|
| `BleProvisioningService` | Permisos, escaneo, conexión GATT, escritura de comandos, eventos UNO vía notify |
| `DiscoveryService` / `DeviceApiService` | mDNS `inodoro_smart.local`, ping, POST `/cmd`, poll `/evt` |
| `VoiceCommandService` | Micrófono bajo demanda (FAB), STT, pausa durante ciclos del dispositivo |
| `GeminiIntentService` | Modelo `gemini-2.5-flash-lite`, umbral de confianza 0.48 |
| `FlushIntentHeuristic` | Detección offline de descarga/recarga sin red |

---

## Flujos de conexión

### Bluetooth (primera configuración)

1. Usuario elige **Bluetooth** → escaneo continuo de dispositivos `INODORO*`.
2. Al seleccionar uno → `DeviceConnectingScreen` (estado **Conectando**).
3. Si conecta → `DeviceSessionScreen` con pestañas **Control** y **Configurar WiFi**.
4. Si falla → vuelve a la búsqueda con banner **No se pudo conectar**.

### LAN (uso en casa)

1. ESP32 ya provisionado en la misma red WiFi.
2. Descubrimiento por **mDNS** (`inodoro_smart.local`) y sondeo de hosts conocidos.
3. Mismo flujo de conexión a pantalla completa.
4. Control sin pestaña WiFi (solo HTTP).

### Modo demo

1. Desde inicio → **Modo demo**.
2. Sin hardware: abre directamente la UI de control.
3. Descarga y recarga simulan **3 segundos** de duración (`AppProvider.demoCycleDuration`).
4. Tapa responde en UI pero no hay tráfico de red; voz deshabilitada.

---

## Protocolo de comandos

Constantes en `lib/core/constants/led_commands.dart`:

| Comando | Efecto en UNO |
|---------|----------------|
| `FLUSH` | Inicia descarga (~10 s) |
| `REFILL` | Inicia recarga hasta ADC(A0) > 400 |
| `LID_OPEN` | Tapa a 85° |
| `LID_CLOSE` | Tapa a 0° |

Comandos procesados solo por el ESP32 (no llegan al UNO):

| Comando | Uso |
|---------|-----|
| `WIFI\|ssid\|password` | Provisionar WiFi (BLE) |
| `RESET` | Borrar credenciales WiFi |
| `WIFI_STATUS` | Leer estado WiFi |
| `LCD\|linea0\|linea1` | Solo ESP32 → LCD I2C |

### BLE (`ble_constants.dart`)

- Service UUID: `1234`
- CMD char: `5678` (write)
- Status char: `9012` (read/notify WiFi)
- Event char: `9013` (notify eventos UNO)

### HTTP LAN (`api_constants.dart`)

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/ping` | Comprueba que el ESP32 responde |
| POST | `/cmd` | Cuerpo = comando en texto plano |
| GET | `/evt` | `seq\|EVENTO` (ej. `42\|FLUSH_START`) |

Host mDNS: `inodoro_smart.local`, puerto **80**.

### Eventos UNO → App

Parseados en `UnoEvent.fromPayload()` (`device_models.dart`):

- `FLUSH_START` / `FLUSH_END`
- `REFILL_START` / `REFILL_END`

En BLE llegan por notify; en LAN se hace **poll** cada 400 ms.

---

## Comandos de voz

1. Usuario pulsa el **FAB** flotante (esquina inferior derecha).
2. `VoiceCommandService` abre sesión STT (~20 s máx.).
3. Clasificación:
   - **Heurística local** (`flush_intent_heuristic.dart`) — rápida, offline.
   - **Gemini** si la heurística no alcanza confianza suficiente.
4. Intenciones: `flush` (descarga) o `refill` (recarga).
5. Durante descarga/recarga activa el micrófono se pausa para no interferir.

Configuración relevante: `lib/core/constants/voice_constants.dart`.

---

## Modelos de datos clave

```dart
enum ConnectionChannel { ble, lan, demo }

enum SessionLinkState { connected, reconnecting, error }

class DeviceSession {
  final ConnectionChannel channel;
  final String deviceName;
  SessionLinkState linkState;
  String? lastError;
  // host (LAN), bleDeviceId (BLE)
}
```

Estados de UI derivados:

- `canSendCommands` — conectado y sin ciclo activo
- `canOpenLid` / `canCloseLid` — conectado y sin descarga en curso
- `deviceBusy` — `flushInProgress || refillInProgress`

---

## Permisos Android

Definidos en `android/app/src/main/AndroidManifest.xml`:

| Permiso | Motivo |
|---------|--------|
| `BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT` | BLE |
| `ACCESS_FINE_LOCATION` | Requerido por Android para escaneo BLE |
| `INTERNET`, `ACCESS_NETWORK_STATE` | LAN / HTTP |
| `NEARBY_WIFI_DEVICES` | Escaneo WiFi para provisioning |
| `RECORD_AUDIO` | Comandos de voz |

En runtime se solicitan vía `permission_handler` desde `BleProvisioningService` y `VoiceCommandService`.

---

## Theming

- Tema oscuro por defecto (`ThemeMode.dark` en `main.dart`).
- Tokens en `lib/core/theme/app_theme.dart` (`AppColors`, `AppTheme.text()`).
- Widgets reutilizables: `GlassCard`, `IosSecondaryButton`, `LinkStatusPill`.

---

## Pruebas

```bash
flutter test
```

El test de widget en `test/widget_test.dart` comprueba el título **Inodoro Smart**.

Para pruebas manuales sin hardware usar **Modo demo** desde la pantalla de inicio.

---

## Solución de problemas

| Síntoma | Qué revisar |
|---------|----------------|
| No aparecen dispositivos BLE | Bluetooth encendido, permisos de ubicación, ESP32 powered |
| LAN no encuentra nada | Mismo WiFi, mDNS bloqueado en router, probar IP directa |
| Voz no clasifica bien | Clave Gemini, conexión a internet, logs de `GeminiIntentService` |
| Conexión falla tras seleccionar | Serial ESP32 @ 115200, UART UNO↔ESP32, GND común |
| APK con nombre incorrecto | `flutter build apk --release` y revisar tarea `renameApk` en Gradle |

Logs útiles en debug:

```bash
flutter run -v
```

---

## Firmware relacionado (fuera del build Flutter)

| Carpeta | MCU | Versión referencia |
|---------|-----|-------------------|
| `codigo_ArduinoUNO/` | Arduino UNO | UNO-GR-32 |
| `codigo_ESP32/` | ESP32 | Ver comentarios en sketch |
| `codigo_testA3/` | Test pin A3 | Diagnóstico servo tapa |
| `codigo_sensorAguaArduino/` | Test sensor A0 | Lectura cruda ADC |

Subir firmware con Arduino IDE antes de probar la app contra hardware real.

---

## Convenciones para contribuir

- **Ramas:** nunca commitear en `main`; crear rama propia, hacer push y abrir PR.
- Estado global: ampliar `AppProvider`; evitar estado duplicado en widgets.
- Nuevos comandos: añadir constante en `LedCommands`, método en `AppProvider.send*`, documentar en `docs/inodoro-smart.html` y firmware UNO/ESP32.
- Comandos de voz: ampliar `flush_intent_heuristic.dart` antes de depender más de Gemini (menor costo y latencia).
- No commitear `gemini_api_key.local.dart` ni claves en el código.
- Mensajes de UI y comentarios de código en **español**.
- Ejecutar `flutter analyze` antes de abrir PR.

---

## Licencia y contacto

Repositorio público: [xosueturpo/inodoro-smart.app](https://github.com/xosueturpo/inodoro-smart.app). Consultar al mantenedor para uso comercial o distribución del APK.
