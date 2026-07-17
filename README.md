# Inodoros Fuertes — Guía de desarrollo

**Épicos y resistentes**

Proyecto IoT de inodoro inteligente con tres capas de software: firmware en **Arduino UNO** (actuadores y sensores), firmware en **ESP32** (comunicaciones) y aplicación móvil en **Flutter**.

Documentación del proyecto (informe / sitio):  
**[https://sites.google.com/view/inodoro-orion/inicio](https://sites.google.com/view/inodoro-orion/inicio)**

Repositorio: [github.com/xosueturpo/inodoro-smart.app](https://github.com/xosueturpo/inodoro-smart.app)

---

## Visión general

```
App Flutter  →  ESP32 (BLE / WiFi / HTTP)  →  Arduino UNO (actuadores)
```

La aplicación **no habla directamente con el Arduino**. Todo comando y evento pasa por el ESP32 vía UART.

| Capa | Carpeta | Rol |
|------|---------|-----|
| Control físico | `codigo_ArduinoUNO/` | Descarga, recarga, tapa, sensores, buzzer, LEDs |
| Comunicaciones | `codigo_ESP32/` | BLE, WiFi, HTTP, LCD, puente UART |
| Aplicación | `lib/`, `android/`, `ios/`, … | UI, BLE/LAN, voz, modo demo |

```
inodoro-smart.app/
├── codigo_ArduinoUNO/   ← 1) Firmware Arduino UNO
├── codigo_ESP32/        ← 2) Firmware ESP32
├── lib/ · android/ · ios/  ← 3) App Flutter (Dart)
└── README.md
```

### Clonar y ramas

```bash
git clone https://github.com/xosueturpo/inodoro-smart.app.git
cd inodoro-smart.app
```

**No desarrolles en `main`.** Crea siempre una rama propia:

```bash
git checkout main
git pull origin main
git checkout -b feature/tu-descripcion
git push -u origin feature/tu-descripcion
```

Luego abre un Pull Request hacia `main`.

---

## 1. Arduino UNO (`codigo_ArduinoUNO/`)

Firmware de referencia: **UNO-GR-33**

### Qué controla

- Servo válvula (D5) — descarga
- Servo tapa (A3 / pin digital 17) — abrir/cerrar
- Relé / bomba (D10) — recarga
- Sensor nivel agua (A0)
- Ultrasónicos HC-SR04 (descarga D6/D7, tapa D2/D3)
- Buzzer (D4), LEDs vía 74HC595 (D11–D13)
- UART SoftwareSerial con ESP32 (RX D8, TX D9, 9600 baud)

### Cómo subir el sketch

1. Abrir `codigo_ArduinoUNO/codigo_ArduinoUNO.ino` en Arduino IDE.
2. Placa: **Arduino UNO**.
3. Subir el firmware.
4. Monitor Serial a **115200** — debe mostrar `FW UNO-GR-33`.

### Comandos UART que recibe (desde el ESP32)

| Comando | Efecto |
|---------|--------|
| `FLUSH` | Inicia descarga |
| `REFILL` | Inicia recarga (solo en reposo) |
| `LID_OPEN` / `LID_CLOSE` | Abrir / cerrar tapa |

### Eventos que envía al ESP32

- `EVT:FLUSH_START` / `EVT:FLUSH_END`
- `EVT:REFILL_START` / `EVT:REFILL_END`
- `LCD|linea0|linea1`

### Notas de desarrollo

- Loop **cooperativo** (sin `delay` largos): FSM de descarga, recarga, válvula, buzzer.
- Watchdogs: todo ciclo debe terminar y volver a **REPOSO**.
- Recarga: mediana de muestras + confirmaciones + gracia al encender bomba (evitar falsos positivos por ruido en A0).

Sketches auxiliares en el repo (diagnóstico): `codigo_testA3/`, `codigo_sensorAguaArduino/`, `test_servo/`.

---

## 2. ESP32 (`codigo_ESP32/`)

### Qué hace

- **BLE**: servicio GATT para comandos y provisioning WiFi.
- **WiFi / HTTP**: `/ping`, `/cmd`, `/evt` en red local (mDNS `inodoro_smart.local`).
- **LCD** I2C (mensajes de estado).
- **UART** hacia el UNO: reenvía comandos de la app y propaga eventos.

### Cómo subir el sketch

1. Abrir `codigo_ESP32/codigo_ESP32.ino` en Arduino IDE (o entorno ESP32).
2. Placa: **ESP32 Dev Module** (o la tuya).
3. Cablear UART con el UNO (TX/RX cruzados + GND común).
4. Subir y revisar Monitor Serial (~115200 según el sketch).

### Flujo típico

1. App se conecta por BLE → configura WiFi del ESP32.
2. En casa, la app usa LAN (mDNS / HTTP).
3. Comandos de app → ESP32 → UART → UNO.
4. Eventos UNO → UART → ESP32 → BLE notify o HTTP `/evt`.

---

## 3. Aplicación Flutter (`lib/` y empaquetado)

Package Dart: `inodoro_inteligente`  
Nombre visible: **Inodoros Fuertes**

### Requisitos

- Flutter / Dart ^3.12
- Dispositivo físico recomendado (BLE, micrófono)

```bash
flutter doctor
flutter pub get
flutter run
```

APK release:

```bash
flutter build apk --release
```

### Estructura relevante

| Ruta | Responsabilidad |
|------|-----------------|
| `lib/main.dart` | Entrada, Provider, tema |
| `lib/providers/app_provider.dart` | Estado global, sesiones BLE/LAN/demo |
| `lib/services/` | BLE, discovery LAN, voz, Gemini |
| `lib/screens/` | Home, búsqueda, conexión, sesión |
| `lib/core/constants/` | Comandos, BLE, API, voz |

### Canales de conexión

1. **Bluetooth** — emparejar ESP32 y (opcional) provisionar WiFi  
2. **LAN** — control por HTTP cuando el ESP32 ya está en la red  
3. **Modo demo** — UI sin hardware  

### Clave Gemini (voz, opcional)

```bash
cp lib/core/config/gemini_api_key.local.example.dart lib/core/config/gemini_api_key.local.dart
```

O:

```bash
flutter run --dart-define=GEMINI_API_KEY=tu_clave
```

No subir `gemini_api_key.local.dart` al repositorio.

### Permisos Android

BLE, ubicación (escaneo BLE), red, WiFi cercano, micrófono — ver `android/app/src/main/AndroidManifest.xml`.

### Tests

```bash
flutter test
flutter analyze
```

---

## Orden recomendado al desarrollar hardware + app

1. Subir y validar **Arduino UNO** (Monitor Serial, ciclo descarga/recarga).  
2. Subir y validar **ESP32** (UART + BLE o `/ping`).  
3. Ejecutar la **app Flutter** contra el dispositivo (o modo demo).  

---

## Enlaces

| Recurso | URL |
|---------|-----|
| Informe / sitio del proyecto | [sites.google.com/view/inodoro-orion/inicio](https://sites.google.com/view/inodoro-orion/inicio) |
| Repositorio | [github.com/xosueturpo/inodoro-smart.app](https://github.com/xosueturpo/inodoro-smart.app) |
| APK (descarga) | [Google Drive — inodoro-smart.apk](https://drive.google.com/uc?export=download&id=10vGvuBBmISq1BG8nMYORT7rQ2gs4ejbn) |
