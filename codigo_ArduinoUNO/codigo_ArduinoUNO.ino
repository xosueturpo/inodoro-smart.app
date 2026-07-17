/*
 * ============================================================================
 *  INODORO SMART — Firmware Arduino UNO
 *  Versión: UNO-GR-33
 * ============================================================================
 *
 *  El UNO controla actuadores y sensores. El ESP32 gestiona Bluetooth/WiFi,
 *  LCD y reenvío de comandos desde la app móvil.
 *
 *  MODOS DE OPERACIÓN
 *  ------------------
 *  · REPOSO    — Espera comandos o detección por sensor.
 *  · DESCARGA  — 10 s con válvula abierta; cierra tapa al iniciar.
 *  · RECARGA   — Relé ON hasta ADC(A0) > 400 confirmado o timeout de 5 min.
 *
 *  FIABILIDAD (GR-33)
 *  ------------------
 *  Todo ciclo debe terminar y volver a REPOSO. Watchdogs por fase y globales
 *  fuerzan cierre de válvula, apagado de relé/buzzer y EVT_*_END si hace falta.
 *
 *  COMUNICACIÓN UART (9600 baud)
 *  -----------------------------
 *  UNO D8 (RX) ← ESP32 TX2
 *  UNO D9 (TX) → ESP32 RX2
 *  GND común obligatorio.
 *
 *  Comandos entrantes : FLUSH | REFILL | LID_OPEN | LID_CLOSE
 *  Mensajes salientes : LCD|linea0|linea1  ·  EVT:FLUSH_START/END  ·  EVT:REFILL_START/END
 *
 *  PINOUT RESUMIDO
 *  ---------------
 *  A0  — Sensor nivel de agua (analógico, lectura cruda)
 *  D2  — HC-SR04 tapa Trig
 *  D3  — HC-SR04 tapa Echo
 *  D4  — Buzzer activo
 *  D5  — Servo válvula 11 kg
 *  D6  — HC-SR04 descarga Trig
 *  D7  — HC-SR04 descarga Echo
 *  D8  — UART RX (desde ESP32)
 *  D9  — UART TX (hacia ESP32)
 *  D10 — Relé bomba de recarga
 *  D11 — 74HC595 Clock
 *  D12 — 74HC595 Latch
 *  D13 — 74HC595 Data
 *  A3  — Servo tapa: pin ANALÓGICO 3 → salida DIGITAL 17 (NO es D3)
 *
 *  LED vía 74HC595: Q1 rojo | Q2 verde | Q3 azul
 *
 *  ARQUITECTURA DEL LOOP (cooperativo, sin delay largos)
 *  -----------------------------------------------------
 *  Cada ciclo ejecuta todos los servicios; ninguno bloquea al resto.
 * ============================================================================
 */

#include <SoftwareSerial.h>
#include <Servo.h>


// =============================================================================
// BLOQUE 1 — OBJETOS GLOBALES Y LIBRERÍAS
// =============================================================================

SoftwareSerial espLink(8, 9);   // RX=D8, TX=D9
Servo valvulaServo;
Servo tapaServo;


// =============================================================================
// BLOQUE 2 — CONFIGURACIÓN DE PINES
// =============================================================================

const int servoPin      = 5;    // Servo válvula principal (D5)

// Tapa: bloque ANALOG IN, etiqueta A3 → pin digital 17 en ATmega328P.
// NO usar D3 (pin digital 3): ese es tapaEchoPin del ultrasónico.
const uint8_t TAPA_SERVO_ANALOG_PIN  = A3;   // Header "ANALOG IN", 4.º pin A3
const uint8_t TAPA_SERVO_DIGITAL_PIN = 17;   // Mismo pin físico, modo digital

const int tapaTrigPin   = 2;    // Ultrasónico tapa — disparo (D2)
const int tapaEchoPin   = 3;    // Ultrasónico tapa — eco (D3, NO es A3)
const int clockPin      = 11;   // 74HC595
const int latchPin      = 12;
const int dataPin       = 13;
const int trigPin       = 6;    // Ultrasónico descarga — disparo
const int echoPin       = 7;    // Ultrasónico descarga — eco
const int pinNivelAgua  = A0;   // Sensor nivel agua
const int buzzerPin     = 4;
const int relayPin      = 10;   // Bomba / electroválvula de recarga


// =============================================================================
// BLOQUE 3 — CONSTANTES
// =============================================================================

// --- Relé ---
const uint8_t RELAY_ON  = HIGH;
const uint8_t RELAY_OFF = LOW;

// --- LEDs en registro de desplazamiento 74HC595 ---
const byte Q1 = 0b00000010;   // Rojo   — agua insuficiente
const byte Q2 = 0b00000100;   // Verde  — reposo normal
const byte Q3 = 0b00001000;   // Azul   — descarga / recarga activa

// --- Tiempos generales ---
const unsigned long FASE_DESCARGA_MS   = 10000;    // Duración de la descarga
const unsigned long RECARGA_MAX_MS     = 300000;   // Tope recarga: 5 minutos
const int           NIVEL_AGUA_OK      = 400;      // ADC mínimo para dar por lleno
const int           NIVEL_AGUA_HYST    = 30;       // Histéresis para reiniciar confirmación
const unsigned long NIVEL_LECTURA_MS   = 200;     // Intervalo entre lecturas ADC
const uint8_t       NIVEL_MUESTRAS     = 5;        // Muestras por lectura (mediana)
const uint8_t       NIVEL_CONFIRM_N    = 4;        // Lecturas seguidas >400 para parar
const unsigned long RECARGA_GRACE_MS   = 2000;     // Ignorar umbral al encender bomba
const unsigned long BLINK_INTERVAL_MS  = 250;    // Parpadeo LED azul en descarga

// --- Buzzer ---
const unsigned long BUZZER_BEEP_MS              = 150;
const unsigned long BUZZER_PAUSA_DESCARGA_MS    = 150;
const unsigned long BUZZER_RECARGA_MS           = 1000;
const uint8_t       BUZZER_BEEPS_DESCARGA       = 3;
const bool          BUZZER_ENABLED              = true;

// --- Sensor proximidad descarga (HC-SR04 D6/D7) ---
const unsigned long PROXIMITY_COOLDOWN_MS       = 1500;  // Enfriamiento tras volver a reposo
const unsigned long PROXIMITY_READ_MS         = 200;
const int           PROXIMITY_CM                = 5;
const int           PROXIMITY_CM_MIN            = 2;
const uint8_t       PROXIMITY_CONFIRM_NEEDED    = 3;   // Lecturas consecutivas para confirmar

