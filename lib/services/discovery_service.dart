import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';

import '../core/constants/api_constants.dart';
import '../models/device_models.dart';

class DiscoveryResult {
  DiscoveryResult({required this.host, required this.name, this.port});

  final String host;
  final String name;
  final int? port;
}

class DiscoveryService {
  Future<void>? _operationChain;
  bool _discoverCancelled = false;
  Completer<void>? _discoverLoopDone;

  /// Quita espacios y normaliza inodoro_smart.local.
  static String? normalizeHost(String host) {
    final cleaned = host.trim().replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) return null;
    final lower = cleaned.toLowerCase();
    if (lower == ApiConstants.mdnsHost() || lower == ApiConstants.mdnsHostname) {
      return ApiConstants.mdnsHost();
    }
    return cleaned;
  }

  void cancelDiscover() {
    _discoverCancelled = true;
  }

  Future<void> waitDiscoverIdle({Duration timeout = const Duration(seconds: 4)}) async {
    final done = _discoverLoopDone;
    if (done == null) return;
    try {
      await done.future.timeout(timeout);
    } catch (_) {}
  }

  Future<T> _serialize<T>(Future<T> Function() operation) async {
    final previous = _operationChain;
    final gate = Completer<void>();
    _operationChain = gate.future;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {}
    }
    try {
      return await operation();
    } finally {
      gate.complete();
      if (identical(_operationChain, gate.future)) {
        _operationChain = null;
      }
    }
  }

  /// Resuelve host a IPv4 (IP directa o mDNS).
  Future<String?> resolveHost(
    String host, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _serialize(() => _resolveHostUnlocked(host, timeout: timeout));
  }

  Future<String?> _resolveHostUnlocked(
    String host, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final normalized = normalizeHost(host);
    if (normalized == null) return null;
    if (_looksLikeIp(normalized)) return normalized;

    try {
      final addresses = await InternetAddress.lookup(normalized).timeout(timeout);
      if (addresses.isNotEmpty) return addresses.first.address;
    } catch (_) {}

    if (normalized.endsWith('.local')) {
      return _resolveMdnsIp(timeout);
    }
    return null;
  }

  Future<List<DiscoveryResult>> discover({
    Duration timeout = const Duration(seconds: 6),
    bool Function()? shouldContinue,
  }) {
    return _serialize(() async {
      _discoverCancelled = false;
      _discoverLoopDone = Completer<void>();
      try {
        final results = <String, DiscoveryResult>{};

        if (_shouldContinue(shouldContinue)) {
          await _discoverMdns(results, timeout, shouldContinue: shouldContinue);
        }
        if (_shouldContinue(shouldContinue)) {
          await _probeKnownHosts(results, shouldContinue: shouldContinue);
        }

        return results.values.toList();
      } finally {
        if (_discoverLoopDone != null && !_discoverLoopDone!.isCompleted) {
          _discoverLoopDone!.complete();
        }
      }
    });
  }

  bool _shouldContinue(bool Function()? shouldContinue) {
    if (_discoverCancelled) return false;
    return shouldContinue?.call() ?? true;
  }

  /// Resuelve la IP LAN del dispositivo (mDNS o probe).
  Future<String?> resolveIp({Duration timeout = const Duration(seconds: 8)}) async {
    final found = await discover(timeout: timeout);
    for (final r in found) {
      if (_looksLikeIp(r.host)) return r.host;
    }
    return null;
  }

  bool _looksLikeIp(String host) {
    final parts = host.split('.');
    return parts.length == 4 && parts.every((p) => int.tryParse(p) != null);
  }

  Future<String?> _resolveMdnsIp(Duration timeout) async {
    final mdns = MDnsClient();
    try {
      await mdns.start();

      await for (final ip in mdns
          .lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(ApiConstants.mdnsHost()),
          )
          .timeout(timeout, onTimeout: (sink) => sink.close())) {
        return ip.address.address;
      }

      await for (final ptr in mdns
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(ApiConstants.mdnsServiceType),
          )
          .timeout(timeout, onTimeout: (sink) => sink.close())) {
        if (!_isInodoroHost(ptr.domainName)) continue;

        await for (final srv in mdns.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        )) {
          await for (final ip in mdns.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
          )) {
            return ip.address.address;
          }
        }
      }
    } catch (_) {
    } finally {
      mdns.stop();
    }
    return null;
  }

  Future<void> _discoverMdns(
    Map<String, DiscoveryResult> results,
    Duration timeout, {
    bool Function()? shouldContinue,
  }) async {
    if (!_shouldContinue(shouldContinue)) return;

    final mdns = MDnsClient();
    try {
      await mdns.start();

      await for (final ptr in mdns.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(ApiConstants.mdnsServiceType),
      ).timeout(timeout, onTimeout: (sink) => sink.close())) {
        if (!_shouldContinue(shouldContinue)) break;

        await for (final srv in mdns.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        )) {
          await for (final ip in mdns.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
          )) {
            if (_isInodoroHost(ptr.domainName)) {
              results[ip.address.address] = DiscoveryResult(
                host: ip.address.address,
                name: ApiConstants.mdnsHostname,
                port: srv.port,
              );
            }
          }
        }
      }

      if (_shouldContinue(shouldContinue)) {
        final directIp = await _resolveMdnsIp(const Duration(seconds: 2));
        if (directIp != null) {
          results[directIp] = DiscoveryResult(
            host: directIp,
            name: ApiConstants.mdnsHostname,
          );
        }
      }
    } catch (_) {
    } finally {
      mdns.stop();
    }
  }

  bool _isInodoroHost(String domainName) {
    return domainName.toLowerCase().contains(ApiConstants.mdnsHostname);
  }

  Future<void> _probeKnownHosts(
    Map<String, DiscoveryResult> results, {
    bool Function()? shouldContinue,
  }) async {
    if (!_shouldContinue(shouldContinue)) return;

    final candidates = <String>[
      ...results.keys,
      ...await _generateLocalSubnetHosts(),
    ];

    final mdnsIp = await _resolveHostUnlocked(
      ApiConstants.mdnsHost(),
      timeout: const Duration(seconds: 3),
    );
    if (mdnsIp != null) {
      candidates.add(mdnsIp);
    }

    for (final host in candidates.toSet()) {
      if (!_shouldContinue(shouldContinue)) break;
      if (results.containsKey(host)) continue;
      if (await _pingHost(host)) {
        results[host] = DiscoveryResult(host: host, name: ApiConstants.mdnsHostname);
      }
    }
  }

  Future<List<String>> _generateLocalSubnetHosts() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      final hosts = <String>[];
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final parts = addr.address.split('.');
          if (parts.length != 4) continue;
          final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
          for (final last in [1, 100, 101, 102, 103, 104, 105, 150, 200]) {
            hosts.add('$prefix.$last');
          }
        }
      }
      return hosts.toSet().toList();
    } catch (_) {
      return [];
    }
  }

  Future<bool> _pingHost(String host) async {
    final resolved = await _resolveHostUnlocked(host, timeout: const Duration(seconds: 2));
    if (resolved == null) return false;

    try {
      final socket = await Socket.connect(
        resolved,
        ApiConstants.httpPort,
        timeout: const Duration(milliseconds: 900),
      );
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }
}

