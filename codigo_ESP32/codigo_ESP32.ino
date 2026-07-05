#include <WiFi.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>

// ================= UART → Arduino UNO =================
// Serial2 = UART2 (pines fijos, no tocar)
//
//   Placa ESP32  TX2 (pin 17) ---> Arduino D8 (RX)
//   Placa ESP32  RX2 (pin 16) <--- Arduino D9 (TX)
//   GND ESP32 ---------------- GND Arduino  (OBLIGATORIO)
//
#define PIN_UART_RX 16  // RX2 en la placa
#define PIN_UART_TX 17  // TX2 en la placa
#define UART_BAUD   9600

// LCD I2C — en la placa: D21 = SDA, D22 = SCL (Arduino IDE: pin 21 y 22)
#define PIN_LCD_SDA 21  // D21
#define PIN_LCD_SCL 22  // D22
#define LCD_ADDR    0x27

LiquidCrystal_I2C lcd(LCD_ADDR, 16, 2);
bool lcdReady = false;

// ================= Identidad =================
static const char *BLE_NAME   = "INODORO_SMART";
static const char *MDNS_NAME  = "inodoro_smart";
static const char *BLE_SVC    = "1234";
static const char *BLE_CHAR   = "5678";
static const char *BLE_STATUS = "9012";
static const char *BLE_EVENT  = "9013";

// ================= Estado =================
Preferences prefs;
WebServer http(80);

String wifiSsid;
String wifiPass;
bool wifiConfigured = false;
bool httpReady = false;

uint32_t lastUnoEventSeq = 0;
String lastUnoEvent = "";

enum WifiPhase { WIFI_IDLE, WIFI_CONNECTING, WIFI_CONNECTED, WIFI_FAILED };
WifiPhase wifiPhase = WIFI_IDLE;
unsigned long wifiPhaseStarted = 0;
unsigned long lastWifiWatchdog = 0;
unsigned long lastBleAdvRestart = 0;

BLEServer *bleServer = nullptr;
BLECharacteristic *cmdChar = nullptr;
BLECharacteristic *statusChar = nullptr;
BLECharacteristic *eventChar = nullptr;
bool bleClientConnected = false;

String buildWifiStatusPayload() {
  if (WiFi.status() == WL_CONNECTED) {
    return "CONNECTED|" + wifiSsid + "|" + WiFi.localIP().toString();
  }
  if (wifiPhase == WIFI_CONNECTING) {
    return "CONNECTING|" + wifiSsid + "|";
  }
  if (wifiPhase == WIFI_FAILED) {
    return "FAILED|" + wifiSsid + "|";
  }
  if (wifiConfigured && wifiSsid.length() > 0) {
    return "CONFIGURED|" + wifiSsid + "|";
  }
  return "NONE||";
}

void publishWifiStatus() {
  if (!statusChar) return;
  const String payload = buildWifiStatusPayload();
  statusChar->setValue(payload.c_str());
  statusChar->notify();
}

void trimIncoming(String &cmd) {
  cmd.trim();
  cmd.replace("\r", "");
}

bool isLcdCommand(const String &raw) {
  String line = raw;
  trimIncoming(line);
  if (line.length() < 4) return false;
  if (line.charAt(3) != '|') return false;
  String head = line.substring(0, 3);
  head.toUpperCase();
  return head == "LCD";
}

void showLcd(const String &line0, const String &line1) {
  if (!lcdReady) return;
  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print(line0.substring(0, 16));
  lcd.setCursor(0, 1);
  lcd.print(line1.substring(0, 16));
}

bool handleLcdCommand(const String &raw) {
  if (!isLcdCommand(raw)) return false;

  String line = raw;
  trimIncoming(line);

  const int sep2 = line.indexOf('|', 4);
  String l0;
  String l1;
  if (sep2 < 0) {
    l0 = line.substring(4);
    l1 = "";
  } else {
    l0 = line.substring(4, sep2);
    l1 = line.substring(sep2 + 1);
  }
  l0.trim();
  l1.trim();

  Serial.print(F("[LCD] \""));
  Serial.print(l0);
  Serial.print(F("\" | \""));
  Serial.print(l1);
  Serial.println(F("\""));
  showLcd(l0, l1);
  return true;
}

void forwardUnoLineToApp(const String &line) {
  String payload = line;
  trimIncoming(payload);
  if (payload.length() == 0) return;

  String appPayload = payload;
  String upper = payload;
  upper.toUpperCase();
  if (upper.startsWith("EVT:")) {
    appPayload = payload.substring(4);
    appPayload.trim();
  }
  if (appPayload.length() == 0) return;

  lastUnoEventSeq++;
  lastUnoEvent = appPayload;

  Serial.print(F("[PUENTE→APP] "));
  Serial.println(appPayload);

  if (eventChar) {
    eventChar->setValue(appPayload.c_str());
    eventChar->notify();
  }
}

void handleLineFromUno(const String &line) {
  if (handleLcdCommand(line)) return;
  forwardUnoLineToApp(line);
}

