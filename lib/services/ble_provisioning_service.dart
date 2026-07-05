import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/constants/ble_constants.dart';
import '../models/device_models.dart';

class BleScanResult {
  BleScanResult({required this.device, required this.name, required this.rssi});

  final BluetoothDevice device;
  final String name;
  final int rssi;
}

class BleProvisioningService {
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _connectionSub;
  StreamSubscription<List<int>>? _wifiStatusSub;
  StreamSubscription<List<int>>? _unoEventSub;

  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _cmdChar;
  BluetoothCharacteristic? _statusChar;
  BluetoothCharacteristic? _eventChar;
  bool _linkReady = false;
  bool _userDisconnect = false;
  bool _connectInProgress = false;
  int _connectionEpoch = 0;
  Completer<void>? _scanLoopDone;
  Future<void>? _connectQueue;

  final _disconnectedController = StreamController<void>.broadcast();
  final _wifiStatusController = StreamController<EspWifiStatus>.broadcast();
  final _unoEventController = StreamController<UnoEvent>.broadcast();

  Stream<void> get onDisconnected => _disconnectedController.stream;
  Stream<EspWifiStatus> get onWifiStatus => _wifiStatusController.stream;
  Stream<UnoEvent> get onUnoEvent => _unoEventController.stream;

  bool get isConnected => _linkReady && _connectedDevice != null && _cmdChar != null;

  BluetoothDevice? get connectedDevice => _connectedDevice;