// --- Tapa (servo A3 + HC-SR04 D2/D3) ---
const int           TAPA_GRADOS_CERRADO         = 0;
const int           TAPA_GRADOS_ABIERTO         = 85;
const unsigned long TAPA_PROX_READ_MS           = 120;
const int           TAPA_PROXIMITY_CM           = 5;
const int           TAPA_PROXIMITY_CM_MIN       = 2;
const uint8_t       TAPA_PROX_CONFIRM_NEEDED    = 3;

// --- Válvula (servo 11 kg en D5) ---
const uint8_t       VALVULA_GRADOS_CERRADO        = 0;
const uint8_t       VALVULA_GRADOS_ABIERTO        = 20;
const int           VALVULA_PWM_MIN_US            = 500;
const int           VALVULA_PWM_MAX_US            = 2500;
const unsigned long VALVULA_MOVE_MS               = 1800;  // Tiempo de recorrido completo
const unsigned long VALVULA_SETTLE_MS             = 500;   // Asentamiento tras movimiento
const unsigned long VALVULA_HOLD_REFRESH_MS       = 80;    // Refresco PWM para mantener torque
const unsigned long VALVULA_MOV_TIMEOUT_MS        = 4000;  // Tope duro movimiento válvula

// --- Watchdogs de ciclo (garantizan vuelta a REPOSO) ---
const unsigned long DESCARGA_PITIDOS_MAX_MS       = 3000;  // Si buzzer no termina, forzar avance
const unsigned long DESCARGA_CICLO_MAX_MS         = 45000; // Tope total descarga → abortar a reposo
const unsigned long RECARGA_CICLO_MAX_MS          = RECARGA_MAX_MS; // Alias explícito
const unsigned long WATCHDOG_LOG_MS              = 10000; // Latido de depuración
const unsigned long ESP_LINE_TIMEOUT_MS          = 2000;  // Descarta línea UART incompleta

// --- UART con ESP32 ---
const uint8_t ESP_RX_MAX_POR_LOOP = 48;   // Límite de bytes por ciclo (evita saturación)


// =============================================================================
// BLOQUE 4 — TIPOS Y ENUMERACIONES
// =============================================================================

/** Posición de la tapa: solo cerrada (0°) o abierta (85°). Sin estados intermedios. */
enum TapaEstado {
  TAPA_CERRADA,
  TAPA_ABIERTA,
};

/** Posición lógica de la válvula (para depuración). */
enum ServoPosicion { SERVO_CERRADO, SERVO_ABIERTO };

/** Secuencias de pitidos del buzzer (no bloqueantes). */
enum BuzzerModo { BUZZER_OFF, BUZZER_DESCARGA, BUZZER_RECARGA };

/**
 * Sub-estados de la descarga.
 * La descarga avanza paso a paso sin bloquear el loop principal.
 */
enum DescargaSub {
  DSC_IDLE,
  DSC_PITIDOS,
  DSC_PRE_ACTIVAR,
  DSC_ABRIENDO_VALVULA,
  DSC_ACTIVA,
  DSC_FINALIZANDO,
};

/** Modo global del sistema. */
enum Modo { MODO_REPOSO, MODO_DESCARGA, MODO_RECARGA };


// =============================================================================
// BLOQUE 5 — VARIABLES DE ESTADO GLOBAL
// =============================================================================

// --- Válvula ---
bool          servoInicializado      = false;
ServoPosicion servoPosActual         = SERVO_CERRADO;
int           ultimoGradosServo      = -1;
int           valvulaGradosHold      = VALVULA_GRADOS_CERRADO;
bool          valvulaMantenerEnganchada = false;
unsigned long ultimoRefreshValvula   = 0;
bool          valvulaMovimientoActivo  = false;
int           valvulaGradosObjetivo  = VALVULA_GRADOS_CERRADO;
unsigned long valvulaMovimientoInicio  = 0;

// --- Buzzer ---
BuzzerModo    buzzerModo             = BUZZER_OFF;
uint8_t       buzzerBeepsRestantes     = 0;
unsigned long buzzerHasta              = 0;
unsigned long buzzerSecuenciaInicio    = 0;
bool          buzzerEncendido          = false;

// --- Descarga (FSM) ---
DescargaSub   descargaSub              = DSC_IDLE;
unsigned long descargaCicloInicio      = 0;   // Reloj del ciclo completo
unsigned long descargaFaseInicio       = 0;   // Reloj de la sub-fase actual
bool          descargaFlushStartEnviado = false;

// --- Tapa ---
int           tapaGradosActual         = TAPA_GRADOS_CERRADO;
TapaEstado    tapaEstado               = TAPA_CERRADA;
bool          tapaProxCerca            = false;
unsigned long ultimaLecturaTapaProx    = 0;
uint8_t       tapaProxConfirmCount     = 0;
long          tapaUsSamples[3]         = {-1, -1, -1};
uint8_t       tapaUsSampleIdx         = 0;

// --- UART / comandos ---
char          lineBuffer[128];
uint8_t       lineLen                  = 0;
bool          espLinkActivo              = false;
unsigned long ultimaRxEspByte          = 0;

// --- Sistema general ---
Modo          modo                     = MODO_REPOSO;
bool          parpadeoEncendido        = true;
bool          manoCerca                = false;
unsigned long faseInicio               = 0;
unsigned long ultimoParpadeo           = 0;
unsigned long proximidadListaEn        = 0;
unsigned long ultimaLecturaProx        = 0;
unsigned long ultimaLecturaNivel       = 0;
uint8_t       nivelConfirmCount        = 0;
uint8_t       proxConfirmCount         = 0;
long          proxUsSamples[3]         = {-1, -1, -1};
uint8_t       proxUsSampleIdx          = 0;
unsigned long ultimoWatchdogLog        = 0;

// Declaraciones adelantadas
void tapaPonerCerrada();
void tapaEscribirGrado(int grados);
void forzarFinValvulaMovimiento(const char *motivo);
void abortarDescarga(const char *motivo);
void serviceWatchdogCiclos();
void serviceValvulaMovimiento();
void serviceBuzzer();
void entrarReposo(bool avisarRefillEnd);
void entrarReposoSinServo(bool avisarRefillEnd);
void finalizarRecargaTimeout();
void procesarLineaEsp();


// =============================================================================
// BLOQUE 6 — COMUNICACIÓN UART CON ESP32
// =============================================================================

/** Detiene SoftwareSerial para liberar el bus durante movimientos de servo. */
void espLinkPausar() {
  if (espLinkActivo) {
    espLink.flush();
    espLink.end();
    espLinkActivo = false;
  }
}

/** Reinicia SoftwareSerial y descarta bytes pendientes. */
void espLinkReanudar() {
  if (!espLinkActivo) {
    espLink.begin(9600);
    espLinkActivo = true;
    while (espLink.available()) espLink.read();
  }
}

