import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';

/// Botón para iniciar recarga del tanque (comando REFILL, sin descarga previa).
class TankRefillButton extends StatelessWidget {
  const TankRefillButton({
    super.key,
    required this.enabled,
    required this.busy,
    this.onRefill,
  });

  final bool enabled;
  final bool busy;
  final VoidCallback? onRefill;

  void _handleTap() {
    if (!enabled || busy) return;
    HapticFeedback.lightImpact();
    onRefill?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final active = enabled && !busy;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _handleTap,
        borderRadius: BorderRadius.circular(20),
        splashColor: const Color(0xFF00BCD4).withValues(alpha: 0.2),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: active
                  ? const [Color(0xFF006064), Color(0xFF00838F)]
                  : const [Color(0xFF6B7280), Color(0xFF9CA3AF)],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.22),
            ),
            boxShadow: [
              if (active)
                BoxShadow(
                  color: const Color(0xFF00BCD4).withValues(alpha: 0.28),
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
                  Icons.water_drop_rounded,
                  color: Colors.white.withValues(alpha: active ? 1 : 0.65),
                  size: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recargar tanque',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: active ? 1 : 0.7),
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        busy
                            ? 'Espera a que termine el ciclo actual…'
                            : 'Hasta nivel OK (sensor) · max 5 min',
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
                  Icons.play_arrow_rounded,
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
