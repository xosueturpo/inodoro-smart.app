import '../models/command_intent_match.dart';
import '../models/device_voice_intent.dart';

/// Detección rápida de descarga / recarga sin IA (STT + variantes en español).
class FlushIntentHeuristic {
  FlushIntentHeuristic._();

  /// STT en español suele escribir Cover como cobre, kover, gober, etc.
  static final _wakePattern = RegExp(
    r'(cover|covers|kover|kaver|caver|gover|gober|kofer|cofer|qover|'
    r'cobre|cobert|cubrir|cubre|cuver|ko ver|co ver|cu ver|'
    r'kuber|kober|gaver|gauber|couvert|covar|cov er)',
    caseSensitive: false,
  );

  static const _refillStrong = [
    'recarga el tanque',
    'recargar el tanque',
    'recarga tanque',
    'recargar tanque',
    'llenar el tanque',
    'llena el tanque',
    'llenar tanque',
    'llena tanque',
    'llenar la cisterna',
    'llena la cisterna',
    'llenar cisterna',
    'llenar el deposito',
    'llena el deposito',
    'llenar deposito',
    'reponer agua',
    'repone agua',
    'echar agua al tanque',
    'echa agua al tanque',
    'agua al tanque',
    'cargar tanque',
    'carga de agua',
    'tanque vacio',
    'deposito vacio',
    'falta agua',
    'sin agua',
    'nivel bajo',
    'surtir agua',
    'surte agua',
    'recargar agua',
    'recarga agua',
    'llenar agua',
    'llena agua',
    'rellenar tanque',
    'rellena tanque',
    'poner agua',
    'pon agua',
    'echar agua',
    'echa agua',
    'llenar la reserva',
    'llena la reserva',
  ];

  static const _refillMedium = [
    'recarga',
    'recargar',
    'recargando',
    'recargalo',
    'recargala',
    'recargue',
    'recargues',
    'tanque',
    'cisterna',
    'deposito',
    'reserva',
    'rellenar',
    'rellena',
    'rellenando',
    'reponer',
    'repone',
    'llenar',
    'llena',
    'llenando',
    'llenalo',
    'llenala',
    'llene',
    'llenes',
    'surtir',
    'surte',
    'cargar',
    'carga',
    'agua nueva',
    'mas agua',
    'más agua',
    'agua por favor',
    'necesito agua',
    'ponle agua',
    'echarle agua',
    'echale agua',
    'échale agua',
  ];

  static const _refillWeak = [
    'agua',
    'liquido',
    'líquido',
    'nivel',
    'reservorio',
  ];

  static const _flushStrong = [
    'descarga el inodoro',
    'descargar el inodoro',
    'descarga el bano',
    'descarga el baño',
    'descargar el bano',
    'descargar el baño',
    'tirar la cadena',
    'tira la cadena',
    'jalar la cadena',
    'jala la cadena',
    'jalar cadena',
    'tirar cadena',
    'tira cadena',
    'vaciar el inodoro',
    'vacía el inodoro',
    'vaciar inodoro',
    'vacia inodoro',
    'vaciar el bano',
    'vaciar el baño',
    'limpia el inodoro',
    'limpiar el inodoro',
    'limpia el bano',
    'limpia el baño',
    'limpiar el bano',
    'limpiar el baño',
    'usa el inodoro',
    'usar el inodoro',
    'bajar la palanca',
    'baja la palanca',
    'tirar el agua',
    'tira el agua',
    'echar el agua',
    'echa el agua',
    'hacer la descarga',
    'haz la descarga',
    'activar descarga',
    'activa descarga',
    'iniciar descarga',
    'inicia descarga',
    'pull chain',
    'pull the chain',
  ];

  static const _flushMedium = [
    'descarga',
    'descargar',
    'descargando',
    'descargalo',
    'descargala',
    'descargue',
    'descargues',
    'vaciar',
    'vacía',
    'vacia',
    'vaciando',
    'vaciarlo',
    'vaciarla',
    'cadena',
    'jalar',
    'jala',
    'tirar',
    'tira',
    'flush',
    'bano',
    'baño',
    'inodoro',
    'wc',
    'sanitario',
    'retrete',
    'poceta',
    'taza',
    'water',
    'limpiar',
    'limpia',
    'limpiando',
    'limpieza',
    'moja',
    'mojar',
    'enjuagar',
    'enjuaga',
    'enjuague',
    'tirar agua',
    'tira agua',
    'usar bano',
    'usar baño',
    'ir al bano',
    'ir al baño',
    'necesito el bano',
    'necesito el baño',
    'por favor descarga',
    'por favor vacia',
    'por favor vacía',
  ];