/**
 * Abre UART si no hay movimiento activo de válvula.
 * La tapa permanece enganchada siempre: no debe bloquear SoftSerial.
 */
void espLinkAsegurar() {
  if (!valvulaMovimientoActivo) {
    espLinkReanudar();
  }
}

/**
 * Seguridad de recuperación: si el enlace quedó pausado sin movimiento
 * de válvula en curso, lo reactiva al final de cada ciclo del loop.
 */
void recuperarEnlace() {
  if (!espLinkActivo && !valvulaMovimientoActivo) {
    espLinkReanudar();
  }
}

/** Vacía el buffer de recepción y reinicia el acumulador de línea. */
void vaciarEspLink() {
  while (espLink.available()) espLink.read();
  lineLen = 0;
  lineBuffer[0] = '\0';
}

/**
 * Lee comandos del ESP32 carácter a carácter.
 * Procesa una línea completa al recibir '\n'.
 * Limita la lectura por ciclo para no monopolizar el loop.
 */
void serviceEsp() {
  espLinkAsegurar();

  // Línea a medias sin '\n': descartar para no bloquear comandos futuros.
  if (lineLen > 0 && ultimaRxEspByte != 0 &&
      millis() - ultimaRxEspByte >= ESP_LINE_TIMEOUT_MS) {
    Serial.println(F("[ESP] linea incompleta descartada"));
    lineLen = 0;
    lineBuffer[0] = '\0';
    ultimaRxEspByte = 0;
  }

  uint8_t leidos = 0;
  while (espLink.available() && leidos < ESP_RX_MAX_POR_LOOP) {
    const char c = espLink.read();
    leidos++;
    ultimaRxEspByte = millis();
    if (c == '\n') {
      procesarLineaEsp();
      ultimaRxEspByte = 0;
    } else if (c != '\r' && c >= 32 && c <= 126 && lineLen < sizeof(lineBuffer) - 1) {
      lineBuffer[lineLen++] = c;
    }
  }
}


// =============================================================================
// BLOQUE 7 — SERVO VÁLVULA (11 kg, D5)
// =============================================================================

/** Engancha el servo de válvula con rango PWM calibrado. */
void valvulaServoAttach() {
  if (!valvulaServo.attached()) {
    valvulaServo.attach(servoPin, VALVULA_PWM_MIN_US, VALVULA_PWM_MAX_US);
  }
}

/**
 * Mantiene la válvula en un ángulo con PWM continuo.
 * Necesario para que el servo de 11 kg no ceda ante la presión mecánica.
 */
void valvulaServoRetener(int grados) {
  grados = constrain(grados, VALVULA_GRADOS_CERRADO, VALVULA_GRADOS_ABIERTO);
  valvulaGradosHold = grados;
  valvulaServoAttach();
  valvulaServo.write(grados);
  valvulaMantenerEnganchada = true;
  ultimoGradosServo = grados;
  ultimoRefreshValvula = millis();
  servoPosActual =
      grados >= VALVULA_GRADOS_ABIERTO ? SERVO_ABIERTO : SERVO_CERRADO;
}

/** Desengancha el servo de válvula antes de transmitir por UART. */
void valvulaServoPausaUart() {
  if (valvulaServo.attached()) {
    valvulaServo.detach();
  }
  valvulaMantenerEnganchada = false;
}

/**
 * Inicia un movimiento de válvula de forma no bloqueante.
 * La tapa NO se toca: permanece en 0° o 85° con su propio servo.
 */
void valvulaIniciarMovimiento(int grados) {
  grados = constrain(grados, VALVULA_GRADOS_CERRADO, VALVULA_GRADOS_ABIERTO);

  if (grados == ultimoGradosServo && valvulaServo.attached() && !valvulaMovimientoActivo) {
    valvulaServoRetener(grados);
    return;
  }

  espLinkPausar();

  valvulaServoAttach();
  valvulaGradosObjetivo = grados;
  valvulaMovimientoActivo = true;
  valvulaMovimientoInicio = millis();
  valvulaServo.write(grados);
  valvulaMantenerEnganchada = false;
}

/** Avanza el movimiento de válvula; al terminar entra en modo HOLD. */
void serviceValvulaMovimiento() {
  if (!valvulaMovimientoActivo) return;

  const unsigned long elapsed = millis() - valvulaMovimientoInicio;

  // Tope duro: nunca dejar el flag activo más de VALVULA_MOV_TIMEOUT_MS.
  if (elapsed >= VALVULA_MOV_TIMEOUT_MS) {
    forzarFinValvulaMovimiento("timeout");
    return;
  }

  if (elapsed < VALVULA_MOVE_MS + VALVULA_SETTLE_MS) {
    return;
  }

  valvulaMovimientoActivo = false;
  valvulaServoRetener(valvulaGradosObjetivo);
  servoInicializado = false;
  espLinkReanudar();

  Serial.print(F("[VALVULA "));
  Serial.print(valvulaGradosObjetivo);
  Serial.println(F("° HOLD]"));
}

/** Fuerza el fin del movimiento de válvula para no colgar la FSM. */
void forzarFinValvulaMovimiento(const char *motivo) {
  if (!valvulaMovimientoActivo) return;

  valvulaMovimientoActivo = false;
  valvulaServoRetener(valvulaGradosObjetivo);
  servoInicializado = false;
  espLinkReanudar();

  Serial.print(F("[VALVULA] forzar fin ("));
  Serial.print(motivo);
  Serial.print(F(") → "));
  Serial.print(valvulaGradosObjetivo);
  Serial.println(F("° HOLD"));
}

/** Refresca el PWM de la válvula periódicamente para mantener el torque. */
void serviceValvulaHold() {
  if (!valvulaMantenerEnganchada || !valvulaServo.attached()) return;
  if (valvulaMovimientoActivo) return;

  const unsigned long ahora = millis();
  if (ahora - ultimoRefreshValvula < VALVULA_HOLD_REFRESH_MS) return;
  ultimoRefreshValvula = ahora;

  valvulaServo.write(valvulaGradosHold);
}

/**
 * Movimiento bloqueante de válvula.
 * Solo se usa en setup(); el loop principal usa valvulaIniciarMovimiento().
 */
void valvulaServoMoverBloqueante(int grados) {
  valvulaIniciarMovimiento(grados);
  while (valvulaMovimientoActivo) {
    serviceValvulaMovimiento();
    serviceBuzzer();
  }
}


// =============================================================================
// BLOQUE 8 — BUZZER (D4)
// =============================================================================

void setBuzzer(bool activo) {
  if (!BUZZER_ENABLED) activo = false;
  digitalWrite(buzzerPin, activo ? HIGH : LOW);
}

