import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../core/theme/app_theme.dart';
import '../services/voice_command_service.dart';

/// Botón flotante inferior derecho para activar comando de voz.
class VoiceCommandFab extends StatefulWidget {
  const VoiceCommandFab({
    super.key,
    required this.state,
    required this.enabled,
    required this.onPressed,
  });

  final VoiceListenState state;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  State<VoiceCommandFab> createState() => _VoiceCommandFabState();
}

class _VoiceCommandFabState extends State<VoiceCommandFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  bool get _active =>
      widget.state == VoiceListenState.activeListening ||
      widget.state == VoiceListenState.processing;

  @override
  Widget build(BuildContext context) {
    final disabled = !widget.enabled || widget.state == VoiceListenState.paused;

    return Semantics(
      button: true,
      enabled: !disabled,
      label: 'Comando de voz',
      child: GestureDetector(
        onTap: disabled ? null : widget.onPressed,
        child: SizedBox(
          width: 72,
          height: 72,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_active)
                ...List.generate(3, (i) {
                  return AnimatedBuilder(
                    animation: _waveController,
                    builder: (_, __) {
                      final t = (_waveController.value + i * 0.28) % 1.0;
                      final scale = 1.0 + t * 0.85;
                      final opacity = (1.0 - t).clamp(0.0, 1.0) * 0.55;
                      final color = i.isEven ? AppColors.accent : AppColors.success;
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: opacity),
                                blurRadius: 18,
                                spreadRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }),
              AnimatedBuilder(
                animation: _waveController,
                builder: (_, __) {
                  final pulse = (math.sin(_waveController.value * math.pi * 2) + 1) / 2;
                  final glow = _active ? 0.35 + pulse * 0.25 : 0.12 + pulse * 0.08;
                  return Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: _active
                            ? [
                                AppColors.accent,
                                Color.lerp(AppColors.accent, AppColors.success, pulse)!,
                              ]
                            : [
                                AppColors.accent.withValues(alpha: 0.85),
                                AppColors.success.withValues(alpha: 0.75),
                              ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.accent.withValues(alpha: glow),
                          blurRadius: 16,
                          spreadRadius: 2,
                        ),
                        BoxShadow(
                          color: AppColors.success.withValues(alpha: glow * 0.7),
                          blurRadius: 22,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Icon(
                      _iconForState(widget.state),
                      color: CupertinoColors.white,
                      size: 26,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForState(VoiceListenState state) {
    switch (state) {
      case VoiceListenState.processing:
        return CupertinoIcons.hourglass;
      case VoiceListenState.activeListening:
        return CupertinoIcons.mic_fill;
      case VoiceListenState.error:
        return CupertinoIcons.exclamationmark;
      case VoiceListenState.paused:
        return CupertinoIcons.pause_fill;
      default:
        return CupertinoIcons.mic;
    }
  }
}
