import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../services/voice_command_service.dart';

/// Burbuja tipo Bixby: solo visible tras detectar «Cover».
class VoiceAssistantBubble extends StatelessWidget {
  const VoiceAssistantBubble({
    super.key,
    required this.state,
    this.transcript,
    this.resultMessage,
    this.micLevel = 0,
    this.micSessionOpen = false,
  });

  final VoiceListenState state;
  final String? transcript;
  final String? resultMessage;
  final double micLevel;
  final bool micSessionOpen;

  static const _accentGreen = Color(0xFF34C759);

  @override
  Widget build(BuildContext context) {
    if (state != VoiceListenState.activeListening &&
        state != VoiceListenState.processing) {
      return const SizedBox.shrink();
    }

    final processing = state == VoiceListenState.processing;
    final isDark = AppTheme.isDark(context);
    final surface = isDark ? AppColors.darkSurfaceElevated : AppColors.lightSurface;
    final borderColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;
    final barValue = micSessionOpen
        ? (0.15 + micLevel * 0.85).clamp(0.15, 1.0)
        : micLevel.clamp(0.08, 1.0);
    final voiceDetected = micLevel > 0.12;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _BubbleIcon(processing: processing),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      processing ? 'Procesando…' : 'Te escucho',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.labelPrimary(context),
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkBg.withValues(alpha: 0.55)
                      : AppColors.lightBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: borderColor.withValues(alpha: 0.7),
                  ),
                ),
                child: Text(
                  transcript?.isNotEmpty == true ? transcript! : 'Di tu comando…',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: transcript?.isNotEmpty == true
                        ? AppTheme.labelPrimary(context)
                        : AppTheme.labelSecondary(context),
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
              if (!processing) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: barValue,
                    minHeight: 4,
                    backgroundColor:
                        AppTheme.labelSecondary(context).withValues(alpha: 0.18),
                    color: voiceDetected
                        ? _accentGreen
                        : _accentGreen.withValues(alpha: 0.4),
                  ),
                ),
              ],
              if (resultMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  resultMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: resultMessage!.contains('Descargando')
                        ? _accentGreen
                        : AppTheme.labelSecondary(context),
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BubbleIcon extends StatefulWidget {
  const _BubbleIcon({required this.processing});

  final bool processing;

  @override
  State<_BubbleIcon> createState() => _BubbleIconState();
}

class _BubbleIconState extends State<_BubbleIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.processing
        ? CupertinoIcons.sparkles
        : CupertinoIcons.mic_fill;
    final color = widget.processing ? AppColors.accent : VoiceAssistantBubble._accentGreen;

    return FadeTransition(
      opacity: Tween<double>(begin: 0.5, end: 1).animate(_ctrl),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }
}
