import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../core/constants/voice_constants.dart';
import '../models/command_intent_match.dart';
import '../models/device_voice_intent.dart';
import 'flush_intent_heuristic.dart';
import 'gemini_intent_service.dart';

enum VoiceListenState {
  off,
  /// Listo para comando (mic apagado hasta pulsar FAB).
  ready,
  activeListening,
  processing,
  paused,
  error,
}

/// Comando de voz bajo demanda: FAB → burbuja → ejecutar descarga o recarga.
class VoiceCommandService with WidgetsBindingObserver {
  VoiceCommandService({GeminiIntentService? intentService})
      : _intentService = intentService ?? GeminiIntentService();

  final GeminiIntentService _intentService;
  final SpeechToText _speech = SpeechToText();

  VoiceListenState _state = VoiceListenState.off;
  bool _commandActive = false;
  String? _lastHeard;
  String? _lastAction;
  String? _error;
  double _micLevel = 0;
  double _micPeak = 0;
  bool _initialized = false;
  bool _busy = false;
  bool _deviceCyclePaused = false;
  bool _appInForeground = true;
  bool _openingSession = false;
  String? _localeId;
  String _commandTranscript = '';
  DateTime? _commandSessionStartedAt;
  DateTime? _lastDeviceTrigger;
  Timer? _commandSessionTimer;
  Timer? _commandFinalizeTimer;
  Timer? _peakDecayTimer;
  DateTime? _lastMicSessionEndedAt;
  bool _commandMicRetryUsed = false;
  int _clientErrorStreak = 0;
  bool _evaluating = false;
  int _evaluateGeneration = 0;
  void Function()? _onFlushRequested;
  void Function()? _onRefillRequested;
  void Function()? _onStateChanged;

  VoiceListenState get state => _state;
  String? get lastHeard => _lastHeard;
  String? get lastAction => _lastAction;
  String? get error => _error;
  double get micLevel => _micLevel;
  bool get micSessionOpen => _speech.isListening && !_deviceCyclePaused;
  bool get isPausedForDevice => _deviceCyclePaused;
  bool get showAssistantBubble =>
      _state == VoiceListenState.activeListening ||
      _state == VoiceListenState.processing;
  GeminiIntentService get intentService => _intentService;
  bool get isReady => _initialized && _state != VoiceListenState.off;

  void bind({
    required void Function() onFlushRequested,
    required void Function() onRefillRequested,
    required void Function() onStateChanged,
  }) {
    _onFlushRequested = onFlushRequested;
    _onRefillRequested = onRefillRequested;
    _onStateChanged = onStateChanged;
  }

  Future<void> pauseForDeviceCycle() async {
    _deviceCyclePaused = true;
    _busy = true;
    _evaluating = false;
    _evaluateGeneration++;
    _cancelCommandTimers();
    await _stopMic();
    _micLevel = 0;
    _micPeak = 0;
    _commandTranscript = '';
    _commandActive = false;
    _commandSessionStartedAt = null;
    _lastHeard = null;
    _setState(VoiceListenState.paused);
  }

  Future<void> resumeAtReposo() async {
    if (!_initialized) return;
    _deviceCyclePaused = false;
    _busy = false;
    _commandTranscript = '';
    _lastHeard = null;
    _lastAction = null;
    _commandActive = false;
    _setState(VoiceListenState.ready);
  }

  /// Inicializa STT y Gemini sin abrir el micrófono.
  Future<void> ensureReady() async {
    if (_initialized) {
      if (_state == VoiceListenState.off) {
        _setState(VoiceListenState.ready);
      }
      return;
    }

    _lastAction = null;
    _error = null;
    _commandTranscript = '';
    WidgetsBinding.instance.addObserver(this);

    final mic = await Permission.microphone.request();
    if (!mic.isGranted) {
      _setState(VoiceListenState.error, error: 'Permiso de micrófono denegado');
      return;
    }

    final available = await _speech.initialize(
      onError: _onSttError,
      onStatus: _onSttStatus,
    );

    if (!available) {
      _setState(
        VoiceListenState.error,
        error: 'Reconocimiento de voz no disponible en este dispositivo',
      );
      return;
    }

    if (!await _speech.hasPermission) {
      await _speech.initialize(onError: _onSttError, onStatus: _onSttStatus);
    }

    _localeId = _pickSpanishLocale(await _speech.locales());
    if (kDebugMode) {
      debugPrint('[Voice] locale=$_localeId');
    }

    _initialized = true;
    unawaited(_ensureGeminiInBackground());
    _setState(VoiceListenState.ready);
  }

