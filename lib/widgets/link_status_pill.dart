import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/device_models.dart';

class LinkStatusPill extends StatelessWidget {
  const LinkStatusPill({
    super.key,
    required this.linkState,
    this.channel,
  });

  final SessionLinkState linkState;
  final ConnectionChannel? channel;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon, showSpinner) = _resolveDisplay();

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: color.withValues(alpha: 0.55)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSpinner)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(icon, size: 16, color: color),
              ),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  (String, Color, IconData, bool) _resolveDisplay() {
    return switch (linkState) {
      SessionLinkState.error => (
          'Error en conexión',
          AppColors.danger,
          CupertinoIcons.exclamationmark_triangle_fill,
          false,
        ),
      SessionLinkState.reconnecting => (
          'Reconectando',
          AppColors.warning,
          CupertinoIcons.arrow_2_circlepath,
          true,
        ),
      SessionLinkState.connected => switch (channel) {
          ConnectionChannel.demo => (
              'Modo demo',
              const Color(0xFFFF9500),
              CupertinoIcons.play_circle_fill,
              false,
            ),
          ConnectionChannel.ble => (
              'Conectado · Bluetooth',
              AppColors.success,
              CupertinoIcons.checkmark_circle_fill,
              false,
            ),
          _ => (
              'Conectado · LAN',
              AppColors.success,
              CupertinoIcons.checkmark_circle_fill,
              false,
            ),
        },
    };
  }
}