/** Arranca la secuencia de 3 pitidos al iniciar descarga. */
void buzzerIniciarDescarga() {
  if (!BUZZER_ENABLED) return;
  buzzerModo = BUZZER_DESCARGA;
  buzzerBeepsRestantes = BUZZER_BEEPS_DESCARGA;
  buzzerEncendido = false;
  buzzerSecuenciaInicio = millis();
  buzzerHasta = millis();
}

/** Arranca el pitido largo de 1 s al iniciar recarga. */
void buzzerIniciarRecarga() {
  if (!BUZZER_ENABLED) return;
  buzzerModo = BUZZER_RECARGA;
  buzzerEncendido = false;
  buzzerSecuenciaInicio = millis();
  buzzerHasta = millis();
}

/** Avanza la máquina de estados del buzzer sin usar delay(). */
void serviceBuzzer() {
  if (buzzerModo == BUZZER_OFF) return;

  const unsigned long ahora = millis();

  // Tope duro: apagar si la secuencia se alarga (evita buzz permanente).
  const unsigned long maxMs =
      (buzzerModo == BUZZER_RECARGA) ? (BUZZER_RECARGA_MS + 500)
                                     : DESCARGA_PITIDOS_MAX_MS;
  if (ahora - buzzerSecuenciaInicio >= maxMs) {
    setBuzzer(false);
    buzzerModo = BUZZER_OFF;
    buzzerEncendido = false;
    Serial.println(F("[BUZZER] timeout — OFF"));
    return;
  }

  if (ahora < buzzerHasta) return;

  if (buzzerModo == BUZZER_RECARGA) {
    if (!buzzerEncendido) {
      setBuzzer(true);
      buzzerEncendido = true;
      buzzerHasta = ahora + BUZZER_RECARGA_MS;
    } else {
      setBuzzer(false);
      buzzerModo = BUZZER_OFF;
      Serial.println(F("[BUZZER] 1 s recarga"));
    }
    return;
  }

  // Secuencia de descarga: beep → pausa → beep → ...
  if (buzzerEncendido) {
    setBuzzer(false);
    buzzerEncendido = false;
    buzzerBeepsRestantes--;
    if (buzzerBeepsRestantes == 0) {
      buzzerModo = BUZZER_OFF;
      Serial.println(F("[BUZZER] 3 pitidos descarga"));
    } else {
      buzzerHasta = ahora + BUZZER_PAUSA_DESCARGA_MS;
    }
  } else {
    setBuzzer(true);
    buzzerEncendido = true;
    buzzerHasta = ahora + BUZZER_BEEP_MS;
  }
}


// =============================================================================
// BLOQUE 9 — SALIDAS DIGITALES (LED 74HC595 Y RELÉ)
// =============================================================================

/** Envía un byte al registro de desplazamiento para controlar los LEDs RGB. */
void enviarByte(byte data) {
  digitalWrite(latchPin, LOW);
  shiftOut(dataPin, clockPin, MSBFIRST, data);
  digitalWrite(latchPin, HIGH);
}

/** Activa o desactiva el relé de recarga (D10). */
void setRelay(bool activo) {
  digitalWrite(relayPin, activo ? RELAY_ON : RELAY_OFF);
}


// =============================================================================
// BLOQUE 10 — MENSAJES HACIA ESP32 (LCD Y EVENTOS)
// =============================================================================

/**
 * Envía texto al LCD del ESP32.
 * Formato: LCD|linea0|linea1
 */
void enviarLcd(const char *line0, const char *line1) {
  valvulaServoPausaUart();
  espLinkReanudar();
  espLink.print(F("LCD|"));
  espLink.print(line0);
  espLink.print('|');
  espLink.println(line1);
  espLink.flush();
  if (!valvulaMovimientoActivo) {
    valvulaServoRetener(valvulaGradosHold);
  }
  Serial.print(F("[LCD→] "));
  Serial.print(line0);
  Serial.print(F(" | "));
  Serial.println(line1);
}

/**
 * Notifica un evento a la app vía ESP32.
 * Formato: EVT:NOMBRE  (ej. EVT:FLUSH_START)
 */
void enviarEvento(const __FlashStringHelper *evento) {
  valvulaServoPausaUart();
  espLinkReanudar();
  espLink.print(F("EVT:"));
  espLink.println(evento);
  espLink.flush();
  if (!valvulaMovimientoActivo) {
    valvulaServoRetener(valvulaGradosHold);
  }
}


// =============================================================================
// BLOQUE 11 — TAPA (SERVO A3 / PIN 17) — SOLO 0° O 85°, SIN LÓGICA INTERMEDIA
// =============================================================================
//
//  Reglas simples:
//  · Abrir  → write(85) una vez, queda abierta.
//  · Cerrar → write(0) una vez, queda cerrada.
//  · Descarga → cierra a 0° al inicio y NO se vuelve a tocar hasta terminar.
//  · Nunca se desengancha por movimientos de la válvula.

void tapaPinSalidaDigital() {
  pinMode(TAPA_SERVO_DIGITAL_PIN, OUTPUT);
  digitalWrite(TAPA_SERVO_DIGITAL_PIN, LOW);
}

void tapaServoEnganchar() {
  if (tapaServo.attached()) return;
  tapaPinSalidaDigital();
  tapaServo.attach(TAPA_SERVO_DIGITAL_PIN);
}

void tapaEscribirGrado(int grados) {
  grados = constrain(grados, TAPA_GRADOS_CERRADO, TAPA_GRADOS_ABIERTO);
  tapaServoEnganchar();
  tapaServo.write(grados);
  tapaGradosActual = grados;
}

void tapaPonerCerrada() {
  tapaEstado = TAPA_CERRADA;
  tapaGradosActual = TAPA_GRADOS_CERRADO;
  tapaEscribirGrado(TAPA_GRADOS_CERRADO);
}

void tapaPonerAbierta() {
  tapaEstado = TAPA_ABIERTA;
  tapaGradosActual = TAPA_GRADOS_ABIERTO;
  tapaEscribirGrado(TAPA_GRADOS_ABIERTO);
}

bool tapaPuedeAbrir() {
  return modo != MODO_DESCARGA && tapaEstado != TAPA_ABIERTA;
}

bool tapaPuedeCerrar() {
  return modo != MODO_DESCARGA && tapaEstado != TAPA_CERRADA;
}

void tapaServoInicializar() {
  tapaPonerCerrada();
  Serial.print(F("[TAPA] init pin "));
  Serial.print(TAPA_SERVO_DIGITAL_PIN);
  Serial.println(F(" → 0° (solo 0/85, sin pasos)"));
}

void tapaAbrir() {
  if (!tapaPuedeAbrir()) return;
  tapaPonerAbierta();
  Serial.println(F("[TAPA] 85° abierta"));
}

void tapaCerrar() {
  if (!tapaPuedeCerrar()) return;
  tapaPonerCerrada();
  Serial.println(F("[TAPA] 0° cerrada"));
}


