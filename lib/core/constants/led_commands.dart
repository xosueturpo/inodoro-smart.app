import 'package:flutter/material.dart';

/// Comandos de dispositivo y estados de LED (solo indicadores de estado en app).
class LedCommands {
  LedCommands._();

  /// Estados internos de UI (no se envían como prueba de color al hardware).
  static const off = 'OFF';
  static const red = 'R';
  static const green = 'G';
  static const blue = 'B';
  static const cyan = 'C';

  static const flush = 'FLUSH';
  static const refill = 'REFILL';
  static const lidOpen = 'LID_OPEN';
  static const lidClose = 'LID_CLOSE';

  static const labels = {
    off: 'Apagado',
    red: 'Rojo',
    green: 'Verde',
    blue: 'Azul',
    cyan: 'Cian',
  };

  static const previewColors = {
    off: Color(0xFF8E8E93),
    red: Color(0xFFFF3B30),
    green: Color(0xFF34C759),
    blue: Color(0xFF007AFF),
    cyan: Color(0xFF5AC8FA),
  };

  static String label(String cmd) => labels[cmd.toUpperCase()] ?? cmd;

  static Color color(String cmd) =>
      previewColors[cmd.toUpperCase()] ?? const Color(0xFF8E8E93);

  static bool isStatus(String cmd) =>
      previewColors.containsKey(cmd.toUpperCase());
}