  /// FAB: abre sesión de comando (micrófono activo).
  Future<void> beginCommandFromButton() async {
    if (_deviceCyclePaused || _busy) return;
    if (_commandActive ||
        _state == VoiceListenState.activeListening ||
        _state == VoiceListenState.processing) {
      return;
    }

    await ensureReady();
    if (_state == VoiceListenState.error || !_initialized) return;

    await _activateCommandSession('');
  }

  Future<void> stop() async {
    _initialized = false;
    _cancelCommandTimers();
    _peakDecayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    await _stopMic();
    _micLevel = 0;
    _micPeak = 0;
    _commandActive = false;
    _setState(VoiceListenState.off);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appInForeground = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (!_initialized) return;

    if (!_appInForeground && _commandActive) {
      unawaited(_finalizeCommand(force: true));
    }
  }

  String? _pickSpanishLocale(List<LocaleName> locales) {
    const preferred = [
      'es-ES',
      'es_ES',
      'es-MX',
      'es_MX',
      'es-US',
      'es_US',
      'es-419',
      'es_419',
    ];
    for (final id in preferred) {
      for (final l in locales) {
        if (l.localeId == id) return l.localeId;
      }
    }
    for (final l in locales) {
      if (l.localeId.startsWith('es')) return l.localeId;
    }
    return null;
  }

  Future<void> _ensureGeminiInBackground() async {
    if (_intentService.modelReady ||
        _intentService.loadState == GeminiIntentLoadState.failed) {
      return;
    }
    await _intentService.ensureModel(
      onProgress: (_) => _onStateChanged?.call(),
    );
  }

  Future<void> _openMicSessionForCommand() async {
    if (!_initialized || _deviceCyclePaused) return;
    if (!_commandActive) return;
    if (_speech.isListening || _openingSession) return;

    final ended = _lastMicSessionEndedAt;
    if (ended != null) {
      final sinceEnd = DateTime.now().difference(ended);
      const minGap = Duration(milliseconds: VoiceConstants.sttMinGapBetweenSessionsMs);
      if (sinceEnd < minGap) {
        await Future<void>.delayed(minGap - sinceEnd);
      }
    }

    _openingSession = true;
    try {
      await _stopMic(delayMs: VoiceConstants.sttStopDelayMs);
      await _speech.listen(
        onResult: _onSpeechResultCommand,
        onSoundLevelChange: _onSoundLevel,
        listenOptions: SpeechListenOptions(
          listenFor: VoiceConstants.commandSessionLength,
          pauseFor: VoiceConstants.commandPauseFor,
          partialResults: true,
          localeId: _localeId,
          cancelOnError: false,
          onDevice: false,
          listenMode: ListenMode.dictation,
        ),
      );
      _clientErrorStreak = 0;
    } catch (e) {
      if (kDebugMode) debugPrint('[Voice] command listen failed: $e');
      unawaited(_finalizeCommand(force: true));
    } finally {
      _openingSession = false;
    }
  }

  void _onSoundLevel(double level) {
    double normalized;
    if (level <= 0) {
      normalized = ((level + 50) / 50).clamp(0.0, 1.0);
    } else {
      normalized = (level / 12).clamp(0.0, 1.0);
    }

    _micPeak = math.max(_micPeak * 0.88, normalized);
    _micLevel = _micPeak;

    _peakDecayTimer?.cancel();
    _peakDecayTimer = Timer(const Duration(milliseconds: 350), () {
      _micPeak *= 0.55;
      _micLevel = _micPeak;
      _onStateChanged?.call();
    });

    _onStateChanged?.call();
  }

