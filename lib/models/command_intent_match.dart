import 'device_voice_intent.dart';

class CommandIntentMatch {
  const CommandIntentMatch({
    required this.intent,
    required this.confidence,
  });

  final DeviceVoiceIntent intent;
  final double confidence;

  bool get isAction =>
      intent != DeviceVoiceIntent.none &&
      confidence >= CommandIntentThresholds.accept;
}

/// Umbrales compartidos entre heurística local y Gemini.
abstract final class CommandIntentThresholds {
  static const accept = 0.48;
  static const strong = 0.72;
}