  static const _flushWeak = [
    'hazlo',
    'haz lo',
    'dale',
    'ya',
    'ahora',
    'rapido',
    'rápido',
    'listo',
    'adelante',
    'venga',
    'por favor',
    'please',
    'go',
    'ok',
    'vale',
    'hecho',
    'activa',
    'activar',
    'ejecuta',
    'ejecutar',
    'corre',
    'funciona',
    'funcione',
  ];

  static final _refillRegex = [
    _ScoredRule(
      RegExp(
        r'\b(re|carga|llen|rellen|repon|surte)\w*\b.*\b(tanque|cisterna|deposito|reserva|agua)\b',
      ),
      4,
    ),
    _ScoredRule(
      RegExp(r'\b(tanque|cisterna|deposito)\b.*\b(vacio|bajo|falta|sin)\b'),
      4,
    ),
    _ScoredRule(
      RegExp(r'\b(falta|sin|necesito|pon|ponle|echar|echa|echale)\w*\b.*\bagua\b'),
      3,
    ),
    _ScoredRule(RegExp(r'\brecarg\w*\b'), 3),
    _ScoredRule(RegExp(r'\bllen\w*\b'), 2.5),
    _ScoredRule(RegExp(r'\brellen\w*\b'), 2.5),
  ];

  static final _flushRegex = [
    _ScoredRule(RegExp(r'\bdescarg\w*\b'), 3.5),
    _ScoredRule(RegExp(r'\bvaci\w*\b'), 3),
    _ScoredRule(RegExp(r'\b(jal|tir)\w*\b.*\bcadena\b'), 4),
    _ScoredRule(
      RegExp(r'\b(limp|enjuag|moj)\w*\b.*\b(bano|bano|inodoro|wc|taza)\b'),
      3.5,
    ),
    _ScoredRule(
      RegExp(
        r'\b(bano|bano|inodoro|wc|sanitario|retrete|poceta)\b.*\b(limp|descarg|vaci|usa|usar)\w*\b',
      ),
      3.5,
    ),
    _ScoredRule(RegExp(r'\b(cadena|flush|palanca)\b'), 2.5),
    _ScoredRule(RegExp(r'\b(bano|bano|inodoro|wc)\b'), 1.8),
  ];

  static const _refillBlockers = [
    'descarga',
    'descargar',
    'vaciar',
    'vacia',
    'cadena',
    'jalar',
    'tirar',
    'flush',
    'limpiar',
    'limpia',
    'inodoro',
    'bano',
    'baño',
  ];

  static const _flushBlockers = [
    'tanque',
    'cisterna',
    'deposito',
    'recarga',
    'recargar',
    'llenar',
    'llena',
    'rellenar',
    'rellena',
    'reponer',
    'reserva',
  ];

  static bool hasWakeWord(String text) {
    if (text.trim().isEmpty) return false;
    final normalized = _normalize(text);
    if (normalized.contains('cover')) return true;
    return _wakePattern.hasMatch(normalized);
  }

  static bool isFlushIntent(String text) {
    if (!hasWakeWord(text)) return false;
    return isFlushCommand(text);
  }

  static bool isRefillIntent(String text) {
    if (!hasWakeWord(text)) return false;
    return isRefillCommand(text);
  }

  static bool isRefillCommand(String text) {
    final match = classify(text);
    return match != null &&
        match.intent == DeviceVoiceIntent.refill &&
        match.confidence >= CommandIntentThresholds.accept;
  }

  static bool isFlushCommand(String text) {
    final match = classify(text);
    return match != null &&
        match.intent == DeviceVoiceIntent.flush &&
        match.confidence >= CommandIntentThresholds.accept;
  }

  static bool isDeviceCommand(String text) => isFlushCommand(text) || isRefillCommand(text);

  /// Clasificación local con puntuación. `null` = usar Gemini.
  static CommandIntentMatch? classify(String text) {
    final normalized = _normalize(text);
    if (normalized.isEmpty) return null;

    var refill = _scoreKeywords(normalized, _refillStrong, 3.5) +
        _scoreKeywords(normalized, _refillMedium, 2) +
        _scoreKeywords(normalized, _refillWeak, 0.8);
    var flush = _scoreKeywords(normalized, _flushStrong, 3.5) +
        _scoreKeywords(normalized, _flushMedium, 2) +
        _scoreKeywords(normalized, _flushWeak, 0.6);

    refill += _scoreRegex(normalized, _refillRegex);
    flush += _scoreRegex(normalized, _flushRegex);

    refill += _scoreFuzzyTokens(normalized, _refillTokenRoots, 1.4);
    flush += _scoreFuzzyTokens(normalized, _flushTokenRoots, 1.4);

    if (_containsAny(normalized, _refillBlockers) && refill < 2.5) {
      flush += 0.4;
    }
    if (_containsAny(normalized, _flushBlockers) && flush < 2.5) {
      refill += 0.4;
    }

    return _resolveScores(refill, flush);
  }

