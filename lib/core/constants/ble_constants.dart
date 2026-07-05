import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Protocolo BLE del ESP32 inodoro_smart.
class BleConstants {
  BleConstants._();

  static const deviceNames = ['INODORO_SMART', 'INODORO', 'inodoro_smart'];

  static bool isInodoroName(String name) {
    if (name.isEmpty) return false;
    final upper = name.toUpperCase();
    return upper.contains('INODORO');
  }

  static bool matchesScanResult(String name, List<Guid> serviceUuids) {
    if (isInodoroName(name)) return true;
    return serviceUuids.any((g) => g == Guid(serviceUuid));
  }

  static const serviceUuid = '1234';
  static const cmdCharUuid = '5678';
  static const statusCharUuid = '9012';
  static const eventCharUuid = '9013';
  static const bleResetWifi = 'RESET';
  static const wifiStatusCmd = 'WIFI_STATUS';

  static String wifiPayload(String ssid, String password) =>
      'WIFI|$ssid|$password';
}
