import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';

/// Cierra la tapa del inodoro (comando LID_CLOSE → servo A3 a 0°).
class LidCloseButton extends StatelessWidget {
  const LidCloseButton({
    super.key,
    required this.enabled,
    required this.flushing,
    this.refilling = false,
    this.onClose,
  });

  final bool enabled;
  final bool flushing;
  final bool refilling;
  final VoidCallback? onClose;

  String get _subtitle {
    if (flushing) return 'No disponible durante la descarga…';
    if (refilling) return 'Disponible durante la recarga';
    return 'Cierra la tapa a 0°';
  }

  void _handleTap() {
    if (!enabled || flushing) return;
    HapticFeedback.lightImpact();
    onClose?.call();
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
        splashColor: const Color(0xFF546E7A).withValues(alpha: 0.2),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: active
                  ? const [Color(0xFF37474F), Color(0xFF546E7A)]
                  : const [Color(0xFF6B7280), Color(0xFF9CA3AF)],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.22),
            ),
            boxShadow: [
              if (active)
                BoxShadow(
                  color: const Color(0xFF546E7A).withValues(alpha: 0.28),
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
                        'Cerrar tapa',
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
                  Icons.keyboard_arrow_down_rounded,
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
