import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/constants/led_commands.dart';
import '../models/device_models.dart';
import '../services/ble_provisioning_service.dart';
import '../services/discovery_service.dart';
import '../services/voice_command_service.dart';

class AppProvider extends ChangeNotifier {
  AppProvider({
    BleProvisioningService? bleService,
    DiscoveryService? discoveryService,
    DeviceApiService? apiService,
    VoiceCommandService? voiceService,
  })  : _ble = bleService ?? BleProvisioningService(),
        _discovery = discoveryService ?? DiscoveryService(),
        _api = apiService ?? DeviceApiService(),
        _voice = voiceService ?? VoiceCommandService() {
    _bleDisconnectSub = _ble.onDisconnected.listen((_) => _onBleUnexpectedDisconnect());
    _voice.bind(
      onFlushRequested: () {
        if (canSendCommands) unawaited(sendFlushCommand());
      },
      onRefillRequested: () {
        if (canSendCommands) unawaited(sendRefillCommand());
      },
      onStateChanged: notifyListeners,
    );
  }

  final BleProvisioningService _ble;
  final DiscoveryService _discovery;
  final DeviceApiService _api;
  final VoiceCommandService _voice;

  DeviceSession? _session;
  bool _sessionActive = false;
  bool _connectInProgress = false;
  int _sessionConnectEpoch = 0;
  Timer? _reconnectTimer;
  Timer? _unoEventPollTimer;
  StreamSubscription? _bleDisconnectSub;
  StreamSubscription? _wifiStatusSub;
  StreamSubscription? _unoEventSub;

  LedState _led = const LedState();
  EspWifiStatus? _wifiStatus;
  bool _flushInProgress = false;
  bool _refillInProgress = false;
  int _lastUnoEventSeq = 0;
  List<BleScanResult> _bleResults = [];
  List<DiscoveryResult> _lanResults = [];
  bool _scanningBle = false;
  bool _scanningLan = false;
  String? _bleScanError;
  String? _lanScanError;

  DeviceSession? get session => _session;
  bool get hasActiveSession => _sessionActive && _session != null;
  LedState get led => _led;
  List<BleScanResult> get bleResults => _bleResults;
  List<DiscoveryResult> get lanResults => _lanResults;
  bool get scanningBle => _scanningBle;
  bool get scanningLan => _scanningLan;
  String? get bleScanError => _bleScanError;
  String? get lanScanError => _lanScanError;
  bool get flushInProgress => _flushInProgress;
  bool get refillInProgress => _refillInProgress;
  bool get deviceBusy => _flushInProgress || _refillInProgress;
  VoiceCommandService get voice => _voice;
  bool get canSendCommands =>
      _session?.linkState == SessionLinkState.connected && !deviceBusy;

  /// Control de tapa: permitido con conexión activa salvo durante descarga.
  bool get canControlLid =>
      _session?.linkState == SessionLinkState.connected && !_flushInProgress;

  /// Abrir tapa: permitido con conexión activa salvo durante descarga.
  bool get canOpenLid => canControlLid;

  /// Cerrar tapa: permitido con conexión activa salvo durante descarga.
  bool get canCloseLid => canControlLid;
  EspWifiStatus? get wifiStatus => _wifiStatus;
  bool get isBleSession => _session?.channel == ConnectionChannel.ble;
  bool get isDemoSession => _session?.channel == ConnectionChannel.demo;

  static const Duration demoCycleDuration = Duration(seconds: 3);

  Future<void> initialize() async {
    notifyListeners();
  }

  Future<void> scanBle() async {
    if (_scanningBle) return;
    _scanningBle = true;
    _bleScanError = null;
    _bleResults = [];
    notifyListeners();

    try {
      await _ble.scanContinuously(
        shouldContinue: () => _scanningBle,
        onResults: (results) {
          _bleResults = results;
          notifyListeners();
        },
      );
    } catch (e) {
      _bleScanError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _scanningBle = false;
      notifyListeners();
    }
  }

  Future<void> stopBleScan({bool notify = true}) async {
    _scanningBle = false;
    await _ble.stopScan();
    await _ble.waitScanIdle();
    if (notify) notifyListeners();
  }

  Future<void> scanLan() async {
    if (_scanningLan) return;
    _scanningLan = true;
    _lanScanError = null;
    _lanResults = [];
    notifyListeners();

    try {
      _lanResults = await _discovery.discover(
        shouldContinue: () => _scanningLan,
      );
    } catch (e) {
      _lanScanError = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _scanningLan = false;
      notifyListeners();
    }
  }