class DeviceApiService {
  DeviceApiService({DiscoveryService? discovery})
      : _discovery = discovery ?? DiscoveryService();

  final DiscoveryService _discovery;

  String? _cachedHostKey;
  String? _cachedIp;
  String? _connectedHost;

  Future<void>? _connectQueue;
  bool _connectInProgress = false;
  bool _linkReady = false;
  int _connectionEpoch = 0;

  bool get isConnected => _linkReady && _connectedHost != null;
  String? get connectedHost => _connectedHost;
  bool get connectInProgress => _connectInProgress;

  void clearHostCache() {
    _cachedHostKey = null;
    _cachedIp = null;
  }

  void disconnect() {
    _connectionEpoch++;
    _linkReady = false;
    _connectedHost = null;
    _connectInProgress = false;
    clearHostCache();
  }

  /// Conexión LAN serializada — una a la vez, con reintentos (como BLE).
  Future<void> connect(String host) async {
    final previous = _connectQueue;
    final gate = Completer<void>();
    _connectQueue = gate.future;
    if (previous != null) {
      try {
        await previous;
      } catch (_) {}
    }

    try {
      await _connectOnce(host);
    } finally {
      gate.complete();
      if (identical(_connectQueue, gate.future)) {
        _connectQueue = null;
      }
    }
  }