// =============================================================================
// BLOQUE 12 — ESTADOS DEL SISTEMA (REPOSO)
// =============================================================================

/**
 * Entra en reposo sin mover la válvula.
 * Usado al finalizar descarga cuando la válvula ya está cerrándose.
 */
void entrarReposoSinServo(bool avisarRefillEnd) {
  modo = MODO_REPOSO;
  descargaSub = DSC_IDLE;
  descargaFlushStartEnviado = false;
  parpadeoEncendido = true;
  setRelay(false);
  setBuzzer(false);
  buzzerModo = BUZZER_OFF;
  buzzerEncendido = false;
  enviarByte(Q2);
  proximidadListaEn = millis() + PROXIMITY_COOLDOWN_MS;
  proxConfirmCount = 0;
  manoCerca = false;
  nivelConfirmCount = 0;
  enviarLcd("Bienvenido", "");
  if (avisarRefillEnd) enviarEvento(F("REFILL_END"));
  espLinkReanudar();
  Serial.println(F("[REPOSO]"));
}

/** Entra en reposo y cierra la válvula de forma cooperativa. */
void entrarReposo(bool avisarRefillEnd) {
  entrarReposoSinServo(avisarRefillEnd);
  valvulaIniciarMovimiento(VALVULA_GRADOS_CERRADO);
}

/**
 * Reposo con error de agua insuficiente.
 * LED rojo y mensaje en LCD; la recarga no alcanzó ADC > 400 en 5 min.
 */
void entrarReposoAguaInsuficiente() {
  modo = MODO_REPOSO;
  descargaSub = DSC_IDLE;
  descargaFlushStartEnviado = false;
  parpadeoEncendido = true;
  setRelay(false);
  setBuzzer(false);
  buzzerModo = BUZZER_OFF;
  buzzerEncendido = false;
  enviarByte(Q1);
  proximidadListaEn = millis() + PROXIMITY_COOLDOWN_MS;
  proxConfirmCount = 0;
  manoCerca = false;
  nivelConfirmCount = 0;
  enviarLcd("No hay suficiente", "agua");
  enviarEvento(F("REFILL_END"));
  valvulaIniciarMovimiento(VALVULA_GRADOS_CERRADO);
  espLinkReanudar();
  Serial.println(F("[REPOSO] sin agua — LED rojo"));
}


// =============================================================================
// BLOQUE 13 — SENSOR DE NIVEL DE AGUA Y RECARGA
// =============================================================================

/** Mediana de cinco enteros (descarta picos de ruido de la bomba/relé). */
int mediana5(int a, int b, int c, int d, int e) {
  int v[5] = {a, b, c, d, e};
  for (uint8_t i = 0; i < 4; i++) {
    for (uint8_t j = i + 1; j < 5; j++) {
      if (v[j] < v[i]) {
        const int t = v[i];
        v[i] = v[j];
        v[j] = t;
      }
    }
  }
  return v[2];
}

/** Lectura cruda del ADC en A0. */
int leerNivelAguaCrudo() {
  return analogRead(pinNivelAgua);
}

/**
 * Lectura filtrada: mediana de NIVEL_MUESTRAS tomas en A0.
 * Evita falsas paradas por ruido eléctrico al arrancar la bomba.
 */
int leerNivelAguaFiltrado() {
  const int a = analogRead(pinNivelAgua);
  delayMicroseconds(400);
  const int b = analogRead(pinNivelAgua);
  delayMicroseconds(400);
  const int c = analogRead(pinNivelAgua);
  delayMicroseconds(400);
  const int d = analogRead(pinNivelAgua);
  delayMicroseconds(400);
  const int e = analogRead(pinNivelAgua);
  return mediana5(a, b, c, d, e);
}

/** Recarga completada: nivel confirmó superar el umbral. */
void finalizarRecargaOk() {
  Serial.print(F("[RECARGA] OK nivel="));
  Serial.print(leerNivelAguaFiltrado());
  Serial.print(F(" confirm="));
  Serial.println(nivelConfirmCount);
  nivelConfirmCount = 0;
  entrarReposo(true);
}

/** Recarga agotó el tiempo máximo sin alcanzar el nivel. */
void finalizarRecargaTimeout() {
  Serial.print(F("[RECARGA] timeout — ultimo nivel="));
  Serial.println(leerNivelAguaFiltrado());
  nivelConfirmCount = 0;
  entrarReposoAguaInsuficiente();
}

/**
 * Evalúa el sensor durante RECARGA.
 * Para solo si N lecturas seguidas (filtradas) superan 400.
 * Primeros RECARGA_GRACE_MS se ignoran picos al encender la bomba.
 */
void evaluarRecarga() {
  if (modo != MODO_RECARGA) return;

  const unsigned long ahora = millis();

  if (ahora - faseInicio >= RECARGA_MAX_MS) {
    finalizarRecargaTimeout();
    return;
  }

  if (ahora - faseInicio < RECARGA_GRACE_MS) return;

  if (ultimaLecturaNivel != 0 &&
      ahora - ultimaLecturaNivel < NIVEL_LECTURA_MS) {
    return;
  }
  ultimaLecturaNivel = ahora;

  const int nivel = leerNivelAguaFiltrado();
  Serial.print(F("[NIVEL] "));
  Serial.print(nivel);
  Serial.print(F(" confirm="));
  Serial.println(nivelConfirmCount);

  if (nivel > NIVEL_AGUA_OK) {
    nivelConfirmCount++;
    if (nivelConfirmCount >= NIVEL_CONFIRM_N) {
      finalizarRecargaOk();
    }
    return;
  }

  if (nivel < NIVEL_AGUA_OK - NIVEL_AGUA_HYST) {
    nivelConfirmCount = 0;
  }
}

/** Inicia la recarga manual (comando REFILL o voz). Solo desde reposo. */
void iniciarRecarga(const char *origen) {
  if (modo != MODO_REPOSO) return;

  if (valvulaMovimientoActivo) {
    forzarFinValvulaMovimiento("pre-recarga");
  }

  modo = MODO_RECARGA;
  faseInicio = millis();
  ultimaLecturaNivel = 0;
  nivelConfirmCount = 0;

  setRelay(true);
  enviarByte(Q2 | Q3);
  enviarLcd("Recargando", "Tanque");
  enviarEvento(F("REFILL_START"));
  Serial.print(F("[RECARGA] "));
  Serial.print(origen);
  Serial.print(F(" | ADC>"));
  Serial.print(NIVEL_AGUA_OK);
  Serial.print(F(" x"));
  Serial.print(NIVEL_CONFIRM_N);
  Serial.print(F(" confirm, max "));
  Serial.print(RECARGA_MAX_MS / 60000);
  Serial.println(F(" min"));

  valvulaIniciarMovimiento(VALVULA_GRADOS_CERRADO);
  buzzerIniciarRecarga();
}