  Future<void> stopLanScan({bool notify = true}) async {
    _scanningLan = false;
    _discovery.cancelDiscover();
    await _discovery.waitDiscoverIdle();
    if (notify) notifyListeners();
  }

  Future<void> openBleSession(BluetoothDevice device, String name) async {
    await stopBleScan();
    await stopLanScan();
    _api.disconnect();

    _sessionConnectEpoch++;
    _sessionActive = true;
    _session = DeviceSession(
      channel: ConnectionChannel.ble,
      deviceName: name,
      deviceId: device.remoteId.str,
      bleDeviceId: device.remoteId.str,
    );
    notifyListeners();

    await _connectSession();
    _startReconnectLoop();
  }

  Future<void> openLanSession(String host, String name) async {
    await stopLanScan();
    await stopBleScan();
    _api.disconnect();

    _sessionConnectEpoch++;
    _sessionActive = true;
    _session = DeviceSession(
      channel: ConnectionChannel.lan,
      deviceName: name,
      deviceId: host,
      host: host,
    );
    notifyListeners();

    await _connectSession();
    _startReconnectLoop();
  }

  /// Sesión demo: interfaz completa sin hardware; descarga/recarga simuladas 3 s.
  Future<void> openDemoSession() async {
    await stopLanScan();
    await stopBleScan();
    await _voice.stop();
    _api.disconnect();
    await _ble.disconnect();

    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _sessionConnectEpoch++;
    _sessionActive = true;
    _flushInProgress = false;
    _refillInProgress = false;
    _led = const LedState(command: LedCommands.green);

    _session = DeviceSession(
      channel: ConnectionChannel.demo,
      deviceName: 'Modo demo',
      deviceId: 'demo-local',
    )..linkState = SessionLinkState.connected;

    notifyListeners();
  }

