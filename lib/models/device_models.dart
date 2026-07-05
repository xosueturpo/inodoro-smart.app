import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/constants/led_commands.dart';

enum ConnectionChannel { ble, lan, demo }

enum SessionLinkState {
  connected,
  reconnecting,
  error,
}

enum EspWifiState {
  none,
  configured,
  connecting,
  connected,
  failed,
}

class EspWifiStatus {
  const EspWifiStatus({
    required this.state,
    this.ssid,
    this.ip,
  });

  final EspWifiState state;
  final String? ssid;
  final String? ip;

  bool get isOnline => state == EspWifiState.connected;

  String get stateLabel => switch (state) {
        EspWifiState.connected => 'Conectado',
        EspWifiState.connecting => 'Conectando…',
        EspWifiState.failed => 'Credenciales incorrectas',
        EspWifiState.configured => 'Guardado (sin conectar)',
        EspWifiState.none => 'Sin configurar',
      };

  static EspWifiStatus unknown() =>
      const EspWifiStatus(state: EspWifiState.none);

  static EspWifiStatus fromPayload(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return unknown();

    final parts = trimmed.split('|');
    final tag = parts.isNotEmpty ? parts[0].toUpperCase() : 'NONE';
    final ssid = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
    final ip = parts.length > 2 && parts[2].isNotEmpty ? parts[2] : null;

    final state = switch (tag) {
      'CONNECTED' => EspWifiState.connected,
      'CONNECTING' => EspWifiState.connecting,
      'FAILED' => EspWifiState.failed,
      'CONFIGURED' => EspWifiState.configured,
      _ => EspWifiState.none,
    };

    return EspWifiStatus(state: state, ssid: ssid, ip: ip);
  }
}

enum UnoEventType {
  flushStart,
  flushEnd,
  refillStart,
  refillEnd,
}

class UnoEvent {
  const UnoEvent({required this.type});

  final UnoEventType type;

  static UnoEvent? fromPayload(String raw) {
    var tag = raw.trim().toUpperCase();
    if (tag.startsWith('EVT:')) {
      tag = tag.substring(4).trim();
    }

    return switch (tag) {
      'FLUSH_START' => const UnoEvent(type: UnoEventType.flushStart),
      'FLUSH_END' => const UnoEvent(type: UnoEventType.flushEnd),
      'REFILL_START' => const UnoEvent(type: UnoEventType.refillStart),
      'REFILL_END' => const UnoEvent(type: UnoEventType.refillEnd),
      _ => null,
    };
  }
}

class LedState {
  const LedState({this.command = LedCommands.off});

  /// Estado de indicador en la app (no es comando de prueba RGB).
  final String command;

  bool get isOn => command != LedCommands.off;

  Color get color => LedCommands.color(command);

  static LedState fromStatus(String cmd) {
    final upper = cmd.trim().toUpperCase();
    if (LedCommands.isStatus(upper)) {
      return LedState(command: upper);
    }
    return const LedState();
  }
}

class InodoroSmartDevice {
  const InodoroSmartDevice({
    required this.id,
    required this.name,
    this.host,
    this.bleId,
    this.lastSeen,
  });

  final String id;
  final String name;
  final String? host;
  final String? bleId;
  final DateTime? lastSeen;

  InodoroSmartDevice copyWith({
    String? id,
    String? name,
    String? host,
    String? bleId,
    DateTime? lastSeen,
  }) =>
      InodoroSmartDevice(
        id: id ?? this.id,
        name: name ?? this.name,
        host: host ?? this.host,
        bleId: bleId ?? this.bleId,
        lastSeen: lastSeen ?? this.lastSeen,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'bleId': bleId,
        'lastSeen': lastSeen?.toIso8601String(),
      };

  factory InodoroSmartDevice.fromJson(Map<String, dynamic> json) =>
      InodoroSmartDevice(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'INODORO_SMART',
        host: json['host'] as String?,
        bleId: json['bleId'] as String?,
        lastSeen: json['lastSeen'] != null
            ? DateTime.tryParse(json['lastSeen'] as String)
            : null,
      );

  static String encodeList(List<InodoroSmartDevice> devices) =>
      jsonEncode(devices.map((d) => d.toJson()).toList());

  static List<InodoroSmartDevice> decodeList(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => InodoroSmartDevice.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

class DeviceSession {
  DeviceSession({
    required this.channel,
    required this.deviceName,
    required this.deviceId,
    this.host,
    this.bleDeviceId,
  });

  final ConnectionChannel channel;
  final String deviceName;
  final String deviceId;
  final String? host;
  final String? bleDeviceId;

  SessionLinkState linkState = SessionLinkState.reconnecting;
  String? lastError;
}