/** Punto de servicio de recarga llamado en cada ciclo del loop. */
void serviceRecarga() {
  evaluarRecarga();
}


// =============================================================================
// BLOQUE 14 — DESCARGA (MÁQUINA DE ESTADOS)
// =============================================================================

/**
 * Aborta la descarga en curso y vuelve a REPOSO de forma segura.
 * Garantiza EVT:FLUSH_END si ya se envió START, cierra válvula y apaga salidas.
 */
void abortarDescarga(const char *motivo) {
  Serial.print(F("[DESCARGA] ABORT "));
  Serial.println(motivo);

  forzarFinValvulaMovimiento("abort-descarga");
  setRelay(false);
  setBuzzer(false);
  buzzerModo = BUZZER_OFF;
  buzzerEncendido = false;

  if (descargaFlushStartEnviado) {
    enviarLcd("Cerrando", "Valvula");
    enviarEvento(F("FLUSH_END"));
    descargaFlushStartEnviado = false;
  }

  descargaSub = DSC_IDLE;
  entrarReposo(false);
}

/**
 * Solicita una descarga.
 * Origen: "app", "sensor" o "voz".
 * Solo acepta si el sistema está en reposo.
 */
void iniciarDescarga(const char *origen) {
  if (modo != MODO_REPOSO || descargaSub != DSC_IDLE) return;

  // Si un movimiento previo quedó colgado, forzar fin antes de empezar.
  if (valvulaMovimientoActivo) {
    forzarFinValvulaMovimiento("pre-descarga");
  }

  modo = MODO_DESCARGA;
  parpadeoEncendido = true;
  tapaProxConfirmCount = 0;
  tapaProxCerca = false;
  descargaCicloInicio = millis();
  descargaFaseInicio = millis();
  descargaFlushStartEnviado = false;
  setRelay(false);
  setBuzzer(false);
  buzzerModo = BUZZER_OFF;
  buzzerEncendido = false;

  // Cierra tapa al instante; durante toda la descarga no se vuelve a mover.
  tapaPonerCerrada();
  Serial.println(F("[TAPA] 0° — bloqueada durante descarga"));

  descargaSub = DSC_PITIDOS;
  buzzerIniciarDescarga();
  // Si buzzer deshabilitado, avanzar ya (buzzerModo sigue OFF).
  if (buzzerModo == BUZZER_OFF) {
    descargaSub = DSC_PRE_ACTIVAR;
    descargaFaseInicio = millis();
  }

  Serial.print(F("[DESCARGA] "));
  Serial.println(origen);
}

/**
 * Avanza la secuencia de descarga sin bloquear el loop.
 *
 * Flujo: tapa 0° → pitidos → abrir válvula → 10 s activa → cerrar válvula → reposo
 * Cada sub-fase tiene timeout; el ciclo completo también (DESCARGA_CICLO_MAX_MS).
 */
void serviceDescargaFsm() {
  if (modo != MODO_DESCARGA) return;

  const unsigned long ahora = millis();

  // Watchdog de ciclo completo: nunca quedarse en descarga indefinidamente.
  if (ahora - descargaCicloInicio >= DESCARGA_CICLO_MAX_MS) {
    abortarDescarga("ciclo-max");
    return;
  }

  switch (descargaSub) {
    case DSC_IDLE:
      // Estado inconsistente: modo descarga pero sub IDLE → recuperar.
      abortarDescarga("sub-idle");
      break;

    case DSC_PITIDOS:
      if (buzzerModo == BUZZER_OFF ||
          ahora - descargaFaseInicio >= DESCARGA_PITIDOS_MAX_MS) {
        if (buzzerModo != BUZZER_OFF) {
          setBuzzer(false);
          buzzerModo = BUZZER_OFF;
          buzzerEncendido = false;
          Serial.println(F("[DESCARGA] pitidos timeout — avance"));
        }
        descargaSub = DSC_PRE_ACTIVAR;
        descargaFaseInicio = ahora;
      }
      break;

    case DSC_PRE_ACTIVAR:
      faseInicio = ahora;
      ultimoParpadeo = faseInicio;
      enviarByte(Q3);
      enviarLcd("Descargando Agua", "");
      enviarEvento(F("FLUSH_START"));
      descargaFlushStartEnviado = true;
      valvulaIniciarMovimiento(VALVULA_GRADOS_ABIERTO);
      descargaSub = DSC_ABRIENDO_VALVULA;
      descargaFaseInicio = ahora;
      break;

    case DSC_ABRIENDO_VALVULA:
      if (valvulaMovimientoActivo &&
          ahora - descargaFaseInicio >= VALVULA_MOV_TIMEOUT_MS) {
        forzarFinValvulaMovimiento("abrir-timeout");
      }
      if (!valvulaMovimientoActivo) {
        descargaSub = DSC_ACTIVA;
        descargaFaseInicio = ahora;
        // Reloj de fase activa: 10 s desde válvula ya abierta.
        faseInicio = ahora;
      }
      break;

    case DSC_ACTIVA: {
      if (ahora - ultimoParpadeo >= BLINK_INTERVAL_MS) {
        parpadeoEncendido = !parpadeoEncendido;
        enviarByte(parpadeoEncendido ? Q3 : 0);
        ultimoParpadeo = ahora;
      }
      if (ahora - faseInicio >= FASE_DESCARGA_MS) {
        descargaSub = DSC_FINALIZANDO;
        descargaFaseInicio = ahora;
        enviarLcd("Cerrando", "Valvula");
        enviarEvento(F("FLUSH_END"));
        descargaFlushStartEnviado = false;
        valvulaIniciarMovimiento(VALVULA_GRADOS_CERRADO);
      }
      break;
    }

    case DSC_FINALIZANDO:
      if (valvulaMovimientoActivo &&
          ahora - descargaFaseInicio >= VALVULA_MOV_TIMEOUT_MS) {
        forzarFinValvulaMovimiento("cerrar-timeout");
      }
      if (!valvulaMovimientoActivo) {
        descargaSub = DSC_IDLE;
        entrarReposoSinServo(false);
      }
      break;
  }
}


// =============================================================================
// BLOQUE 15 — COMANDOS UART (DESDE APP / ESP32)
// =============================================================================

/** Comparación de comandos sin distinguir mayúsculas/minúsculas. */
bool eqCmd(const char *cmd, const char *lit) {
  while (*cmd && *lit) {
    char a = *cmd++;
    char b = *lit++;
    if (a >= 'a' && a <= 'z') a -= 32;
    if (b >= 'a' && b <= 'z') b -= 32;
    if (a != b) return false;
  }
  return *cmd == '\0' && *lit == '\0';
}

