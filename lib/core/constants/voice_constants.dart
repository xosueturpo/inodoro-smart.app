/// Voz: palabra clave «Cover» + Gemini para intención de comando.
class VoiceConstants {
  VoiceConstants._();

  static const wakeWordDisplay = 'Cover';
  /// Modelo más barato con calidad suficiente para clasificación binaria.
  static const geminiModel = 'gemini-2.5-flash-lite';
  /// Confianza mínima aceptada de Gemini (0–1).
  static const geminiConfidenceThreshold = 0.48;

  static const flushCooldown = Duration(seconds: 8);

  /// Standby: sesiones largas y pausa amplia → menos reinicios del mic (Samsung pitaba cada ~6 s).
  static const standbySessionLength = Duration(minutes: 5);
  static const standbyPauseFor = Duration(seconds: 45);

  /// Burbuja activa: corta cuando el STT deja de oír palabras (no por ruido ambiente).
  static const commandSessionLength = Duration(seconds: 20);
  /// Sin palabras durante este tiempo → el STT cierra la sesión (`done`).
  static const commandPauseFor = Duration(seconds: 2);
  static const commandSessionMaxDuration = Duration(seconds: 18);
  /// Tras el último fragmento final del STT, esperar un poco y procesar.
  static const commandWordsSettledDelay = Duration(milliseconds: 550);
  static const wakeActivationDelayMs = 380;
  static const bubbleDismissDelay = Duration(milliseconds: 1600);

  static const sttStopDelayMs = 450;
  static const sttMinGapBetweenSessionsMs = 1200;
  static const sttReconnectDelay = Duration(milliseconds: 1500);
  static const sttErrorBackoff = Duration(milliseconds: 1500);
  static const sttClientErrorMaxBackoff = Duration(milliseconds: 2800);
  static const sttSessionEndDebounceMs = 150;
}
