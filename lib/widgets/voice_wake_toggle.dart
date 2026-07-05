import 'package:flutter/cupertino.dart';

import '../core/constants/voice_constants.dart';
import '../core/theme/app_theme.dart';

/// Activa escucha de «Cover» bajo demanda (micrófono apagado por defecto).
class VoiceWakeToggle extends StatelessWidget {
  const VoiceWakeToggle({
    super.key,
    required this.enabled,
    required this.connected,
    required this.onChanged,
  });

  final bool enabled;
  final bool connected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: enabled
              ? AppColors.accent.withValues(alpha: 0.45)
              : AppTheme.border(context),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(
              enabled ? CupertinoIcons.mic_fill : CupertinoIcons.mic_slash,
              color: enabled ? AppColors.accent : AppTheme.labelSecondary(context),
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Voz «${VoiceConstants.wakeWordDisplay}»',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.labelPrimary(context),
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    enabled
                        ? 'Escuchando palabra clave (usa el micrófono)'
                        : 'Apagado — sin avisos ni pitidos del sistema',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.labelSecondary(context),
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
            CupertinoSwitch(
              value: enabled,
              onChanged: connected ? onChanged : null,
              activeTrackColor: AppColors.accent,
            ),
          ],
        ),
      ),
    );
  }
}