/**
 * Ejecuta un comando recibido por UART.
 * FLUSH    — Inicia descarga
 * REFILL   — Inicia recarga (solo en reposo)
 * LID_OPEN  — Abre tapa si está permitido
 * LID_CLOSE — Cierra tapa (no durante descarga)
 */
void aplicarCmd(const char *cmd) {
  Serial.print(F("[CMD] "));
  Serial.println(cmd);

  if (eqCmd(cmd, "FLUSH")) {
    iniciarDescarga("app");
    return;
  }
  if (eqCmd(cmd, "REFILL")) {
    if (modo == MODO_REPOSO) iniciarRecarga("app");
    return;
  }
  if (eqCmd(cmd, "LID_OPEN")) {
    if (tapaPuedeAbrir()) tapaAbrir();
    return;
  }
  if (eqCmd(cmd, "LID_CLOSE")) {
    if (tapaPuedeCerrar()) tapaCerrar();
    return;
  }
}

/** Procesa la línea acumulada en lineBuffer y la limpia. */
void procesarLineaEsp() {
  while (lineLen > 0 && lineBuffer[lineLen - 1] == '\r') {
    lineBuffer[--lineLen] = '\0';
  }
  if (lineLen == 0) return;
  lineBuffer[lineLen] = '\0';
  aplicarCmd(lineBuffer);
  lineLen = 0;
  lineBuffer[0] = '\0';
}


// =============================================================================
// BLOQUE 16 — SENSORES ULTRASÓNICOS (UTILIDADES Y LECTURA)
// =============================================================================

/** Mediana de tres valores (filtro de ruido). */
long mediana3(long a, long b, long c) {
  if (a > b) { const long t = a; a = b; b = t; }
  if (b > c) { const long t = b; b = c; c = t; }
  if (a > b) { const long t = a; a = b; b = t; }
  return b;
}

/** Calcula mediana o promedio según cuántas muestras válidas hay. */
long medianaMuestras(long *vals, uint8_t n) {
  if (n == 0) return -1;
  if (n == 1) return vals[0];
  if (n == 2) return (vals[0] + vals[1]) / 2;
  return mediana3(vals[0], vals[1], vals[2]);
}

/** Una lectura del HC-SR04 de la tapa (cm). Retorna -1 si no hay eco. */
long leerDistanciaTapaCmUna() {
  digitalWrite(tapaTrigPin, LOW);
  delayMicroseconds(2);
  digitalWrite(tapaTrigPin, HIGH);
  delayMicroseconds(10);
  digitalWrite(tapaTrigPin, LOW);
  const unsigned long us = pulseIn(tapaEchoPin, HIGH, 12000);
  if (us == 0) return -1;
  return us / 58;
}

/**
 * Lectura filtrada del sensor de tapa.
 * Acumula 3 muestras rotativas y devuelve la mediana de las válidas.
 */
long leerDistanciaTapaCmFiltrada() {
  const long v = leerDistanciaTapaCmUna();
  tapaUsSamples[tapaUsSampleIdx] = v;
  tapaUsSampleIdx = (tapaUsSampleIdx + 1) % 3;

  long valid[3];
  uint8_t n = 0;
  for (uint8_t i = 0; i < 3; i++) {
    if (tapaUsSamples[i] >= TAPA_PROXIMITY_CM_MIN && tapaUsSamples[i] < 350) {
      valid[n++] = tapaUsSamples[i];
    }
  }
  return medianaMuestras(valid, n);
}

/** Una lectura del HC-SR04 de descarga (cm). Retorna -1 si no hay eco. */
long leerDistanciaCmUna() {
  digitalWrite(trigPin, LOW);
  delayMicroseconds(2);
  digitalWrite(trigPin, HIGH);
  delayMicroseconds(10);
  digitalWrite(trigPin, LOW);
  const unsigned long us = pulseIn(echoPin, HIGH, 12000);
  if (us == 0) return -1;
  return us / 58;
}

/**
 * Lectura filtrada del sensor de descarga.
 * Acumula 3 muestras rotativas y devuelve la mediana de las válidas.
 */
long leerDistanciaCmFiltrada() {
  const long v = leerDistanciaCmUna();
  proxUsSamples[proxUsSampleIdx] = v;
  proxUsSampleIdx = (proxUsSampleIdx + 1) % 3;

  long valid[3];
  uint8_t n = 0;
  for (uint8_t i = 0; i < 3; i++) {
    if (proxUsSamples[i] >= PROXIMITY_CM_MIN && proxUsSamples[i] < 350) {
      valid[n++] = proxUsSamples[i];
    }
  }
  return medianaMuestras(valid, n);
}


// =============================================================================
// BLOQUE 17 — PROXIMIDAD (DETECCIÓN AUTOMÁTICA)
// =============================================================================

/**
 * Sensor de tapa (D2/D3): abre la tapa si detecta objeto a ≤ 5 cm.
 * Requiere 3 lecturas consecutivas para evitar falsos positivos.
 */
void serviceProximidadTapa() {
  if (!tapaPuedeAbrir()) {
    tapaProxConfirmCount = 0;
    tapaProxCerca = false;
    return;
  }

  const unsigned long ahora = millis();
  if (ahora - ultimaLecturaTapaProx < TAPA_PROX_READ_MS) return;
  ultimaLecturaTapaProx = ahora;

  const long cm = leerDistanciaTapaCmFiltrada();
  const bool cerca = cm >= TAPA_PROXIMITY_CM_MIN && cm <= TAPA_PROXIMITY_CM;

  if (cerca) {
    tapaProxConfirmCount++;
    if (tapaProxConfirmCount >= TAPA_PROX_CONFIRM_NEEDED && !tapaProxCerca) {
      Serial.print(F("[TAPA-SENSOR] "));
      Serial.print(cm);
      Serial.println(F(" cm"));
      tapaProxConfirmCount = 0;
      tapaProxCerca = true;
      tapaAbrir();
    }
  } else {
    tapaProxConfirmCount = 0;
    tapaProxCerca = false;
  }
}

/**
 * Sensor de descarga (D6/D7): inicia descarga si detecta objeto a ≤ 5 cm.
 * Solo activo en REPOSO y tras el período de enfriamiento.
 */
void serviceProximidad() {
  if (modo != MODO_REPOSO) return;
  if (millis() < proximidadListaEn) return;

  const unsigned long ahora = millis();
  if (ahora - ultimaLecturaProx < PROXIMITY_READ_MS) return;
  ultimaLecturaProx = ahora;

  const long cm = leerDistanciaCmFiltrada();
  const bool cerca = cm >= PROXIMITY_CM_MIN && cm <= PROXIMITY_CM;

  if (cerca) {
    proxConfirmCount++;
    if (proxConfirmCount >= PROXIMITY_CONFIRM_NEEDED && !manoCerca) {
      Serial.print(F("[SENSOR] "));
      Serial.println(cm);
      proxConfirmCount = 0;
      manoCerca = true;
      iniciarDescarga("sensor");
    }
  } else {
    proxConfirmCount = 0;
    manoCerca = false;
  }
}