  void _startReconnectLoop() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_sessionActive || _session == null || _connectInProgress) return;
      final state = _session!.linkState;
      if (state == SessionLinkState.error || state == SessionLinkState.reconnecting) {
        unawaited(_connectSession());
      } else if (state == SessionLinkState.connected) {
        unawaited(_verifyLink());
      }
    });
  }

  Future<void> reconnectNow() async {
    if (!_sessionActive || _session == null || _connectInProgress) return;
    await _connectSession();
  }

  Future<void> _connectSession() async {
    if (_connectInProgress || !_sessionActive || _session == null) return;

    _connectInProgress = true;
    final connectEpoch = _sessionConnectEpoch;
    final s = _session!;
    s.linkState = SessionLinkState.reconnecting;
    s.lastError = null;
    notifyListeners();

    try {
      if (s.channel == ConnectionChannel.ble) {
        await _ble.connectFromId(s.bleDeviceId!);
        if (connectEpoch != _sessionConnectEpoch || !_sessionActive) return;
        if (!_ble.isConnected) {
          throw Exception('No se pudo abrir enlace GATT');
        }
        s.linkState = SessionLinkState.connected;
        s.lastError = null;
        _listenWifiStatus();
        _listenUnoEvents();
      } else {
        await _api.connect(s.host!);
        if (connectEpoch != _sessionConnectEpoch || !_sessionActive) return;
        if (!_api.isConnected) {
          throw Exception('No se pudo conectar por LAN');
        }
        final resolved = _api.connectedHost ?? s.host!;
        _session = DeviceSession(
          channel: ConnectionChannel.lan,
          deviceName: s.deviceName,
          deviceId: resolved,
          host: resolved,
        )..linkState = SessionLinkState.connected;
        _listenUnoEvents();
      }
    } catch (e) {
      if (connectEpoch != _sessionConnectEpoch || !_sessionActive) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (_session != null) {
        _session!.linkState = SessionLinkState.error;
        _session!.lastError = msg;
      }
    } finally {
      if (connectEpoch == _sessionConnectEpoch) {
        _connectInProgress = false;
      }
      notifyListeners();
    }
  }

  void _listenWifiStatus() {
    _wifiStatusSub?.cancel();
    _wifiStatusSub = null;
    if (_session?.channel != ConnectionChannel.ble) return;

    _wifiStatusSub = _ble.onWifiStatus.listen((status) {
      if (!_sessionActive || _session?.channel != ConnectionChannel.ble) return;
      _wifiStatus = status;
      notifyListeners();
    });
    unawaited(_refreshWifiStatus());
  }

  Future<void> _refreshWifiStatus() async {
    if (_session?.channel != ConnectionChannel.ble || !_ble.isConnected) return;
    try {
      await _ble.requestWifiStatus();
    } catch (_) {}
  }

  Future<void> refreshWifiStatus() => _refreshWifiStatus();

  void _listenUnoEvents() {
    _unoEventSub?.cancel();
    _unoEventSub = null;
    _unoEventPollTimer?.cancel();
    _unoEventPollTimer = null;
    _flushInProgress = false;
    _refillInProgress = false;
    _lastUnoEventSeq = 0;

    unawaited(_voice.ensureReady());

    final s = _session;
    if (s == null || s.linkState != SessionLinkState.connected) return;

    if (s.channel == ConnectionChannel.ble) {
      _unoEventSub = _ble.onUnoEvent.listen(_handleUnoEvent);
      return;
    }

    _unoEventPollTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      unawaited(_pollLanUnoEvent());
    });
  }

  Future<void> _pollLanUnoEvent() async {
    final s = _session;
    if (!_sessionActive ||
        s == null ||
        s.channel != ConnectionChannel.lan ||
        s.host == null) {
      return;
    }

    final result = await _api.pollUnoEvent(s.host!);
    if (result == null || result.seq <= _lastUnoEventSeq) return;

    _lastUnoEventSeq = result.seq;
    if (result.event != null) {
      _handleUnoEvent(result.event!);
    }
  }

  void _handleUnoEvent(UnoEvent event) {
    if (!_sessionActive || _session == null) return;

    switch (event.type) {
      case UnoEventType.flushStart:
        _flushInProgress = true;
        _refillInProgress = false;
        _led = const LedState(command: LedCommands.blue);
        if (_voice.isReady) unawaited(_voice.pauseForDeviceCycle());
      case UnoEventType.flushEnd:
        _flushInProgress = false;
      case UnoEventType.refillStart:
        _refillInProgress = true;
        _flushInProgress = false;
        _led = const LedState(command: LedCommands.cyan);
        if (_voice.isReady) unawaited(_voice.pauseForDeviceCycle());
      case UnoEventType.refillEnd:
        _refillInProgress = false;
        _led = const LedState(command: LedCommands.green);
        if (_voice.isReady) unawaited(_voice.resumeAtReposo());
    }
    notifyListeners();
  }

  Future<void> provisionWifi(String ssid, String password) async {
    if (!canSendCommands || _session?.channel != ConnectionChannel.ble) {
      throw Exception('Conecta por Bluetooth para configurar WiFi');
    }
    final trimmedSsid = ssid.trim();
    if (trimmedSsid.isEmpty) {
      throw Exception('Ingresa el nombre de la red WiFi');
    }
    await _ble.provisionWifi(trimmedSsid, password);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _refreshWifiStatus();
  }

  Future<void> resetWifi() async {
    if (!canSendCommands || _session?.channel != ConnectionChannel.ble) {
      throw Exception('Conecta por Bluetooth para borrar WiFi');
    }
    await _ble.resetWifi();
    _wifiStatus = EspWifiStatus.unknown();
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await _refreshWifiStatus();
  }

  Future<void> _verifyLink() async {
    if (_connectInProgress || !_sessionActive || _session == null) return;
    if (_session!.linkState != SessionLinkState.connected) return;

    try {
      if (_session!.channel == ConnectionChannel.ble) {
        if (!_ble.isConnected) throw Exception('BLE desconectado');
      } else {
        if (_api.connectInProgress) return;
        final ok = await _api.ping(_session!.host!);
        if (!ok) throw Exception('Ping falló');
      }
    } catch (e) {
      if (!_sessionActive || _session == null) return;
      _session!.linkState = SessionLinkState.error;
      _session!.lastError = e.toString().replaceFirst('Exception: ', '');
      notifyListeners();
    }
  }

  void _onBleUnexpectedDisconnect() {
    if (!_sessionActive || _connectInProgress) return;
    if (_session?.channel != ConnectionChannel.ble) return;
    _session!.linkState = SessionLinkState.error;
    _session!.lastError = 'Conexión Bluetooth perdida';
    notifyListeners();
  }

  Future<void> closeSession({bool notify = true}) async {
    if (!_sessionActive && _session == null) return;

    await _voice.stop();
    _sessionActive = false;
    _sessionConnectEpoch++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await _wifiStatusSub?.cancel();
    _wifiStatusSub = null;
    await _unoEventSub?.cancel();
    _unoEventSub = null;
    _unoEventPollTimer?.cancel();
    _unoEventPollTimer = null;
    _wifiStatus = null;
    _flushInProgress = false;
    _refillInProgress = false;
    _lastUnoEventSeq = 0;

    final wasBle = _session?.channel == ConnectionChannel.ble;
    _session = null;
    _led = const LedState();

    if (wasBle) {
      await _ble.disconnect();
    }
    _api.disconnect();

    if (notify) notifyListeners();
  }

  Future<void> sendFlushCommand() async {
    if (!canSendCommands || deviceBusy) return;

    if (isDemoSession) {
      unawaited(_simulateDemoFlush());
      return;
    }

    if (_voice.isReady) await _voice.pauseForDeviceCycle();
    try {
      await _dispatchCommand(LedCommands.flush);
    } catch (e) {
      if (!deviceBusy && _voice.isReady) {
        await _voice.resumeAtReposo();
      }
      if (_session != null) {
        _session!.linkState = SessionLinkState.error;
        _session!.lastError = e.toString().replaceFirst('Exception: ', '');
        notifyListeners();
      }
    }
  }

  Future<void> sendRefillCommand() async {
    if (!canSendCommands || deviceBusy) return;

    if (isDemoSession) {
      unawaited(_simulateDemoRefill());
      return;
    }

    if (_voice.isReady) await _voice.pauseForDeviceCycle();
    try {
      await _dispatchCommand(LedCommands.refill);
    } catch (e) {
      if (!deviceBusy && _voice.isReady) {
        await _voice.resumeAtReposo();
      }
      if (_session != null) {
        _session!.linkState = SessionLinkState.error;
        _session!.lastError = e.toString().replaceFirst('Exception: ', '');
        notifyListeners();
      }
    }
  }

  Future<void> sendLidOpenCommand() async {
    if (!canOpenLid) return;

    if (isDemoSession) {
      notifyListeners();
      return;
    }

    try {
      await _dispatchCommand(LedCommands.lidOpen);
      if (_session != null) {
        _session!.lastError = null;
        notifyListeners();
      }
    } catch (e) {
      if (_session != null) {
        _session!.linkState = SessionLinkState.error;
        _session!.lastError = e.toString().replaceFirst('Exception: ', '');
        notifyListeners();
      }
    }
  }

  Future<void> sendLidCloseCommand() async {
    if (!canCloseLid) return;

    if (isDemoSession) {
      notifyListeners();
      return;
    }

    try {
      await _dispatchCommand(LedCommands.lidClose);
      if (_session != null) {
        _session!.lastError = null;
        notifyListeners();
      }
    } catch (e) {
      if (_session != null) {
        _session!.linkState = SessionLinkState.error;
        _session!.lastError = e.toString().replaceFirst('Exception: ', '');
        notifyListeners();
      }
    }
  }

  Future<void> startVoiceCommand() async {
    if (isDemoSession) return;
    if (_session?.linkState != SessionLinkState.connected) return;
    await _voice.beginCommandFromButton();
    notifyListeners();
  }

  Future<void> _simulateDemoFlush() async {
    if (!isDemoSession || deviceBusy) return;

    _flushInProgress = true;
    _refillInProgress = false;
    _led = const LedState(command: LedCommands.blue);
    notifyListeners();

    await Future<void>.delayed(demoCycleDuration);
    if (!isDemoSession || !_sessionActive) return;

    _flushInProgress = false;
    _led = const LedState(command: LedCommands.green);
    notifyListeners();
  }

  Future<void> _simulateDemoRefill() async {
    if (!isDemoSession || deviceBusy) return;

    _refillInProgress = true;
    _flushInProgress = false;
    _led = const LedState(command: LedCommands.cyan);
    notifyListeners();

    await Future<void>.delayed(demoCycleDuration);
    if (!isDemoSession || !_sessionActive) return;

    _refillInProgress = false;
    _led = const LedState(command: LedCommands.green);
    notifyListeners();
  }

  Future<void> _dispatchCommand(String cmd) async {
    final s = _session;
    if (s == null || s.linkState != SessionLinkState.connected) {
      throw Exception('Sin conexión activa');
    }
    if (s.channel == ConnectionChannel.demo) return;

    if (s.channel == ConnectionChannel.ble) {
      await _ble.sendCommand(cmd);
    } else {
      await _api.sendCommand(s.host!, cmd);
    }
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _bleDisconnectSub?.cancel();
    _wifiStatusSub?.cancel();
    _unoEventSub?.cancel();
    _unoEventPollTimer?.cancel();
    unawaited(_voice.stop());
    _ble.dispose();
    _api.dispose();
    super.dispose();
  }
}
