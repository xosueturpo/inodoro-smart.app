/// Protocolo passthrough Flutter ↔ ESP32 ↔ UNO.
/// El ESP32 solo intercepta: LCD|..., RESET, WIFI_STATUS, WIFI|ssid|pass.
/// Todo lo demás llega al UNO sin modificar.
class DeviceProtocol {
  DeviceProtocol._();

  /// ESP32 escribe en LCD local (acepta espacios: LCD|linea 0|linea 1).
  static String lcd(String line0, String line1) => 'LCD|$line0|$line1';
}