// ======================================================
// UART — debug + envío
// ======================================================
void logUartTx(const String &cmd) {
  Serial.print(F("[UART→UNO] TX: \""));
  Serial.print(cmd);
  Serial.print(F("\" len="));
  Serial.print(cmd.length());
  Serial.print(F(" bytes | ASCII:"));
  for (unsigned i = 0; i < cmd.length(); i++) {
    Serial.print(' ');
    Serial.print((int)cmd[i]);
  }
  Serial.println();
}

void pollUartFromArduino() {
  static String rxLine;
  static unsigned long ultimoByteRx = 0;

  while (Serial2.available() > 0) {
    ultimoByteRx = millis();
    const char c = Serial2.read();

    if (c == '\n') {
      rxLine.trim();
      rxLine.replace("\r", "");
      if (rxLine.length() > 0) {
        Serial.print(F("[UART←UNO] "));
        Serial.println(rxLine);
        handleLineFromUno(rxLine);
      }
      rxLine = "";
    } else if (c != '\r' && c >= 32 && c <= 126 && rxLine.length() < 200) {
      rxLine += c;
    }
  }

  // Línea incompleta por ruido UART → descartar para no bloquear el LCD.
  if (rxLine.length() > 0 && millis() - ultimoByteRx > 250) {
    Serial.print(F("[UART←UNO] DESCARTE: "));
    Serial.println(rxLine);
    rxLine = "";
  }
}

void sendToArduino(const String &cmd) {
  String c = cmd;
  trimIncoming(c);
  if (c.length() == 0) return;

  logUartTx(c);
  Serial2.println(c);
  Serial2.flush();
}

bool isWifiSetup(const String &raw) {
  String line = raw;
  trimIncoming(line);
  String upper = line;
  upper.toUpperCase();
  if (!upper.startsWith("WIFI|")) return false;
  const int sep2 = line.indexOf('|', 5);
  return sep2 > 5;
}

void startWifiConnect();

void processCommand(const String &raw, const char *source) {
  String trimmed = raw;
  trimIncoming(trimmed);
  if (trimmed.length() == 0) return;

  Serial.print(F("[RX "));
  Serial.print(source);
  Serial.print(F("] \""));
  Serial.print(trimmed);
  Serial.println(F("\""));

  if (handleLcdCommand(trimmed)) return;

  String upper = trimmed;
  upper.toUpperCase();

  // Solo estos tres los interpreta el ESP32. Todo lo demás → UNO tal cual llega.
  if (upper == "RESET") {
    Serial.println(F("[ACCION] RESET WiFi (ESP32)"));
    wifiSsid = "";
    wifiPass = "";
    wifiConfigured = false;
    httpReady = false;
    wifiPhase = WIFI_IDLE;
    prefs.remove("ssid");
    prefs.remove("pass");
    WiFi.disconnect(true, true);
    delay(300);
    publishWifiStatus();
    restartBleAdvertising();
    return;
  }

  if (upper == "WIFI_STATUS") {
    publishWifiStatus();
    return;
  }

  if (isWifiSetup(trimmed)) {
    const int sep1 = trimmed.indexOf('|');
    const int sep2 = trimmed.indexOf('|', sep1 + 1);
    wifiSsid = trimmed.substring(sep1 + 1, sep2);
    wifiPass = trimmed.substring(sep2 + 1);
    wifiSsid.trim();
    wifiPass.trim();
    wifiConfigured = true;
    prefs.putString("ssid", wifiSsid);
    prefs.putString("pass", wifiPass);
    Serial.print(F("[ACCION] WiFi SSID="));
    Serial.println(wifiSsid);
    publishWifiStatus();
    startWifiConnect();
    return;
  }

  // Passthrough libre — mismo texto que envió Flutter (sin toUpperCase)
  Serial.print(F("[PASSTHROUGH→UNO] "));
  Serial.println(trimmed);
  sendToArduino(trimmed);
}

// ======================================================
// HTTP
// ======================================================
void handlePing() {
  http.send(200, "text/plain", "OK");
}

void handleEvt() {
  const String body = String(lastUnoEventSeq) + "|" + lastUnoEvent;
  http.send(200, "text/plain", body);
}

void handleCmd() {
  if (!http.hasArg("plain")) {
    Serial.println(F("[RX HTTP] sin body"));
    http.send(400, "text/plain", "NO BODY");
    return;
  }
  processCommand(http.arg("plain"), "HTTP/Flutter");
  http.send(200, "text/plain", "OK");
}

void setupHttp() {
  if (httpReady) return;
  http.on("/ping", HTTP_GET, handlePing);
  http.on("/evt", HTTP_GET, handleEvt);
  http.on("/cmd", HTTP_POST, handleCmd);
  http.begin();
  httpReady = true;
  Serial.println(F("HTTP listo: GET /ping  GET /evt  POST /cmd"));
}

