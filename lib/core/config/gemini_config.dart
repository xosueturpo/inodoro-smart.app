import 'gemini_api_key_stub.dart'
    if (dart.library.io) 'gemini_api_key.local.dart';

/// Clave Gemini: `--dart-define=GEMINI_API_KEY=...` o `gemini_api_key.local.dart`.
abstract final class GeminiConfig {
  static String get apiKey {
    const fromEnv = String.fromEnvironment('GEMINI_API_KEY');
    if (fromEnv.isNotEmpty) return fromEnv;
    return kGeminiApiKey;
  }

  static bool get hasApiKey => apiKey.isNotEmpty;
}