// =============================================================================
// BLOQUE 18 — WATCHDOG GLOBAL DE CICLOS
// =============================================================================

/**
 * Garantiza que ningún modo quede inconsistente o colgado.
 * · REPOSO: relé OFF, sub-FSM limpia, UART vivo.
 * · DESCARGA: el tope de ciclo está en serviceDescargaFsm.
 * · RECARGA: el tope de 5 min está en evaluarRecarga; aquí refuerza relé ON.
 * · Válvula: fuerza fin si el flag de movimiento supera el tope.
 */
void serviceWatchdogCiclos() {
  const unsigned long ahora = millis();

  // Movimiento de válvula colgado aunque no estemos en descarga.
  if (valvulaMovimientoActivo &&
      ahora - valvulaMovimientoInicio >= VALVULA_MOV_TIMEOUT_MS) {
    forzarFinValvulaMovimiento("watchdog");
  }

  if (modo == MODO_REPOSO) {
    // Relé nunca debe quedar ON en reposo.
    setRelay(false);

    if (descargaSub != DSC_IDLE) {
      Serial.println(F("[WD] reposo con descargaSub!=IDLE — reset"));
      descargaSub = DSC_IDLE;
      descargaFlushStartEnviado = false;
    }

    // Buzzer huérfano en reposo.
    if (buzzerModo != BUZZER_OFF &&
        ahora - buzzerSecuenciaInicio >= DESCARGA_PITIDOS_MAX_MS) {
      setBuzzer(false);
      buzzerModo = BUZZER_OFF;
      buzzerEncendido = false;
    }
  } else if (modo == MODO_RECARGA) {
    // Si se apagó el relé por error, reactivar durante la recarga.
    // (setRelay es barato; asegura bomba activa hasta OK/timeout)
    digitalWrite(relayPin, RELAY_ON);

    if (ahora - faseInicio >= RECARGA_CICLO_MAX_MS) {
      // Doble seguro por si evaluarRecarga no corrió.
      finalizarRecargaTimeout();
    }
  } else if (modo == MODO_DESCARGA) {
    // Relé OFF durante descarga (seguridad).
    setRelay(false);
  }

  // Latido de depuración cada 10 s.
  if (ahora - ultimoWatchdogLog >= WATCHDOG_LOG_MS) {
    ultimoWatchdogLog = ahora;
    Serial.print(F("[WD] modo="));
    if (modo == MODO_REPOSO) Serial.print(F("REPOSO"));
    else if (modo == MODO_DESCARGA) Serial.print(F("DESCARGA"));
    else Serial.print(F("RECARGA"));
    Serial.print(F(" dsc="));
    Serial.print((int)descargaSub);
    Serial.print(F(" valvMov="));
    Serial.print(valvulaMovimientoActivo ? 1 : 0);
    Serial.print(F(" esp="));
    Serial.println(espLinkActivo ? 1 : 0);
  }
}


// =============================================================================
// BLOQUE 19 — SETUP Y LOOP PRINCIPAL
// =============================================================================

void setup() {
  // --- Configuración de pines ---
  pinMode(buzzerPin, OUTPUT);
  digitalWrite(buzzerPin, LOW);

  pinMode(dataPin, OUTPUT);
  pinMode(clockPin, OUTPUT);
  pinMode(latchPin, OUTPUT);
  pinMode(trigPin, OUTPUT);
  pinMode(echoPin, INPUT);
  pinMode(tapaTrigPin, OUTPUT);
  pinMode(tapaEchoPin, INPUT);
  pinMode(relayPin, OUTPUT);

  // A3 como salida digital (pin 17) antes de cualquier attach de servo
  tapaPinSalidaDigital();

  // --- Serial de depuración y enlace ESP32 ---
  Serial.begin(115200);
  espLinkReanudar();
  delay(200);
  vaciarEspLink();

  // --- Posición inicial de actuadores (bloqueante solo al arranque) ---
  valvulaServoMoverBloqueante(VALVULA_GRADOS_CERRADO);
  tapaServoInicializar();

  // --- Información de arranque en Monitor Serial ---
  Serial.println(F("=== inodoro_smart UNO ==="));
  Serial.println(F("FW UNO-GR-33"));
  Serial.println(F("Watchdogs: descarga/valvula/buzzer/UART → siempre a REPOSO"));
  Serial.print(F("Buzzer="));
  Serial.println(BUZZER_ENABLED ? F("ON") : F("OFF"));
  Serial.print(F("Descarga="));
  Serial.print(FASE_DESCARGA_MS / 1000);
  Serial.print(F("s Recarga: hasta ADC>"));
  Serial.print(NIVEL_AGUA_OK);
  Serial.print(F(" (max "));
  Serial.print(RECARGA_MAX_MS / 60000);
  Serial.println(F(" min)"));
  Serial.print(F("Valvula 11kg D5: cerrado="));
  Serial.print(VALVULA_GRADOS_CERRADO);
  Serial.print(F("° abierto="));
  Serial.print(VALVULA_GRADOS_ABIERTO);
  Serial.print(F("° move="));
  Serial.print(VALVULA_MOVE_MS);
  Serial.println(F("ms HOLD cooperativo"));
  Serial.print(F("Tapa: pin digital "));
  Serial.print(TAPA_SERVO_DIGITAL_PIN);
  Serial.print(F(" = A3 analógico | cerrada="));
  Serial.print(TAPA_GRADOS_CERRADO);
  Serial.print(F("° abierta="));
  Serial.print(TAPA_GRADOS_ABIERTO);
  Serial.println(F("° | write(grados)"));
  Serial.print(F("Sensor tapa Trig D2 / Echo D3 @ "));
  Serial.print(TAPA_PROXIMITY_CM);
  Serial.println(F(" cm (cierra solo en descarga)"));

  entrarReposo(false);
  Serial.println(F("Listo — LCD via ESP32"));
}

/**
 * Loop cooperativo: cada servicio se ejecuta en cada ciclo.
 * El orden prioriza movimientos y comunicación antes que sensores.
 * El watchdog al final fuerza salida de estados inconsistentes.
 */
void loop() {
  serviceValvulaMovimiento();
  serviceBuzzer();
  serviceValvulaHold();
  serviceEsp();
  serviceDescargaFsm();
  serviceRecarga();
  serviceProximidad();
  serviceProximidadTapa();
  serviceWatchdogCiclos();
  recuperarEnlace();
}
