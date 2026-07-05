/*
 * Solo escaneo I2C — subir al UNO, Serial 9600
 * Copia TODA la salida y enviala.
 * Cableado: SDA=A4, SCL=A5, VCC=5V, GND=GND
 */

#include <Wire.h>

void setup() {
  Serial.begin(9600);
  delay(800);
  Serial.println(F("=== I2C SCANNER ==="));

  Wire.begin();
  delay(200);

  uint8_t count = 0;
  for (uint8_t addr = 1; addr < 127; addr++) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      Serial.print(F("Dispositivo en 0x"));
      if (addr < 16) Serial.print('0');
      Serial.println(addr, HEX);
      count++;
    }
  }

  if (count == 0) {
    Serial.println(F("NINGUNO — revisa SDA A4, SCL A5, 5V, GND"));
  } else {
    Serial.print(F("Total: "));
    Serial.println(count);
    Serial.println(F("0x27 o 0x3F = LCD tipico PCF8574"));
    Serial.println(F("otra direccion = puede ser otro chip"));
  }
}

void loop() {
  delay(10000);
}