  Future<bool> ensurePermissions() async {
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
      return statuses.values.every((s) => s.isGranted);
    }
    if (Platform.isIOS) {
      final bt = await Permission.bluetooth.request();
      final loc = await Permission.locationWhenInUse.request();
      return bt.isGranted && loc.isGranted;
    }
    return true;
  }

  Future<bool> isBluetoothOn() async {
    final state = await FlutterBluePlus.adapterState.first;
    return state == BluetoothAdapterState.on;
  }

  Future<void> waitScanIdle({Duration timeout = const Duration(seconds: 3)}) async {
    final done = _scanLoopDone;
    if (done == null) return;
    try {
      await done.future.timeout(timeout);
    } catch (_) {}
  }

  /// Solo para escaneo — no usar durante sesión activa.
  Future<void> prepareForScan() async {
    await stopScan();
    if (_connectInProgress || _linkReady) return;

    _connectionEpoch++;
    await _connectionSub?.cancel();
    _connectionSub = null;
    _connectedDevice = null;
    _cmdChar = null;
    _statusChar = null;
    _eventChar = null;
    _linkReady = false;

    for (final d in FlutterBluePlus.connectedDevices) {
      try {
        if (d.isConnected) await d.disconnect(queue: false);
      } catch (_) {}
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<void> scanContinuously({
    required void Function(List<BleScanResult> results) onResults,
    required bool Function() shouldContinue,
    Duration passTimeout = const Duration(seconds: 15),
  }) async {
    _scanLoopDone = Completer<void>();
    try {
      final ok = await ensurePermissions();
      if (!ok) throw Exception('Permisos Bluetooth denegados');

      if (!await isBluetoothOn()) {
        if (Platform.isAndroid) {
          try {
            await FlutterBluePlus.turnOn();
          } catch (_) {}
        }
        if (!await isBluetoothOn()) {
          throw Exception('Activa Bluetooth para continuar');
        }
      }

      var prepared = false;
      while (shouldContinue()) {
        if (!prepared) {
          await prepareForScan();
          prepared = true;
        }

        final found = <String, BleScanResult>{};
        try {
          await FlutterBluePlus.startScan(
            timeout: passTimeout,
            androidScanMode: AndroidScanMode.lowLatency,
            continuousUpdates: true,
            removeIfGone: const Duration(seconds: 8),
          );

          _scanSub = FlutterBluePlus.scanResults.listen((results) {
            for (final r in results) {
              final adv = r.advertisementData;
              final name = r.device.platformName.isNotEmpty
                  ? r.device.platformName
                  : adv.advName;
              if (!BleConstants.matchesScanResult(name, adv.serviceUuids)) continue;

              found[r.device.remoteId.str] = BleScanResult(
                device: r.device,
                name: name.isNotEmpty ? name : 'INODORO_SMART',
                rssi: r.rssi,
              );
            }
            onResults(found.values.toList()..sort((a, b) => b.rssi.compareTo(a.rssi)));
          });

          final deadline = DateTime.now().add(passTimeout);
          while (shouldContinue() && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 400));
          }
        } finally {
          await stopScan();
        }
        if (!shouldContinue()) break;
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
    } finally {
      if (_scanLoopDone != null && !_scanLoopDone!.isCompleted) {
        _scanLoopDone!.complete();
      }
    }
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    if (FlutterBluePlus.isScanningNow) {
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
  }

  Future<void> connectFromId(String deviceId) async {
    await connect(BluetoothDevice.fromId(deviceId));
  }

  /// Conexión serializada — una a la vez, sin limpieza agresiva en reconexión.
  Future<void> connect(BluetoothDevice device) async {
    final previous = _connectQueue;
    final gate = Completer<void>();
    _connectQueue = gate.future;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {}
    }

    try {
      await _connectOnce(device);
    } finally {
      gate.complete();
      if (identical(_connectQueue, gate.future)) {
        _connectQueue = null;
      }
    }
  }

  Future<void> _connectOnce(BluetoothDevice device) async {
    await stopScan();
    await waitScanIdle();

    final targetId = device.remoteId.str;
    final target = BluetoothDevice.fromId(targetId);

    if (_linkReady &&
        _connectedDevice?.remoteId.str == targetId &&
        _cmdChar != null &&
        target.isConnected) {
      return;
    }

    _connectInProgress = true;
    _userDisconnect = false;
    final epoch = ++_connectionEpoch;

    try {
      await _connectionSub?.cancel();
      _connectionSub = null;

      if (target.isConnected) {
        _connectedDevice = target;
        await _discoverCharacteristic();
        if (_cmdChar != null) {
          _linkReady = true;
          _attachDisconnectListener(target, epoch);
          return;
        }
        try {
          await target.disconnect(queue: false);
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }

      _connectedDevice = target;
      _cmdChar = null;
      _linkReady = false;
      _attachDisconnectListener(target, epoch);

      await target.connect(
        autoConnect: false,
        timeout: const Duration(seconds: 20),
      );

      await target.connectionState
          .where((s) => s == BluetoothConnectionState.connected)
          .first
          .timeout(const Duration(seconds: 20));

      await Future<void>.delayed(const Duration(milliseconds: 500));

      if (epoch != _connectionEpoch) {
        throw Exception('Conexión cancelada');
      }

      await _discoverCharacteristic(retry: true);

      if (_cmdChar == null) {
        throw Exception('Characteristic 5678 no encontrada — ¿firmware INODORO_SMART?');
      }

      await _setupWifiStatus();
      await _setupUnoEvents();

      _linkReady = true;
    } catch (e) {
      _linkReady = false;
      _cmdChar = null;
      _statusChar = null;
      _eventChar = null;
      await _wifiStatusSub?.cancel();
      _wifiStatusSub = null;
      await _unoEventSub?.cancel();
      _unoEventSub = null;
      if (epoch == _connectionEpoch && !_userDisconnect) {
        try {
          if (target.isConnected) await target.disconnect(queue: false);
        } catch (_) {}
      }
      rethrow;
    } finally {
      _connectInProgress = false;
    }
  }

  void _attachDisconnectListener(BluetoothDevice target, int epoch) {
    _connectionSub?.cancel();
    _connectionSub = target.connectionState.listen((state) {
      if (state != BluetoothConnectionState.disconnected) return;
      if (_userDisconnect || _connectInProgress) return;
      if (epoch != _connectionEpoch) return;
      unawaited(_onUnexpectedDisconnect(target, epoch));
    });
  }

  Future<void> _onUnexpectedDisconnect(BluetoothDevice device, int epoch) async {
    if (epoch != _connectionEpoch || _userDisconnect || _connectInProgress) return;

    _linkReady = false;
    _cmdChar = null;
    _statusChar = null;
    _eventChar = null;
    _connectedDevice = null;
    await _wifiStatusSub?.cancel();
    _wifiStatusSub = null;
    await _unoEventSub?.cancel();
    _unoEventSub = null;
    _connectionEpoch++;

    await _connectionSub?.cancel();
    _connectionSub = null;

    if (!_disconnectedController.isClosed) {
      _disconnectedController.add(null);
    }
  }

  Future<void> _discoverCharacteristic({bool retry = false}) async {
    final device = _connectedDevice;
    if (device == null) return;

    for (var attempt = 0; attempt < (retry ? 3 : 1); attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
      }
      try {
        final services = await device.discoverServices();
        _cmdChar = _findCharacteristic(services);
        if (_cmdChar != null) return;
      } catch (_) {}
    }
  }

  BluetoothCharacteristic? _findCharacteristic(List<BluetoothService> services) {
    for (final service in services) {
      if (_uuidMatches(service.uuid, BleConstants.serviceUuid)) {
        final c = _findWritableChar(service, BleConstants.cmdCharUuid);
        if (c != null) return c;
      }
    }
    return _findAnyWritableChar(services);
  }

  Future<void> disconnect() async {
    _userDisconnect = true;
    _connectInProgress = false;
    _linkReady = false;
    _connectionEpoch++;

    final device = _connectedDevice;
    _connectedDevice = null;
    _cmdChar = null;
    _statusChar = null;
    _eventChar = null;

    await _wifiStatusSub?.cancel();
    _wifiStatusSub = null;
    await _unoEventSub?.cancel();
    _unoEventSub = null;

    await _connectionSub?.cancel();
    _connectionSub = null;

    if (device != null) {
      try {
        if (device.isConnected) await device.disconnect(queue: false);
      } catch (_) {}
    }

    await Future<void>.delayed(const Duration(milliseconds: 300));
    _userDisconnect = false;
  }

  Future<void> sendCommand(String cmd) async {
    if (!isConnected) throw Exception('BLE desconectado');
    await _write(cmd.trim());
  }

  Future<void> provisionWifi(String ssid, String password) async {
    await sendCommand(BleConstants.wifiPayload(ssid, password));
  }

  Future<void> resetWifi() async {
    await sendCommand(BleConstants.bleResetWifi);
  }

  Future<EspWifiStatus?> readWifiStatus() async {
    final char = _statusChar;
    if (char == null || !isConnected) return null;

    try {
      final raw = await char.read().timeout(const Duration(seconds: 3));
      return EspWifiStatus.fromPayload(String.fromCharCodes(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> requestWifiStatus() async {
    if (_statusChar != null) {
      final status = await readWifiStatus();
      if (status != null) {
        _wifiStatusController.add(status);
        return;
      }
    }
    await sendCommand(BleConstants.wifiStatusCmd);
  }

  Future<void> _setupWifiStatus() async {
    await _wifiStatusSub?.cancel();
    _wifiStatusSub = null;
    _statusChar = null;

    final device = _connectedDevice;
    if (device == null) return;

    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
      }
      try {
        final services = await device.discoverServices();
        _statusChar = _findStatusCharacteristic(services);
        if (_statusChar == null) continue;

        if (_statusChar!.properties.notify) {
          await _statusChar!.setNotifyValue(true);
          _wifiStatusSub = _statusChar!.onValueReceived.listen((value) {
            if (value.isEmpty) return;
            _wifiStatusController.add(
              EspWifiStatus.fromPayload(String.fromCharCodes(value)),
            );
          });
        }

        final initial = await readWifiStatus();
        if (initial != null) {
          _wifiStatusController.add(initial);
        } else {
          await requestWifiStatus();
        }
        return;
      } catch (_) {}
    }
  }

  BluetoothCharacteristic? _findStatusCharacteristic(
    List<BluetoothService> services,
  ) {
    for (final service in services) {
      if (!_uuidMatches(service.uuid, BleConstants.serviceUuid)) continue;
      for (final c in service.characteristics) {
        if (_uuidMatches(c.uuid, BleConstants.statusCharUuid) &&
            (c.properties.read || c.properties.notify)) {
          return c;
        }
      }
    }
    return null;
  }

  Future<void> _setupUnoEvents() async {
    await _unoEventSub?.cancel();
    _unoEventSub = null;
    _eventChar = null;

    final device = _connectedDevice;
    if (device == null) return;

    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
      }
      try {
        final services = await device.discoverServices();
        _eventChar = _findEventCharacteristic(services);
        if (_eventChar == null) continue;

        if (_eventChar!.properties.notify) {
          await _eventChar!.setNotifyValue(true);
          _unoEventSub = _eventChar!.onValueReceived.listen((value) {
            if (value.isEmpty) return;
            final event = UnoEvent.fromPayload(String.fromCharCodes(value));
            if (event != null && !_unoEventController.isClosed) {
              _unoEventController.add(event);
            }
          });
        }
        return;
      } catch (_) {}
    }
  }

  BluetoothCharacteristic? _findEventCharacteristic(
    List<BluetoothService> services,
  ) {
    for (final service in services) {
      if (!_uuidMatches(service.uuid, BleConstants.serviceUuid)) continue;
      for (final c in service.characteristics) {
        if (_uuidMatches(c.uuid, BleConstants.eventCharUuid) &&
            (c.properties.read || c.properties.notify)) {
          return c;
        }
      }
    }
    return null;
  }

  Future<void> _write(String payload) async {
    if (_cmdChar == null) await _discoverCharacteristic(retry: true);
    final char = _cmdChar;
    if (char == null || !isConnected) {
      throw Exception('No hay enlace BLE activo');
    }

    await char.write(
      utf8.encode(payload),
      withoutResponse: char.properties.writeWithoutResponse && !char.properties.write,
    );
  }

  bool _uuidMatches(Guid guid, String shortOrFull) {
    if (guid == Guid(shortOrFull)) return true;
    final full = _expandShortUuid(shortOrFull);
    return guid.toString().toLowerCase() == full.toLowerCase();
  }

  String _expandShortUuid(String shortUuid) {
    final hex = shortUuid.replaceAll('-', '').toLowerCase();
    if (hex.length == 4) {
      return '0000$hex-0000-1000-8000-00805f9b34fb';
    }
    return shortUuid;
  }

  BluetoothCharacteristic? _findWritableChar(BluetoothService service, String uuid) {
    for (final c in service.characteristics) {
      if (_uuidMatches(c.uuid, uuid) &&
          (c.properties.write || c.properties.writeWithoutResponse)) {
        return c;
      }
    }
    return null;
  }

  BluetoothCharacteristic? _findAnyWritableChar(List<BluetoothService> services) {
    for (final service in services) {
      for (final c in service.characteristics) {
        if (c.properties.write || c.properties.writeWithoutResponse) return c;
      }
    }
    return null;
  }

  void dispose() {
    stopScan();
    _connectionSub?.cancel();
    _wifiStatusSub?.cancel();
    _unoEventSub?.cancel();
    _disconnectedController.close();
    _wifiStatusController.close();
    _unoEventController.close();
  }
}
