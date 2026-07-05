/*
 * TEST PIN A3 — Salida digital en Arduino UNO
 *
 * A3 (header ANALOG IN) = pin digital 17 internamente.
 * NO confundir con D3 (pin digital 3 del header digital).
 *
 * Este sketch NO mueve un servo: alterna 0 V y 5 V cada 2 s.
 * Así el multímetro SÍ puede ver la señal claramente.
 *
 * Conexión multímetro (modo DC V):
 *   Negro (COM) → GND del Arduino
 *   Rojo (V)    → pin A3 (header ANALOG IN)
 *
 * Resultado esperado:
 *   ~0 V durante 2 s  →  ~5 V durante 2 s  →  se repite
 *
 * Monitor Serie: 115200 baud
 */

const uint8_t PIN_A3_DIGITAL = 17;   // A3 analógico = pin digital 17
const unsigned long INTERVALO_MS = 2000;

void setup() {
  Serial.begin(115200);
  pinMode(PIN_A3_DIGITAL, OUTPUT);
  digitalWrite(PIN_A3_DIGITAL, LOW);

  Serial.println();
  Serial.println(F("=== TEST SALIDA DIGITAL A3 ==="));
  Serial.println(F("Pin fisico: A3 (header ANALOG IN)"));
  Serial.print(F("Pin digital interno: "));
  Serial.println(PIN_A3_DIGITAL);
  Serial.println(F("NO usar pin 3 del header digital (ese es D3)"));
  Serial.println();
  Serial.println(F("Multimetro: COM->GND, V->A3"));
  Serial.println(F("Debe alternar 0 V y 5 V cada 2 s"));
  Serial.println(F("----------------------------------------"));
}

void loop() {
  digitalWrite(PIN_A3_DIGITAL, HIGH);
  Serial.println(F("A3 = HIGH  (~5.0 V en multimetro)"));
  delay(INTERVALO_MS);

  digitalWrite(PIN_A3_DIGITAL, LOW);
  Serial.println(F("A3 = LOW   (~0.0 V en multimetro)"));
  delay(INTERVALO_MS);
}
