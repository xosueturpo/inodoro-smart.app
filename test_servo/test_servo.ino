/*
 * TEST SERVO + ULTRASONIDO — inodoro_smart
 *
 * Servo D5: subida LENTA a 60° si mano ~5 cm | baja tras 3 s sin mano
 * HC-SR04: Trig D8 | Echo D9
 *
 * Monitor Serie: 115200 baud
 */

#include <Servo.h>

const int SERVO_PIN = 5;
const int TRIG_PIN = 8;
const int ECHO_PIN = 9;

const int GRADOS_CERRADO = 0;
const int GRADOS_ABIERTO = 85;

const int PROXIMITY_CM = 5;
const int PROXIMITY_CM_MIN = 2;
const uint8_t PROX_CONFIRM_NEEDED = 3;
const unsigned long LECTURA_MS = 120;
const unsigned long SUBIDA_PASO_MS = 18;
const unsigned long ESPERA_ANTES_BAJAR_MS = 3000;
const unsigned long BAJADA_PASO_MS = 12;

enum EstadoServo {
  EST_REPOSO,
  EST_SUBIENDO,
  EST_ABIERTO,
  EST_ESPERA_BAJAR,
  EST_BAJANDO,
};

Servo valvula;
EstadoServo estado = EST_REPOSO;
bool manoCerca = false;
uint8_t proxConfirmCount = 0;
int gradosActual = GRADOS_CERRADO;
unsigned long ultimaLectura = 0;
unsigned long ultimoPasoServo = 0;
unsigned long tiempoManoFuera = 0;

long leerDistanciaCm() {
  digitalWrite(TRIG_PIN, LOW);
  delayMicroseconds(2);
  digitalWrite(TRIG_PIN, HIGH);
  delayMicroseconds(10);
  digitalWrite(TRIG_PIN, LOW);
  const unsigned long us = pulseIn(ECHO_PIN, HIGH, 12000);
  if (us == 0) return -1;
  return us / 58;
}

long mediana3(long a, long b, long c) {
  if (a > b) { const long t = a; a = b; b = t; }
  if (b > c) { const long t = b; b = c; c = t; }
  if (a > b) { const long t = a; a = b; b = t; }
  return b;
}

long leerDistanciaFiltrada() {
  long vals[3];
  uint8_t n = 0;
  for (uint8_t i = 0; i < 3; i++) {
    const long v = leerDistanciaCm();
    if (v >= PROXIMITY_CM_MIN && v < 350) vals[n++] = v;
    if (i < 2) delay(5);
  }
  if (n == 0) return -1;
  if (n == 1) return vals[0];
  if (n == 2) return (vals[0] + vals[1]) / 2;
  return mediana3(vals[0], vals[1], vals[2]);
}

void escribirServo(int grados) {
  grados = constrain(grados, GRADOS_CERRADO, GRADOS_ABIERTO);
  if (!valvula.attached()) {
    valvula.attach(SERVO_PIN);
    delay(30);
  }
  valvula.write(grados);
  gradosActual = grados;
}

void iniciarSubida() {
  estado = EST_SUBIENDO;
  ultimoPasoServo = millis();
  Serial.println(F("SUBIENDO suave → 60°"));
}

void iniciarEsperaBajar() {
  estado = EST_ESPERA_BAJAR;
  tiempoManoFuera = millis();
  Serial.println(F("Mano fuera — espera 3 s antes de bajar"));
}

void iniciarBajada() {
  estado = EST_BAJANDO;
  ultimoPasoServo = millis();
  Serial.println(F("BAJANDO → 0°"));
}

void serviceServo(unsigned long ahora) {
  switch (estado) {
    case EST_SUBIENDO:
      if (ahora - ultimoPasoServo >= SUBIDA_PASO_MS) {
        ultimoPasoServo = ahora;
        if (gradosActual < GRADOS_ABIERTO) {
          escribirServo(gradosActual + 1);
        } else {
          estado = EST_ABIERTO;
          Serial.println(F("ABIERTO 60°"));
        }
      }
      break;

    case EST_ESPERA_BAJAR:
      if (manoCerca) {
        estado = EST_ABIERTO;
        Serial.println(F("Mano otra vez — cancela bajada"));
        break;
      }
      if (ahora - tiempoManoFuera >= ESPERA_ANTES_BAJAR_MS) {
        iniciarBajada();
      }
      break;

    case EST_BAJANDO:
      if (ahora - ultimoPasoServo >= BAJADA_PASO_MS) {
        ultimoPasoServo = ahora;
        if (gradosActual > GRADOS_CERRADO) {
          escribirServo(gradosActual - 1);
        } else {
          estado = EST_REPOSO;
          Serial.println(F("REPOSO 0°"));
        }
      }
      break;

    default:
      break;
  }
}

void setup() {
  pinMode(TRIG_PIN, OUTPUT);
  pinMode(ECHO_PIN, INPUT);

  Serial.begin(115200);
  delay(400);

  escribirServo(GRADOS_CERRADO);
  estado = EST_REPOSO;

  Serial.println();
  Serial.println(F("=== TEST SERVO + ULTRASONIDO ==="));
  Serial.println(F("Servo D5 | Trig D8 | Echo D9"));
  Serial.println(F("Subida suave ~1 s a 60° @ 5 cm"));
  Serial.print(F("Baja tras "));
  Serial.print(ESPERA_ANTES_BAJAR_MS / 1000);
  Serial.println(F(" s sin mano"));
  Serial.println(F("----------------------------------------"));
}

void loop() {
  const unsigned long ahora = millis();

  serviceServo(ahora);

  if (ahora - ultimaLectura < LECTURA_MS) return;
  ultimaLectura = ahora;

  const long cm = leerDistanciaFiltrada();
  const bool cerca = cm >= PROXIMITY_CM_MIN && cm <= PROXIMITY_CM;

  if (cerca) {
    proxConfirmCount++;
    if (proxConfirmCount >= PROX_CONFIRM_NEEDED) {
      manoCerca = true;
      if (estado == EST_REPOSO) {
        Serial.print(F("ACTIVO — "));
        Serial.print(cm);
        Serial.println(F(" cm"));
        iniciarSubida();
      }
    }
  } else {
    proxConfirmCount = 0;
    manoCerca = false;
    if (estado == EST_ABIERTO) {
      iniciarEsperaBajar();
    }
  }
}