// ======================================================
// WiFi (no bloqueante)
// ======================================================
void startWifiConnect() {
  if (wifiSsid.length() == 0) return;

  WiFi.mode(WIFI_STA);
  WiFi.disconnect(true, true);
  delay(100);
  WiFi.begin(wifiSsid.c_str(), wifiPass.c_str());

  wifiPhase = WIFI_CONNECTING;
  wifiPhaseStarted = millis();
  httpReady = false;

  Serial.print(F("WiFi conectando a "));
  Serial.println(wifiSsid);
}

void onWifiConnected() {
  wifiPhase = WIFI_CONNECTED;
  Serial.println(F("WiFi OK"));
  Serial.println(WiFi.localIP());
  publishWifiStatus();

  if (!MDNS.begin(MDNS_NAME)) {
    Serial.println(F("mDNS fallo"));
  } else {
    Serial.print(F("mDNS: "));
    Serial.print(MDNS_NAME);
    Serial.println(F(".local"));
  }

  setupHttp();
}

void serviceWifi() {
  if (!wifiConfigured || wifiSsid.length() == 0) return;

  if (wifiPhase == WIFI_IDLE) {
    startWifiConnect();
    return;
  }

  if (wifiPhase == WIFI_CONNECTING) {
    if (WiFi.status() == WL_CONNECTED) {
      onWifiConnected();
      return;
    }
    if (millis() - wifiPhaseStarted > 15000) {
      Serial.println(F("WiFi timeout"));
      wifiPhase = WIFI_FAILED;
      wifiPhaseStarted = millis();
      publishWifiStatus();
    }
    return;
  }

  if (wifiPhase == WIFI_FAILED) {
    if (millis() - wifiPhaseStarted > 8000) {
      startWifiConnect();
    }
    return;
  }

  if (millis() - lastWifiWatchdog < 5000) return;
  lastWifiWatchdog = millis();

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println(F("WiFi perdido → reconectar"));
    httpReady = false;
    wifiPhase = WIFI_IDLE;
  }
}

// ======================================================
// BLE
// ======================================================
class CmdCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) override {
    String value = pCharacteristic->getValue();
    processCommand(value, "BLE/Flutter");
  }
};

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer *pServer) override {
    bleClientConnected = true;
    Serial.println(F("BLE conectado"));
    publishWifiStatus();
  }

  void onDisconnect(BLEServer *pServer) override {
    bleClientConnected = false;
    Serial.println(F("BLE desconectado"));
    restartBleAdvertising();
  }
};

void restartBleAdvertising() {
  lastBleAdvRestart = millis();
  BLEDevice::startAdvertising();
  Serial.println(F("BLE advertising activo"));
}

void startBle() {
  BLEDevice::init(BLE_NAME);
  bleServer = BLEDevice::createServer();
  bleServer->setCallbacks(new ServerCallbacks());

  BLEService *service = bleServer->createService(BLE_SVC);
  cmdChar = service->createCharacteristic(
    BLE_CHAR,
    BLECharacteristic::PROPERTY_WRITE
  );
  cmdChar->setCallbacks(new CmdCallbacks());

  statusChar = service->createCharacteristic(
    BLE_STATUS,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  statusChar->addDescriptor(new BLE2902());
  statusChar->setValue(buildWifiStatusPayload().c_str());

  eventChar = service->createCharacteristic(
    BLE_EVENT,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  eventChar->addDescriptor(new BLE2902());
  eventChar->setValue("");

  service->start();

  BLEAdvertising *adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(BLE_SVC);
  adv->setScanResponse(true);
  adv->start();

  Serial.println(F("BLE listo: INODORO_SMART"));
}

// ======================================================
// Setup / Loop
// ======================================================
void setup() {
  Serial.begin(115200);
  delay(500);

  Serial.println();
  Serial.println(F("=== INODORO_SMART ESP32 ==="));
  Serial.printf("UART2: RX2(pin%d)  TX2(pin%d)  @ %d baud\n", PIN_UART_RX, PIN_UART_TX, UART_BAUD);
  Serial.println(F("Cableado: TX2→UNO D8(RX)  RX2←UNO D9(TX)  GND↔GND"));

  Serial2.begin(UART_BAUD, SERIAL_8N1, PIN_UART_RX, PIN_UART_TX);
  delay(200);

  Wire.begin(PIN_LCD_SDA, PIN_LCD_SCL);
  lcd.init();
  lcd.backlight();
  lcdReady = true;
  showLcd("inodoro_smart", "ESP32 OK");
  Serial.println(F("LCD I2C @ 0x27 — SDA=D21  SCL=D22"));

  prefs.begin("inodoro", false);
  wifiSsid = prefs.getString("ssid", "");
  wifiPass = prefs.getString("pass", "");
  wifiConfigured = wifiSsid.length() > 0;

  startBle();

  if (wifiConfigured) {
    startWifiConnect();
  }

  Serial.println(F("=== ESP32 listo — monitor 115200 ==="));
}

void loop() {
  pollUartFromArduino();
  serviceWifi();

  if (WiFi.status() == WL_CONNECTED && httpReady) {
    http.handleClient();
  }

  if (!bleClientConnected && millis() - lastBleAdvRestart > 30000) {
    restartBleAdvertising();
  }
}