  void _onSttError(SpeechRecognitionError error) {
    if (kDebugMode) debugPrint('[Voice] STT error: ${error.errorMsg}');

    if (_isBenignSttError(error.errorMsg)) return;

    if (error.errorMsg.contains('permission') ||
        error.errorMsg.contains('audio')) {
      _setState(VoiceListenState.error, error: error.errorMsg);
      return;
    }

    if (_commandActive && !error.errorMsg.contains('network')) {
      _clientErrorStreak++;
      if (_clientErrorStreak <= 2) {
        unawaited(_openMicSessionForCommand());
        return;
      }
    }

    if (error.errorMsg.contains('network')) {
      _error = 'Sin internet para reconocimiento de voz';
      _onStateChanged?.call();
    }

    if (_commandActive) {
      unawaited(_finalizeCommand(force: true));
    }
  }

  void _onSttStatus(String status) {
    if (kDebugMode) debugPrint('[Voice] STT status: $status');
    if (status == 'done' && _commandActive) {
      unawaited(_handleCommandMicDone());
    }
  }

  bool _isBenignSttError(String msg) {
    const benign = ['error_speech_timeout', 'error_no_match'];
    return benign.any(msg.contains);
  }

  Future<void> _stopMic({int delayMs = 0}) async {
    try {
      if (_speech.isListening) await _speech.stop();
    } catch (e) {
      if (kDebugMode) debugPrint('[Voice] stop failed: $e');
    }
    _lastMicSessionEndedAt = DateTime.now();
    if (delayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: delayMs));
    }
  }

  Future<void> _activateCommandSession(String triggerText) async {
    if (!_initialized || _deviceCyclePaused || _busy) return;
    if (_commandActive) return;

    _commandActive = true;
    _commandSessionStartedAt = DateTime.now();
    _commandMicRetryUsed = false;
    _commandTranscript = triggerText.trim().isEmpty
        ? ''
        : FlushIntentHeuristic.extractAfterWakeWord(triggerText);
    _lastHeard =
        _commandTranscript.isEmpty ? 'Di tu comando…' : _commandTranscript;
    _lastAction = null;
    _micLevel = 0;
    _micPeak = 0;

    _setState(VoiceListenState.activeListening);
    _onStateChanged?.call();

    _commandSessionTimer?.cancel();
    _commandSessionTimer = Timer(VoiceConstants.commandSessionMaxDuration, () {
      if (_commandActive) {
        unawaited(_finalizeCommand(force: true));
      }
    });

    if (_hasCommandText()) {
      _scheduleFinalizeAfterWordsSettled();
    }

    await _openMicSessionForCommand();
  }

  bool _hasCommandText() {
    final t = _commandTranscript.trim();
    return t.isNotEmpty && t != 'Di tu comando…';
  }

  void _scheduleFinalizeAfterWordsSettled() {
    _commandFinalizeTimer?.cancel();
    _commandFinalizeTimer = Timer(VoiceConstants.commandWordsSettledDelay, () {
      if (_commandActive && !_evaluating) {
        unawaited(_finalizeCommand());
      }
    });
  }

  Future<void> _handleCommandMicDone() async {
    if (!_commandActive) return;
    if (_evaluating || _state == VoiceListenState.processing) return;

    _commandFinalizeTimer?.cancel();

    if (_hasCommandText()) {
      await _finalizeCommand();
      return;
    }

    final started = _commandSessionStartedAt;
    if (!_commandMicRetryUsed &&
        started != null &&
        DateTime.now().difference(started) < const Duration(milliseconds: 1200)) {
      _commandMicRetryUsed = true;
      await _openMicSessionForCommand();
      return;
    }

    await _finalizeCommand(force: true);
  }

  void _onSpeechResultCommand(SpeechRecognitionResult result) {
    if (_deviceCyclePaused || _busy || !_commandActive) return;

    final text = result.recognizedWords.trim();
    if (text.isEmpty) return;

    final afterWake = FlushIntentHeuristic.extractAfterWakeWord(text);
    final newText = afterWake.isNotEmpty ? afterWake : text;

    if (!result.finalResult) {
      _commandFinalizeTimer?.cancel();
      if (newText.length >= _commandTranscript.length ||
          newText != _commandTranscript) {
        _commandTranscript = newText;
        _lastHeard = newText;
        _onStateChanged?.call();

        if (FlushIntentHeuristic.isDeviceCommand(newText)) {
          _scheduleFinalizeAfterWordsSettled();
        }
      }
      return;
    }

    _commandTranscript = newText;
    _lastHeard = newText;
    _onStateChanged?.call();
    _scheduleFinalizeAfterWordsSettled();
  }

  Future<void> _finalizeCommand({bool force = false}) async {
    if (!_commandActive) return;
    if (_evaluating) return;

    _commandFinalizeTimer?.cancel();
    _commandSessionTimer?.cancel();
    await _stopMic();

    final command = _commandTranscript.trim();
    final empty = command.isEmpty || command == 'Di tu comando…';
    if (empty && !force) return;
    if (empty) {
      _lastAction = 'No escuché un comando';
      _onStateChanged?.call();
      await _dismissCommandSession();
      return;
    }

    await _evaluateCommand(command);
  }

  Future<void> _evaluateCommand(String command) async {
    if (_evaluating || _busy || _deviceCyclePaused) return;

    final cooldown = VoiceConstants.flushCooldown;
    final last = _lastDeviceTrigger;
    if (last != null && DateTime.now().difference(last) < cooldown) {
      _lastAction = 'Espera unos segundos antes de otro comando';
      _onStateChanged?.call();
      await _dismissCommandSession();
      return;
    }

    _evaluating = true;
    final generation = ++_evaluateGeneration;

    try {
      _setState(VoiceListenState.processing);

      final CommandIntentMatch match =
          await _intentService.classifyWithConfidence(command);

      if (!_initialized || generation != _evaluateGeneration) return;

      if (match.isAction && match.intent == DeviceVoiceIntent.refill) {
        _lastDeviceTrigger = DateTime.now();
        _lastAction = 'Recargando tanque…';
        _onStateChanged?.call();
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await pauseForDeviceCycle();
        _onRefillRequested?.call();
      } else if (match.isAction && match.intent == DeviceVoiceIntent.flush) {
        _lastDeviceTrigger = DateTime.now();
        _lastAction = 'Descargando…';
        _onStateChanged?.call();
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await pauseForDeviceCycle();
        _onFlushRequested?.call();
      } else {
        _lastAction = 'Comando no reconocido';
        _onStateChanged?.call();
        await _dismissCommandSession();
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Voice] evaluate failed: $e\n$st');
      }
      if (_initialized && !_deviceCyclePaused) {
        _lastAction = 'Error al analizar — intenta de nuevo';
        _onStateChanged?.call();
        await _dismissCommandSession();
      }
    } finally {
      _evaluating = false;
    }
  }

  Future<void> _dismissCommandSession({Duration? delay}) async {
    final wait = delay ?? VoiceConstants.bubbleDismissDelay;
    await Future<void>.delayed(wait);
    if (_deviceCyclePaused || !_initialized) return;

    _commandActive = false;
    _commandTranscript = '';
    _commandSessionStartedAt = null;
    _lastHeard = null;
    _lastAction = null;
    _micLevel = 0;
    _micPeak = 0;
    _setState(VoiceListenState.ready);
  }

  void _cancelCommandTimers() {
    _commandFinalizeTimer?.cancel();
    _commandSessionTimer?.cancel();
  }

  void _setState(VoiceListenState state, {String? error}) {
    _state = state;
    if (error != null) {
      _error = error;
    } else if (state == VoiceListenState.ready) {
      _error = null;
    }
    _onStateChanged?.call();
  }
}