  static const _refillTokenRoots = [
    'recarg',
    'llen',
    'rellen',
    'repon',
    'tanque',
    'cisterna',
    'deposit',
    'reserv',
    'surt',
  ];

  static const _flushTokenRoots = [
    'descarg',
    'vaci',
    'cadena',
    'jalar',
    'tirar',
    'limp',
    'enjuag',
    'inodor',
    'bano',
    'baño',
    'flush',
    'sanit',
    'retret',
  ];

  static CommandIntentMatch? _resolveScores(double refill, double flush) {
    if (refill <= 0 && flush <= 0) return null;

    final total = refill + flush;
    final margin = (refill - flush).abs();
    final dominance = margin / total;

    if (refill >= 4 && refill >= flush + 1.2) {
      return CommandIntentMatch(
        intent: DeviceVoiceIntent.refill,
        confidence: _clamp01(0.62 + dominance * 0.35),
      );
    }
    if (flush >= 4 && flush >= refill + 1.2) {
      return CommandIntentMatch(
        intent: DeviceVoiceIntent.flush,
        confidence: _clamp01(0.62 + dominance * 0.35),
      );
    }

    if (dominance >= 0.38 && margin >= 1.4) {
      final intent =
          refill > flush ? DeviceVoiceIntent.refill : DeviceVoiceIntent.flush;
      return CommandIntentMatch(
        intent: intent,
        confidence: _clamp01(0.5 + dominance * 0.45),
      );
    }

    if (dominance >= 0.28 && margin >= 0.9 && total >= 2.2) {
      final intent =
          refill > flush ? DeviceVoiceIntent.refill : DeviceVoiceIntent.flush;
      return CommandIntentMatch(
        intent: intent,
        confidence: _clamp01(0.48 + dominance * 0.4),
      );
    }

    return null;
  }

  static double _scoreKeywords(String text, List<String> hints, double weight) {
    var score = 0.0;
    for (final hint in hints) {
      if (text.contains(hint)) score += weight;
    }
    return score;
  }

  static double _scoreRegex(String text, List<_ScoredRule> rules) {
    var score = 0.0;
    for (final rule in rules) {
      if (rule.pattern.hasMatch(text)) score += rule.weight;
    }
    return score;
  }

  static double _scoreFuzzyTokens(String text, List<String> roots, double weight) {
    final tokens = text.split(RegExp(r'\s+')).where((t) => t.length >= 4);
    var score = 0.0;
    for (final token in tokens) {
      for (final root in roots) {
        if (token.startsWith(root) || _levenshteinAtMost(token, root, 2)) {
          score += weight;
          break;
        }
      }
    }
    return score;
  }

  static bool _levenshteinAtMost(String a, String b, int maxDist) {
    if ((a.length - b.length).abs() > maxDist) return false;
    if (a == b) return true;
    if (a.startsWith(b) || b.startsWith(a)) return true;

    final m = a.length;
    final n = b.length;
    var prev = List<int>.generate(n + 1, (i) => i);
    var curr = List<int>.filled(n + 1, 0);

    for (var i = 1; i <= m; i++) {
      curr[0] = i;
      var rowMin = curr[0];
      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        curr[j] = [
          curr[j - 1] + 1,
          prev[j] + 1,
          prev[j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
        if (curr[j] < rowMin) rowMin = curr[j];
      }
      if (rowMin > maxDist) return false;
      final swap = prev;
      prev = curr;
      curr = swap;
    }
    return prev[n] <= maxDist;
  }

  static bool _containsAny(String text, List<String> hints) {
    for (final hint in hints) {
      if (text.contains(hint)) return true;
    }
    return false;
  }

  static double _clamp01(double v) => v.clamp(0.0, 1.0);

  static String extractAfterWakeWord(String text) {
    final normalized = _normalize(text);
    final match = _wakePattern.firstMatch(normalized);
    if (match != null) {
      return normalized.substring(match.end).trim();
    }
    const cover = 'cover';
    final idx = normalized.indexOf(cover);
    if (idx >= 0) {
      return normalized.substring(idx + cover.length).trim();
    }
    return normalized;
  }

  static String exampleCommand() =>
      'Toca el micrófono y di tu comando (descarga o recarga)';

  static String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^\w\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

class _ScoredRule {
  const _ScoredRule(this.pattern, this.weight);
  final RegExp pattern;
  final double weight;
}
