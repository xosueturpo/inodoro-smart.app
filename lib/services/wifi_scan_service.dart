import 'dart:io';

import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';

class WifiNetworkResult {
  const WifiNetworkResult({
    required this.ssid,
    required this.level,
    required this.secure,
  });

  final String ssid;
  final int level;
  final bool secure;

  int get signalBars {
    if (level >= -50) return 3;
    if (level >= -70) return 2;
    return 1;
  }
}

class WifiScanService {
  Future<bool> ensurePermissions() async {
    if (Platform.isAndroid) {
      final location = await Permission.locationWhenInUse.request();
      await Permission.nearbyWifiDevices.request();
      return location.isGranted;
    }
    if (Platform.isIOS) {
      final location = await Permission.locationWhenInUse.request();
      return location.isGranted;
    }
    return false;
  }

  Future<List<WifiNetworkResult>> scanNetworks() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw Exception('Buscar WiFi solo está disponible en Android e iOS');
    }

    final permitted = await ensurePermissions();
    if (!permitted) {
      throw Exception(
        'Activa el permiso de ubicación para buscar redes WiFi cercanas',
      );
    }

    final canStart = await WiFiScan.instance.canStartScan(askPermissions: false);
    if (canStart != CanStartScan.yes) {
      throw Exception(_scanBlockedMessage(canStart));
    }

    final started = await WiFiScan.instance.startScan();
    if (!started) {
      throw Exception('No se pudo iniciar el escaneo WiFi');
    }

    await Future<void>.delayed(const Duration(seconds: 2));

    final canRead = await WiFiScan.instance.canGetScannedResults(
      askPermissions: false,
    );
    if (canRead != CanGetScannedResults.yes) {
      throw Exception('No se pudieron leer las redes WiFi');
    }

    final accessPoints = await WiFiScan.instance.getScannedResults();
    final bySsid = <String, WifiNetworkResult>{};

    for (final ap in accessPoints) {
      final ssid = ap.ssid.trim();
      if (ssid.isEmpty) continue;

      final caps = ap.capabilities.toUpperCase();
      final secure = caps.contains('WPA') ||
          caps.contains('WEP') ||
          caps.contains('PSK') ||
          caps.contains('EAP');

      final entry = WifiNetworkResult(
        ssid: ssid,
        level: ap.level,
        secure: secure,
      );

      final existing = bySsid[ssid];
      if (existing == null || entry.level > existing.level) {
        bySsid[ssid] = entry;
      }
    }

    final networks = bySsid.values.toList()
      ..sort((a, b) => b.level.compareTo(a.level));
    return networks;
  }

  String _scanBlockedMessage(CanStartScan reason) {
    return switch (reason) {
      CanStartScan.notSupported => 'Este dispositivo no permite escanear WiFi',
      CanStartScan.noLocationPermissionRequired ||
      CanStartScan.noLocationPermissionDenied ||
      CanStartScan.noLocationPermissionUpgradeAccuracy =>
        'Se necesita permiso de ubicación para buscar redes',
      CanStartScan.noLocationServiceDisabled =>
        'Activa la ubicación del teléfono para buscar redes WiFi',
      CanStartScan.failed => 'No se pudo iniciar el escaneo WiFi',
      CanStartScan.yes => 'Escaneo WiFi no disponible',
    };
  }
}