  Future<void> _connectOnce(String host) async {
    final normalized = DiscoveryService.normalizeHost(host);
    if (normalized == null) {
      throw Exception('Host invalido: "$host"');
    }

    if (_linkReady && _connectedHost != null && _cachedHostKey == normalized) {
      final ok = await _pingResolved(_connectedHost!);
      if (ok) return;
    }

    _connectInProgress = true;
    _linkReady = false;
    _connectedHost = null;
    final epoch = ++_connectionEpoch;

    try {
      Object? lastError;
      for (var attempt = 0; attempt < 3; attempt++) {
        if (epoch != _connectionEpoch) {
          throw Exception('Conexión cancelada');
        }
        if (attempt > 0) {
          clearHostCache();
          await Future<void>.delayed(Duration(milliseconds: 450 * attempt));
        }

        try {
          final ip = await _discovery.resolveHost(normalized);
          if (ip == null) {
            lastError = Exception('No se resolvió $normalized en la red local');
            continue;
          }

          if (epoch != _connectionEpoch) {
            throw Exception('Conexión cancelada');
          }

          final ok = await _pingResolved(ip);
          if (!ok) {
            lastError = Exception('ESP32 no responde en $ip (¿WiFi configurado?)');
            continue;
          }

          _cachedHostKey = normalized;
          _cachedIp = ip;
          _connectedHost = ip;
          _linkReady = true;
          return;
        } catch (e) {
          lastError = e;
          if (epoch != _connectionEpoch) rethrow;
        }
      }

      throw lastError ?? Exception('No se pudo conectar por LAN');
    } finally {
      _connectInProgress = false;
    }
  }

  Future<String> _resolveForRequest(String host) async {
    final normalized = DiscoveryService.normalizeHost(host);
    if (normalized == null) {
      throw Exception('Host invalido: "$host"');
    }

    if (_linkReady && _connectedHost != null && _cachedHostKey == normalized) {
      return _connectedHost!;
    }

    if (_cachedHostKey == normalized && _cachedIp != null) {
      return _cachedIp!;
    }

    final ip = await _discovery.resolveHost(normalized);
    if (ip == null) {
      throw Exception(
        'No se pudo resolver $normalized. Usa la IP (ej. 192.168.1.x) o busca de nuevo en LAN.',
      );
    }

    _cachedHostKey = normalized;
    _cachedIp = ip;
    return ip;
  }

  Future<bool> _pingResolved(String ip) async {
    try {
      final uri = Uri.parse('${ApiConstants.baseUrl(ip)}${ApiConstants.pingPath}');
      final response = await http.get(uri).timeout(const Duration(seconds: 3));
      return response.statusCode == 200 && response.body.trim() == 'OK';
    } catch (_) {
      return false;
    }
  }

  /// POST a /cmd con body plain: R | OFF | RGB:255,100,0
  Future<void> sendCommand(String host, String cmd) async {
    if (!_linkReady) {
      throw Exception('Sin conexión LAN activa');
    }
    final ip = await _resolveForRequest(host);
    final uri = Uri.parse('${ApiConstants.baseUrl(ip)}${ApiConstants.cmdPath}');
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'text/plain'},
          body: cmd.trim(),
        )
        .timeout(const Duration(seconds: 4));

    if (response.statusCode >= 400) {
      throw HttpException('CMD error ${response.statusCode}');
    }
  }

  Future<bool> verifyConnection(String host) async {
    try {
      final ip = await _resolveForRequest(host);
      return _pingResolved(ip);
    } catch (_) {
      return false;
    }
  }

  Future<bool> ping(String host) async {
    if (_connectInProgress) return _linkReady;
    try {
      return await verifyConnection(host);
    } catch (_) {
      return false;
    }
  }

  /// GET /evt → "seq|FLUSH_START" (puente UNO→ESP32→app).
  Future<({int seq, UnoEvent? event})?> pollUnoEvent(String host) async {
    if (!_linkReady) return null;

    try {
      final ip = await _resolveForRequest(host);
      final uri = Uri.parse('${ApiConstants.baseUrl(ip)}${ApiConstants.evtPath}');
      final response = await http.get(uri).timeout(const Duration(seconds: 2));
      if (response.statusCode != 200) return null;

      final body = response.body.trim();
      if (body.isEmpty) return null;

      final sep = body.indexOf('|');
      if (sep <= 0) return null;

      final seq = int.tryParse(body.substring(0, sep));
      if (seq == null || seq <= 0) return null;

      final payload = body.substring(sep + 1);
      if (payload.isEmpty) return (seq: seq, event: null);

      return (seq: seq, event: UnoEvent.fromPayload(payload));
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    disconnect();
  }
}
