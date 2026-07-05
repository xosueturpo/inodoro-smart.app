int SENSOR;

unsigned long ultimaMs = 0;

void setup() {
  Serial.begin(9600);
}

void loop() {
  SENSOR = analogRead(A0);
  Serial.println(SENSOR);
  delay(1000);
}
