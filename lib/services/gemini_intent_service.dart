import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

import '../core/config/gemini_config.dart';
import '../core/constants/voice_constants.dart';
import '../models/command_intent_match.dart';
import '../models/device_voice_intent.dart';
import 'flush_intent_heuristic.dart';

enum GeminiIntentLoadState { notConfigured, ready, failed }

/// Clasifica comandos ambiguos con Gemini (heurística local va primero).
class GeminiIntentService {
  GeminiIntentLoadState _loadState = GeminiIntentLoadState.notConfigured;
  String? _statusMessage;
  GenerativeModel? _model;
  Future<void> _requestQueue = Future<void>.value();

  GeminiIntentLoadState get loadState => _loadState;
  String? get statusMessage => _statusMessage;
  bool get modelReady => _loadState == GeminiIntentLoadState.ready;

  Future<void> ensureModel({void Function(int progress)? onProgress}) async {
    if (_loadState == GeminiIntentLoadState.ready) return;

    if (!GeminiConfig.hasApiKey) {
      _loadState = GeminiIntentLoadState.notConfigured;
      _statusMessage =
          'Sin clave Gemini — crea lib/core/config/gemini_api_key.local.dart';
      return;
    }

    try {
      _model = GenerativeModel(
        model: VoiceConstants.geminiModel,
        apiKey: GeminiConfig.apiKey,
        generationConfig: GenerationConfig(
          temperature: 0,
          maxOutputTokens: 24,
          responseMimeType: 'text/plain',
        ),
        systemInstruction: Content.text(_systemInstruction),
      );
      _loadState = GeminiIntentLoadState.ready;
      _statusMessage = null;
      onProgress?.call(100);
    } catch (e) {
      _loadState = GeminiIntentLoadState.failed;
      _statusMessage = 'Gemini: $e';
      if (kDebugMode) {
        debugPrint('[GeminiIntentService] init failed: $e');
      }
    }
  }

  Future<bool> isFlushCommandIntent(String userPhrase) async {
    final match = await classifyWithConfidence(userPhrase);
    return match.intent == DeviceVoiceIntent.flush && match.isAction;
  }

  Future<bool> isRefillCommandIntent(String userPhrase) async {
    final match = await classifyWithConfidence(userPhrase);
    return match.intent == DeviceVoiceIntent.refill && match.isAction;
  }

  Future<DeviceVoiceIntent> classifyCommandIntent(String userPhrase) async {
    final match = await classifyWithConfidence(userPhrase);
    return match.intent;
  }

  Future<CommandIntentMatch> classifyWithConfidence(String userPhrase) {
    return _runSerialized(() => _classify(userPhrase));
  }

  Future<T> _runSerialized<T>(Future<T> Function() fn) {
    final run = _requestQueue.then((_) => fn());
    _requestQueue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<CommandIntentMatch> _classify(String command) async {
    final local = FlushIntentHeuristic.classify(command);
    if (local != null && local.confidence >= CommandIntentThresholds.accept) {
      return local;
    }

    if (_loadState != GeminiIntentLoadState.ready || _model == null) {
      return local ??
          const CommandIntentMatch(
            intent: DeviceVoiceIntent.none,
            confidence: 0,
          );
    }

    try {
      final response = await _model!.generateContent([
        Content.text('Comando del usuario: "$command"'),
      ]);
      final parsed = _parseResponse(response.text ?? '');
      if (parsed.intent == DeviceVoiceIntent.none) {
        return local ??
            const CommandIntentMatch(
              intent: DeviceVoiceIntent.none,
              confidence: 0,
            );
      }
      if (parsed.confidence < VoiceConstants.geminiConfidenceThreshold) {
        return local ??
            CommandIntentMatch(
              intent: DeviceVoiceIntent.none,
              confidence: parsed.confidence,
            );
      }
      return parsed;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[GeminiIntentService] classify failed: $e\n$st');
      }
      return local ??
          const CommandIntentMatch(
            intent: DeviceVoiceIntent.none,
            confidence: 0,
          );
    }
  }

  static const _systemInstruction = '''
Eres un clasificador de voz para un inodoro inteligente con SOLO dos acciones:

1) FLUSH — descargar / vaciar / usar el inodoro / tirar la cadena / limpiar el baño.
2) REFILL — recargar o llenar el tanque / cisterna / depósito de agua del inodoro.

Reglas:
- Si el usuario pide agua PARA EL TANQUE, cisterna o reserva → REFILL.
- Si pide usar, vaciar, limpiar o descargar el inodoro/baño → FLUSH.
- Frases cortas o coloquiales ("hazlo", "dale", "ya", "por favor") cuentan si el contexto apunta claramente a una acción.
- "Agua" sola es ambigua: elige REFILL solo si suena a llenar tanque; FLUSH si suena a usar el baño.
- Si no puedes decidir con seguridad razonable → NONE.

Responde EXACTAMENTE una línea en este formato:
ACCION:CONFIANZA

Donde ACCION es FLUSH, REFILL o NONE y CONFIANZA es un decimal 0.00–1.00 (qué tan seguro estás).

Ejemplos:
"llena el depósito" → REFILL:0.95
"necesito el baño ya" → FLUSH:0.88
"ponle agua al tanque" → REFILL:0.97
"limpia el wc por favor" → FLUSH:0.92
"hazlo" → NONE:0.20
"agua" → NONE:0.35
"échale agua arriba" → REFILL:0.75
''';

  CommandIntentMatch _parseResponse(String raw) {
    final line = raw
        .trim()
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
        .trim()
        .toUpperCase();

    final match = RegExp(r'^(FLUSH|REFILL|NONE)\s*[:;\-]\s*([0-9]*\.?[0-9]+)')
        .firstMatch(line);
    if (match != null) {
      return CommandIntentMatch(
        intent: _wordToIntent(match.group(1)!),
        confidence: double.tryParse(match.group(2)!)?.clamp(0.0, 1.0) ?? 0,
      );
    }

    final word = line.split(RegExp(r'\s+')).first;
    if (word.startsWith('REFILL') || word == 'RECARGA') {
      return const CommandIntentMatch(
        intent: DeviceVoiceIntent.refill,
        confidence: 0.7,
      );
    }
    if (word.startsWith('FLUSH') || word == 'DESCARGA') {
      return const CommandIntentMatch(
        intent: DeviceVoiceIntent.flush,
        confidence: 0.7,
      );
    }
    return const CommandIntentMatch(
      intent: DeviceVoiceIntent.none,
      confidence: 0,
    );
  }

  DeviceVoiceIntent _wordToIntent(String word) {
    if (word.startsWith('REFILL')) return DeviceVoiceIntent.refill;
    if (word.startsWith('FLUSH')) return DeviceVoiceIntent.flush;
    return DeviceVoiceIntent.none;
  }
}
