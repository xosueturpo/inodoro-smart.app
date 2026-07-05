import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';

/// Abre la tapa del inodoro (comando LID_OPEN → servo A3 a 85°).
class LidOpenButton extends StatelessWidget {
  const LidOpenButton({
    super.key,
    required this.enabled,
    required this.flushing,
    this.refilling = false,
    this.onOpen,
  });

  final bool enabled;
  final bool flushing;
  final bool refilling;
  final VoidCallback? onOpen;

  String get _subtitle {
    if (flushing) return 'Espera a que termine la descarga…';
    if (refilling) return 'Disponible durante la recarga';
    return 'Abre la tapa a 85° (también con sensor 5 cm)';
  }

  void _handleTap() {
    if (!enabled || flushing) return;
    HapticFeedback.lightImpact();
    onOpen?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final active = enabled && !flushing;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _handleTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: const Color(0xFF7C4DFF).withValues(alpha: 0.2),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: active
                  ? const [Color(0xFF4527A0), Color(0xFF7C4DFF)]
                  : const [Color(0xFF6B7280), Color(0xFF9CA3AF)],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.22),
            ),
            boxShadow: [
              if (active)
                BoxShadow(
                  color: const Color(0xFF7C4DFF).withValues(alpha: 0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(
                  Icons.flip_rounded,
                  color: Colors.white.withValues(alpha: active ? 1 : 0.65),
                  size: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Levantar tapa',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: active ? 1 : 0.7),
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.85),
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_up_rounded,
                  color: Colors.white.withValues(alpha: active ? 1 : 0.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
